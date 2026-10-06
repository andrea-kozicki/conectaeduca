#!/usr/bin/env bash
# FREEZE-02 - manifesto e pacote final de um diretorio de evidencias ja montado.
# Uso: ./50-empacotar-evidencias.sh /caminho/para/conectaeduca-freeze02-final
# Nao busca arquivos automaticamente: o diretorio deve ser revisado antes.

SRC="$1"
FAIL=0

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "USO=$0 /diretorio/de/evidencias"
  false
else
  SRC="$(cd "$SRC" 2>/dev/null && pwd -P)"
  PARENT="$(dirname "$SRC")"
  BASE="$(basename "$SRC")"
  STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
  SUMS="$SRC/SHA256SUMS"
  ARCHIVE="$PARENT/$BASE-$STAMP.tar.gz"

  echo "SOURCE=$SRC"

  BAD="$(find "$SRC" -type f -printf '%P\n' | grep -Ei '(^|/)(secret-id|role-id|root-token|unseal-share|recovery-share)$|\.key$|\.pem$|(^|/)\.env$' || true)"
  if [ -n "$BAD" ]; then
    echo "FORBIDDEN_PATHS=FOUND"
    printf '%s\n' "$BAD"
    FAIL=1
  else
    echo "FORBIDDEN_PATHS=NONE"
  fi

  if grep -RIlE -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' "$SRC" 2>/dev/null | grep -q .; then
    echo "PRIVATE_KEY_HEADER=FOUND"
    FAIL=1
  else
    echo "PRIVATE_KEY_HEADER=NONE"
  fi

  if [ "$FAIL" -eq 0 ]; then
    (
      cd "$SRC" || return 1
      find . -type f ! -name SHA256SUMS -print0         | LC_ALL=C sort -z         | xargs -0 sha256sum
    ) > "$SUMS"

    sha256sum -c "$SUMS"
    CHECK_RC=$?
    echo "MANIFEST_CHECK_RC=$CHECK_RC"
    [ "$CHECK_RC" -eq 0 ] || FAIL=1
  fi

  if [ "$FAIL" -eq 0 ]; then
    tar -C "$PARENT" -czf "$ARCHIVE" "$BASE"
    TAR_RC=$?
    echo "PACKAGE_RC=$TAR_RC"
    [ "$TAR_RC" -eq 0 ] || FAIL=1
  fi

  if [ "$FAIL" -eq 0 ]; then
    sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
    echo "PACKAGE=$ARCHIVE"
    echo "PACKAGE_SHA256=$(awk '{print $1}' "$ARCHIVE.sha256")"
    echo "MANIFEST=$SUMS"
    echo "FREEZE02_PACKAGE=PASS"
  else
    echo "FREEZE02_PACKAGE=FAIL"
  fi

  [ "$FAIL" -eq 0 ]
fi
