#!/usr/bin/env bash
# EP126 / ZT-07.6 — registro de evidencia da parada do Connector pessoal.
# Nao modifica Twingate, Docker, Wazuh, firewall, credenciais ou rede.
set -euo pipefail
set +x
umask 077

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARIO="$BASE/diario.md"
MARK="CE-ZT076-ISOLAMENTO-VALIDADO-20261031"

[[ "$(hostname -s)" == "ep126-pucpr-br" ]] || { echo "ERRO=HOST_INCORRETO"; exit 2; }
[[ -r "$DIARIO" && -w "$DIARIO" ]] || { echo "ERRO=DIARIO_INACESSIVEL"; exit 3; }

exec 9>"$BASE/.diario-zt07.lock"
flock -n 9 || { echo "ERRO=REGISTRO_EM_USO"; exit 4; }
if grep -Fq "$MARK" "$DIARIO"; then
  echo "REGISTRO_JA_EXISTE=SIM"
  echo "DIARIO_NAO_ALTERADO=SIM"
  sha256sum "$DIARIO"
  exit 0
fi

CONNECTOR="conectaeduca-twingate-connector"
RUNNING="$(docker inspect "$CONNECTOR" --format '{{.State.Running}}')"
HEALTH="$(docker inspect "$CONNECTOR" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}')"
RESTARTS="$(docker inspect "$CONNECTOR" --format '{{.RestartCount}}')"
if [[ "$RUNNING" != true || "$HEALTH" != healthy ]]; then
  echo "ERRO=CONNECTOR_INSTITUCIONAL_NAO_SAUDAVEL" >&2
  echo "DIARIO_NAO_MODIFICADO=SIM"
  exit 5
fi

STAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$DIARIO.bak.ZT076-$STAMP"
TMP="$(mktemp "$BASE/.diario-ZT076.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT
ANTES="$(sha256sum "$DIARIO" | awk '{print $1}')"
cp -p -- "$DIARIO" "$BACKUP"
cp -p -- "$DIARIO" "$TMP"

cat >> "$TMP" <<'EVIDENCIA'

---
## CE-ZT076-ISOLAMENTO-VALIDADO-20261031 — Connectors Twingate

Evidencias de 31/10/2026 fornecidas pela responsavel a partir de terminais e captura do painel. Nao constituem verificacao remota independente.

- A tentativa inicial de isolamento no openSUSE foi cancelada por falta de confirmacao interativa e nao parou o contêiner.
- A execucao corrigida ocorreu no computador pessoal opensuse-andrea, Docker context=default, Docker host=opensuse-andrea, Compose project=twingate e service=connector.
- A operadora digitou a confirmacao manual ISOLAR-OPENSUSE.
- Docker stop concluiu a parada do conteiner pessoal conectaeduca-twingate-connector: Running=false, Status=exited, ZT076_ISOLAMENTO_CONCLUIDO=SIM. O aviso de depreciacao de --time nao impediu a parada.
- Captura do Twingate na Remote Network ConectaEduca - Rede Interna: conectaeduca-interna-01 = Could not connect; conectaeduca-interna-ep126 = Connected.
- Comando diagnostico posterior no terminal da EP126: Running=true, Health=healthy, RestartCount=0.
- Conclusao: Connector pessoal isolado e Connector institucional conectado/saudavel no instante das verificacoes.
- NAO HOMOLOGADO: Resource Wazuh, politica MFA/grupos, CA TLS, acesso fim a fim e retestes PA-01 a PA-07.
- Proposta ainda nao aplicada: Resource privado do Wazuh Dashboard via Connector EP126, destino loopback, alias wazuh.dashboard, TCP/443 e grupo autorizado de Operacao/SOC; requer teste seguro de roteamento e validacao HTTPS.
- Reversao prevista, se necessaria e autorizada, no openSUSE: docker start conectaeduca-twingate-connector.
- Nenhum token, segredo nem certificado privado foi registrado.
EVIDENCIA

printf '\nRegistro local inserido em %s; estado atual EP126 Running=%s Health=%s RestartCount=%s.\n' \
  "$(date -Is)" "$RUNNING" "$HEALTH" "$RESTARTS" >> "$TMP"

mv -f -- "$TMP" "$DIARIO"
trap - EXIT
sha256sum "$DIARIO" > "$BASE/diario.sha256"

echo "RESULTADO=DIARIO_LOCAL_ZT076_ATUALIZADO"
echo "MARCADOR=$MARK"
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARIO"
echo "SHA256_ANTES=$ANTES"
echo "SHA256_DEPOIS=$(sha256sum "$DIARIO" | awk '{print $1}')"
echo "CONNECTOR_EP126=RUNNING_$RUNNING-HEALTH_$HEALTH-RESTARTS_$RESTARTS"
echo "ALTERACOES_INFRAESTRUTURA=NAO"
