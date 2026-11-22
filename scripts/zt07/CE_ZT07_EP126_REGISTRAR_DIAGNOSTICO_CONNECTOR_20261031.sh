#!/usr/bin/env bash
# EP126 / ZT-07.5 — Registro do teste OCI sem shell no Twingate Connector.
# Não altera Docker, Twingate, Wazuh, DNS, certificados ou pfSense.
set -euo pipefail
set +x
umask 077

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARIO="$BASE/diario.md"
MARK="CE-ZT07-5-CONNECTOR-SEM-SHELL-20261031"

[[ "$(hostname -s)" == "ep126-pucpr-br" ]] || { echo "ERRO=HOST_INCORRETO"; exit 2; }
[[ -f "$DIARIO" && -w "$DIARIO" ]] || { echo "ERRO=DIARIO_INDISPONIVEL"; exit 3; }
exec 9>"$BASE/.diario-zt07.lock"
flock -n 9 || { echo "ERRO=LOCK_INDISPONIVEL"; exit 4; }

if grep -Fq "$MARK" "$DIARIO"; then
  echo "REGISTRO_JA_EXISTE=SIM"
  sha256sum "$DIARIO"
  exit 0
fi

STAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$DIARIO.bak.ZT075-$STAMP"
TMP="$(mktemp "$BASE/.diario-ZT075.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT
ANTES="$(sha256sum "$DIARIO" | awk '{print $1}')"
cp -p "$DIARIO" "$BACKUP"
cp -p "$DIARIO" "$TMP"

cat >> "$TMP" <<'REGISTRO'

---
## CE-ZT07-5-CONNECTOR-SEM-SHELL-20261031 — Limite da coleta DNS

Coleta ZT-07.5 de 31/10/2026, aproximadamente 19:49 BRT, EP126. Registro retrospectivo de saída compartilhada pela operadora. Nenhum serviço foi alterado.

- ZT-07.4 foi registrado no diário: RESULTADO=DIARIO_LOCAL_ZT074_ATUALIZADO.
- Backup criado: /home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md.bak.ZT074-20261031T194911.
- SHA256 anterior: 11c42efd06af56a214cff5fce71418d34bea54764a2cf941e6ee85cb24236a1d.
- SHA256 posterior: 44bde5d9c59b1930ac7b42ec345ab5c734a002f847f6f9292c56ddcce3882966.
- Docker inspect do Twingate Connector: Running=true, NetworkMode=host.
- Tentativa de docker exec ... sh -c <consulta DNS> falhou no runtime OCI: exec: "sh": executable file not found in $PATH.
- Classificação: FERRAMENTA INDISPONIVEL; nenhuma consulta DNS chegou a executar dentro do Connector. Portanto NÃO classificar como erro DNS interno, nem problema no Twingate; saúde prévia do Connector preservada.
- Host EP126 previamente não resolveu wazuh.dashboard; teste curl com --resolve + --insecure mostrou HTTPS HTTP302, sem validar DNS real, CA ou E2E.
- Wazuh Dashboard permanece publicado somente em 127.0.0.1:443 (host), redirecionamento relativo /app/login, certificado SAN DNS:wazuh.dashboard.
- Proposta a avaliar por change control: Resource privado no Twingate com endereço de destino 127.0.0.1 e alias wazuh.dashboard, TCP/443, restrito a Operação/SOC e MFA. A proposta NÃO foi aplicada/testada e só pode ser avaliada após isolar o Connector pessoal openSUSE da mesma Remote Network, com acesso alternativo e autorização. Alias pode fornecer nome de acesso ao Client; não supre confiança na CA Wazuh.
- Permanecem pendentes: viabilidade do Resource e alias com este Connector, TLS confiável, testes positivos/negativos, rota pelo Connector EP126, políticas e retestes PA-01..PA-07.
REGISTRO

printf '\nRegistro efetuado em %s.\n' "$(date -Is)" >> "$TMP"
mv -f "$TMP" "$DIARIO"
trap - EXIT
sha256sum "$DIARIO" > "$BASE/diario.sha256"
echo "RESULTADO=DIARIO_LOCAL_ZT075_ATUALIZADO"
echo "MARCADOR=$MARK"
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARIO"
echo "SHA256_ANTES=$ANTES"
echo "SHA256_DEPOIS=$(sha256sum "$DIARIO" | awk '{print $1}')"
echo "ALTERACAO_INFRAESTRUTURA=NAO"
