#!/usr/bin/env bash
# ConectaEduca / EP126 — registrar deploy Twingate em diario.md (31/10/2026).
# Idempotente, sem sudo, sem coleta/exibicao de tokens, sem alterar containers.
set -euo pipefail
set +x
umask 077

if [[ "$(hostname -s)" != "ep126-pucpr-br" ]]; then
  echo "ERRO: execute exclusivamente na EP126 (ep126-pucpr-br)." >&2
  exit 2
fi

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARY="$BASE/diario.md"
CONTAINER="conectaeduca-twingate-connector"
MARK="CE-ZT06-EP126-DEPLOY-20261031"
EXPECTED_IMAGE="sha256:0ef390ef3e526ba7cfb1c6504b794518226188c005087c95205fa9a5b769372a"

if [[ ! -f "$DIARY" || ! -w "$DIARY" ]]; then
  echo "ERRO: diario original inexistente ou sem permissao de escrita: $DIARY" >&2
  exit 3
fi
if grep -Fq "$MARK" "$DIARY"; then
  echo "REGISTRO_JA_EXISTE=SIM"
  echo "DIARIO_NAO_MODIFICADO=$DIARY"
  sha256sum "$DIARY"
  exit 0
fi

echo "=== CE / ZT-06 — VALIDACAO ANTES DO REGISTRO ==="
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}')
HEALTH=$(docker inspect "$CONTAINER" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}')
RESTARTS=$(docker inspect "$CONTAINER" --format '{{.RestartCount}}')
NETMODE=$(docker inspect "$CONTAINER" --format '{{.HostConfig.NetworkMode}}')
POLICY=$(docker inspect "$CONTAINER" --format '{{.HostConfig.RestartPolicy.Name}}')
IMAGE=$(docker inspect "$CONTAINER" --format '{{.Image}}')
VERSION=$(docker exec "$CONTAINER" ./connectord --version 2>&1 | tr -d '\r')

printf 'Running=%s Health=%s Reinicios=%s Rede=%s RestartPolicy=%s Versao=%s\n' \
 "$RUNNING" "$HEALTH" "$RESTARTS" "$NETMODE" "$POLICY" "$VERSION"

if [[ "$RUNNING" != true || "$HEALTH" != healthy || "$NETMODE" != host ]]; then
  echo "ERRO: estado atual divergente; diario preservado. Investigue antes do registro." >&2
  exit 4
fi
if [[ "$IMAGE" != "$EXPECTED_IMAGE" ]]; then
  echo "ERRO: imagem diverge do digest documentado; diario preservado." >&2
  exit 5
fi

STAMP=$(date +%Y%m%dT%H%M%S)
ISO_NOW=$(date -Is)
BACKUP="$DIARY.bak.ZT06-$STAMP"
TMP=$(mktemp "$BASE/.diario-zt06.XXXXXX")
trap 'rm -f "$TMP"' EXIT
cp -p -- "$DIARY" "$BACKUP"
cp -p -- "$DIARY" "$TMP"

cat >> "$TMP" <<'ENTRY'

---
## CE-ZT06-EP126-DEPLOY-20261031 — Twingate Connector institucional (31/10/2026, BRT)

### Resultado da implantacao (evidencias operacionais)
- Host: ep126-pucpr-br; operadora: andrea.kiew; Remote Network: ConectaEduca - Rede Interna; tenant: conectaeducalab.
- 18:45 BRT: preflight local; Docker Engine 29.9.2 e Compose v5.6.1; Docker funcional; nenhum Connector Twingate registrado na EP126 naquele instante; HTTPS externo de teste HTTP 200.
- Manifesto institucional: /opt/conectaeduca/deploy/interna/twingate/compose.yml, SHA256 ab78d9fcbea955f2141116daab3fea74b6ae2762aba4833aabc23e1f9d1edd29. Service connector; profile twingate; network_mode host; restart unless-stopped.
- Connector ja cadastrado como tall-centipede foi renomeado no painel para conectaeduca-interna-ep126. As credenciais proprias foram geradas e armazenadas fora do Git, em ~/.config/conectaeduca/twingate-ep126.env (permissao 0600); docker compose config --quiet retornou COMPOSE_VALIDADO=SIM. Nenhuma credencial transcrita.
- 19:07 BRT: implantacao do Connector na EP126 por Docker Compose (projeto conectaeduca-zt-ep126, service connector, profile twingate); imagem twingate/connector:1 obtida e contêiner conectaeduca-twingate-connector iniciado.
- O Compose versionado manteve digest antigo sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9. A implantacao REAL usa override local ~/.config/conectaeduca/twingate-ep126.override.yml, externo ao repositorio; reconciliar imagem/digest/rollback/CI em change control.
- 19:11:39 BRT: docker inspect registrou Running=true, Health=healthy, RestartCount=0, Rede=host, RestartPolicy=unless-stopped. docker ps: Up 4 minutes (healthy). Connector v1.95.0; ImageID sha256:0ef390ef3e526ba7cfb1c6504b794518226188c005087c95205fa9a5b769372a.
- Painel do Twingate (captura fornecida pela operadora): conectaeduca-interna-ep126 = Connected. O Connector pessoal conectaeduca-interna-01 no openSUSE tambem permanece Connected, sem homologacao como infraestrutura institucional.
- GitHub: documentacao adicionada na PR #214 (draft), branch docs/twingate-evidencias-20261031; Trello: ZT-06 e reconciliacao atualizados.

### Estado e limites
- CONCLUIDO: implantacao operacional basica, registro no painel, autenticacao e healthcheck do Connector institucional EP126.
- NAO HOMOLOGADO: alcance Graylog/Wazuh e demais Resources, entrega ao Twingate Client, MFA/grupos, testes de autorizacao positiva/negativa, isolamento, ausencia de bypass, acesso sem FortiClient e retestes PA-01 a PA-07.
- Dois Connectors Connected na mesma Remote Network impedem atribuir automaticamente qualquer teste exclusivamente a EP126. Isolamento temporario do Connector openSUSE apenas com acesso alternativo e janela segura.
- Nenhum firewall, pfSense, Bacula, Wazuh ou servico adicional foi alterado por este registro de diario.
ENTRY

printf '\n### Nova observacao local (%s)\n' "$ISO_NOW" >> "$TMP"
printf '%s\n' \
 "- Estado atual: Running=$RUNNING, Health=$HEALTH, Reinicios=$RESTARTS, Rede=$NETMODE, RestartPolicy=$POLICY, Versao=$VERSION." \
 "- Imagem atualmente observada: $IMAGE." >> "$TMP"

echo "=== HASHES E CUSTODIA ==="
echo -n "SHA256_ANTES="
sha256sum "$DIARY" | awk '{print $1}'
mv -f -- "$TMP" "$DIARY"
trap - EXIT
sha256sum "$DIARY" > "$BASE/diario.sha256"
echo -n "SHA256_DEPOIS="
sha256sum "$DIARY" | awk '{print $1}'
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARY"
echo "MARCADOR=$MARK"
echo "RESULTADO=DIARIO_LOCAL_ATUALIZADO"
