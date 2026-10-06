#!/usr/bin/env bash
# FREEZE-02 / EP125 - suplemento do handoff DMZ com overlays do runtime live.
#
# O handoff canonico c37bdce exclui deliberadamente compose.database.yml,
# mas o runtime final congelado da EP125 usa tres overlays que nao entram
# naquele bundle: database, database-tls e vm hardening.
#
# Este script NAO altera runtime nem main. Ele extrai esses tres arquivos
# diretamente do commit congelado, registra a ordem Compose observada no
# FREEZE-02 e gera pacote + hashes para acompanhar o handoff canonico.

EXPECTED_HEAD="c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce"
SHORT="c37bdce07a9a"
REPO="/opt/conectaeduca"
OUT="$HOME/Downloads"
[ -d "$OUT" ] || OUT="$HOME"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
ROOTNAME="conectaeduca-dmz-runtime-supplement-$SHORT"
BUNDLE="$OUT/$ROOTNAME.tar.gz"
REPORT="$OUT/conectaeduca-freeze02-dmz-runtime-supplement-$STAMP.txt"
TMP="$(mktemp -d -t conectaeduca-dmz-runtime-supplement-XXXXXX)"
FAIL=0

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

HOST="$(hostname)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null)"
DIRTY="$(git -C "$REPO" status --short 2>/dev/null)"

echo "=== FREEZE-02 / EP125 DMZ RUNTIME SUPPLEMENT ==="
echo "HOST=$HOST"
echo "HEAD=$HEAD"
echo "BRANCH=$BRANCH"

[ "$HOST" = "ep125-pucpr" ] || { echo "HOST_MATCH=FAIL"; FAIL=1; }
[ "$HEAD" = "$EXPECTED_HEAD" ] || { echo "HEAD_MATCH=FAIL"; FAIL=1; }
[ "$BRANCH" = "main" ] || { echo "BRANCH_MAIN=FAIL"; FAIL=1; }
[ -z "$DIRTY" ] || { echo "WORKTREE_CLEAN_BEFORE=FAIL"; printf '%s\n' "$DIRTY"; FAIL=1; }

STAGE="$TMP/$ROOTNAME"
mkdir -p "$STAGE/deploy/dmz"

extract_exact() {
  local rel="$1"
  if git -C "$REPO" cat-file -e "$EXPECTED_HEAD:$rel" 2>/dev/null; then
    git -C "$REPO" show "$EXPECTED_HEAD:$rel" > "$STAGE/$rel"
    echo "SOURCE_FILE=$rel|STATUS=EXTRACTED"
  else
    echo "SOURCE_FILE=$rel|STATUS=MISSING"
    FAIL=1
  fi
}

extract_exact "deploy/dmz/compose.database.yml"
extract_exact "deploy/dmz/compose.database-tls.yml"
extract_exact "deploy/dmz/compose.vm.yml"

cat > "$STAGE/README-FREEZE02.txt" <<EOF
ConectaEduca FREEZE-02 — suplemento de runtime DMZ
=================================================

Commit fonte:
$EXPECTED_HEAD

Finalidade:
Este pacote acompanha o handoff DMZ canonico gerado para o mesmo commit.
Ele contem somente overlays versionados que fazem parte da composicao live
final da EP125 e que nao entram no bundle canonico de handoff.

Arquivos:
- deploy/dmz/compose.database.yml
- deploy/dmz/compose.database-tls.yml
- deploy/dmz/compose.vm.yml

Nenhum segredo de runtime e incluido. Os paths de secrets permanecem apenas
como referencias declarativas e devem ser materializados no host.

Ordem Compose validada no FREEZE-02 da EP125:
1. deploy/dmz/compose.yml
2. deploy/dmz/compose.database.yml
3. deploy/dmz/compose.app-secrets.yml
4. deploy/dmz/compose.waf.yml
5. deploy/dmz/compose.waf-tls.yml
6. deploy/dmz/compose.waf-policy.yml
7. deploy/dmz/compose.host.yml
8. deploy/dmz/compose.vm.yml
9. deploy/dmz/compose.database-tls.yml

Este suplemento nao substitui o handoff canonico; deve ser arquivado junto a ele.
EOF

cat > "$STAGE/RELEASE-METADATA.txt" <<EOF
project=ConectaEduca
artifact=dmz-runtime-supplement
git_commit=$EXPECTED_HEAD
git_short=$SHORT
source=exact_git_commit
runtime_secrets_included=no
purpose=preserve_live_freeze02_compose_overlays
EOF

if find "$STAGE" -type f -printf '%P\n' | grep -Eq '(^|/)\.runtime(/|$)|(^|/)\.env$|(^|/).*\.(key|pem)$'; then
  echo "FORBIDDEN_PATHS=FOUND"
  FAIL=1
else
  echo "FORBIDDEN_PATHS=NONE"
fi

if grep -RIlE -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' "$STAGE" 2>/dev/null | grep -q .; then
  echo "PRIVATE_KEY_MATERIAL=FOUND"
  FAIL=1
else
  echo "PRIVATE_KEY_MATERIAL=NONE"
fi

(
  cd "$STAGE" &&
  find . -type f ! -name SHA256SUMS -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum
) > "$STAGE/SHA256SUMS"

if (
  cd "$STAGE" &&
  sha256sum -c SHA256SUMS >/dev/null
); then
  echo "INTERNAL_SHA256SUMS=PASS"
else
  echo "INTERNAL_SHA256SUMS=FAIL"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  (
    cd "$TMP" &&
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf "$BUNDLE" "$ROOTNAME"
  )
  TAR_RC=$?
else
  TAR_RC=99
fi
echo "BUNDLE_CREATE_RC=$TAR_RC"
[ "$TAR_RC" -eq 0 ] || FAIL=1

if [ "$FAIL" -eq 0 ]; then
  BUNDLE_SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
  printf '%s  %s\n' "$BUNDLE_SHA" "$(basename "$BUNDLE")" > "$BUNDLE.sha256"
else
  BUNDLE_SHA="NOT_CREATED"
fi

DIRTY_AFTER="$(git -C "$REPO" status --short 2>/dev/null)"
[ -z "$DIRTY_AFTER" ] || FAIL=1

{
  echo "=== CONECTAEDUCA FREEZE-02 / DMZ RUNTIME SUPPLEMENT ==="
  echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HOST=$HOST"
  echo "HEAD=$HEAD"
  echo "BRANCH=$BRANCH"
  echo "BUNDLE=$BUNDLE"
  echo "BUNDLE_SHA256=$BUNDLE_SHA"
  echo "BUNDLE_CREATE_RC=$TAR_RC"
  echo "WORKTREE_CLEAN_AFTER=$([ -z "$DIRTY_AFTER" ] && echo PASS || echo FAIL)"
  if [ "$FAIL" -eq 0 ]; then
    echo "FREEZE02_DMZ_RUNTIME_SUPPLEMENT=PASS"
  else
    echo "FREEZE02_DMZ_RUNTIME_SUPPLEMENT=FAIL"
  fi
  echo "SECRET_VALUES_RECORDED=NO"
} > "$REPORT"

sha256sum "$REPORT" > "$REPORT.sha256"
echo "REPORT=$REPORT"
echo "REPORT_SHA256=$(awk '{print $1}' "$REPORT.sha256")"
echo "BUNDLE=$BUNDLE"
echo "BUNDLE_SHA256=$BUNDLE_SHA"

[ "$FAIL" -eq 0 ]
