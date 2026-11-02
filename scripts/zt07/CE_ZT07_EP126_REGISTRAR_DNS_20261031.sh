#!/usr/bin/env bash
# EP126 / ZT-07.4: registrar teste DNS/HTTPS de 31/10/2026.
# Nao altera DNS, certificados, Twingate, Docker, pfSense ou tokens.
set -euo pipefail
set +x
umask 077

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARIO="$BASE/diario.md"
MARK="CE-ZT07-4-WAZUH-DNS-20261031"

if [[ "$(hostname -s)" != "ep126-pucpr-br" ]]; then
  echo "ERRO=HOST_INCORRETO"
  exit 2
fi
if [[ ! -f "$DIARIO" || ! -r "$DIARIO" || ! -w "$DIARIO" ]]; then
  echo "ERRO=DIARIO_INACESSIVEL"
  exit 3
fi
exec 9>"$BASE/.diario-zt07.lock"
flock -n 9 || { echo "ERRO=DIARIO_BLOQUEADO"; exit 4; }
if grep -Fq "$MARK" "$DIARIO"; then
  echo "REGISTRO_JA_EXISTE=SIM"
  echo "DIARIO_NAO_MODIFICADO=SIM"
  sha256sum "$DIARIO"
  exit 0
fi

STAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$DIARIO.bak.ZT074-$STAMP"
TMP="$(mktemp "$BASE/.diario-ZT074.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT
ANTES="$(sha256sum "$DIARIO" | awk '{print $1}')"
cp -p -- "$DIARIO" "$BACKUP"
cp -p -- "$DIARIO" "$TMP"

cat >> "$TMP" <<'REGISTRO'

---
## CE-ZT07-4-WAZUH-DNS-20261031 — DNS local e HTTPS com nome do certificado

Coleta ZT-07.4 de 31/10/2026, aproximadamente 19:43 BRT, EP126 ep126-pucpr-br. Evidencias transcritas das saidas compartilhadas pela operadora. Nao houve alteracoes na infraestrutura.

- O registrador ZT-07.3 foi executado: RESULTADO=DIARIO_LOCAL_ZT073_ATUALIZADO; marcador CE-ZT07-3-WAZUH-TLS-20261031.
- Backup ZT-07.3: /home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md.bak.ZT073-20261031T194257.
- SHA256 antes ZT-07.3: 04b26843f9464f5aac5eb3f66e8e911896303095880476454bfcaf0b7beb881d.
- SHA256 depois ZT-07.3: 11c42efd06af56a214cff5fce71418d34bea54764a2cf941e6ee85cb24236a1d.
- getent ahostsv4 wazuh.dashboard nao retornou enderecos: RESOLUCAO_HOST=NAO_ENCONTRADA.
- curl --resolve wazuh.dashboard:443:127.0.0.1 --insecure https://wazuh.dashboard/ respondeu HTTP=302, REMOTE_IP=127.0.0.1, CURL_RC=0.
- TLS_VALIDADO=NAO. --resolve mapeia o destino apenas para esse curl. Nao configura DNS, nao valida a cadeia TLS e nao comprova acesso via Twingate.
- Dashboard continua publicado no host em 127.0.0.1:443->5601/tcp. IP Docker 172.19.0.3 observado em ZT-07.2 e potencialmente efemero.
- Connector EP126 esta em network_mode=host. Nao foi comprovada resolucao DNS do proprio processo Connector. Connector pessoal openSUSE na mesma Remote Network nao compartilha loopback nem Docker da EP126.

Classificacao: HTTPS respondeu quando destino foi explicitamente forçado; DNS wazuh.dashboard nao foi resolvido pelo host; Zero Trust E2E, grupo/MFA e retestes PA-01..PA-07 NAO homologados. Nenhum Resource criado.

Proximos gates: confirmar resolucao pela instancia Connector, endereco privado estavel alcançavel pelo(s) Connector(s), CA/hostname, isolamento controlado do Connector pessoal com acesso alternativo, grupo Operacao/SOC e politica MFA, testes positivos/negativos. Nao modificar /etc/hosts, DNS, Compose, firewall ou certificados automaticamente.
REGISTRO

printf '\nRegistro inserido em %s.\n' "$(date -Is)" >> "$TMP"
mv -f -- "$TMP" "$DIARIO"
trap - EXIT
sha256sum "$DIARIO" > "$BASE/diario.sha256"

echo "RESULTADO=DIARIO_LOCAL_ZT074_ATUALIZADO"
echo "MARCADOR=$MARK"
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARIO"
echo "SHA256_ANTES=$ANTES"
echo "SHA256_DEPOIS=$(sha256sum "$DIARIO" | awk '{print $1}')"
echo "ALTERACAO_INFRAESTRUTURA=NAO"
