#!/usr/bin/env bash
# ConectaEduca / EP126 / ZT-07.3: registro retrospectivo de evidencia TLS
# Somente adiciona ao diario.md; nao instala CA, nao muda Docker, rede ou servicos.
set -euo pipefail
set +x
umask 077

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARIO="$BASE/diario.md"
MARCADOR="CE-ZT07-3-WAZUH-TLS-20261031"

if [[ "$(hostname -s)" != "ep126-pucpr-br" ]]; then
  echo "ERRO=HOST_DIFERENTE_DA_EP126" >&2
  exit 2
fi
if [[ ! -f "$DIARIO" || ! -r "$DIARIO" || ! -w "$DIARIO" ]]; then
  echo "ERRO=DIARIO_AUSENTE_OU_SEM_PERMISSAO" >&2
  exit 3
fi

exec 9>"$BASE/.diario-zt07.lock"
flock -n 9 || { echo "ERRO=LOCK_INDISPONIVEL" >&2; exit 4; }

if grep -Fq "$MARCADOR" "$DIARIO"; then
  echo "REGISTRO_JA_EXISTE=SIM"
  echo "DIARIO_NAO_ALTERADO=SIM"
  sha256sum "$DIARIO"
  exit 0
fi

MOMENTO="$(date +%Y%m%dT%H%M%S)"
BACKUP="$DIARIO.bak.ZT073-$MOMENTO"
TMP="$(mktemp "$BASE/.diario-ZT073.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT
HASH_ANTES="$(sha256sum "$DIARIO" | awk '{print $1}')"

cp -p -- "$DIARIO" "$BACKUP"
cp -p -- "$DIARIO" "$TMP"

cat >> "$TMP" <<'EVIDENCIA'

---
## CE-ZT07-3-WAZUH-TLS-20261031 — Wazuh Dashboard, HTTPS e certificado

Coleta efetuada em 31/10/2026, 19:39:06 BRT, na EP126 ep126-pucpr-br, conforme saida apresentada pela operadora. Testes apenas de leitura; nao alteraram Wazuh, Twingate, Docker, CA ou pfSense.

### Resultados observados
- HTTPS no loopback 127.0.0.1:443: HTTP=302, CURL_RC=0 (teste curl --insecure para a conectividade).
- Redirecionamento: REDIRECT_ABSOLUTO=False; REDIRECT_PATH=/app/login; query=False; fragment=False. Redirecionamento relativo, sem troca obrigatoria de host.
- Certificado apresentado pelo servidor: subject C=US, L=California, O=Wazuh, OU=Wazuh, CN=wazuh.dashboard.
- Emissor: OU=Wazuh, O=Wazuh, L=California.
- Validade UTC: Aug 27 21:36:49 2026 ate Aug 24 21:36:49 2036.
- Subject Alternative Name: DNS:wazuh.dashboard (sem IP SAN observado).
- Verificacao curl SEM -k contra https://127.0.0.1/: erro 60; TLS_VERIFY=20; HTTP=000; CURL_RC=60. Mensagem: unable to get local issuer certificate.
- Sintese: servico HTTPS respondeu e apontou login; a cadeia de confianca apresentada nao foi validada pelo cliente. O teste realizado nao estabelece se HTTPS via wazuh.dashboard passaria a validacao de hostname apos provisionamento correto da CA; 127.0.0.1 nao consta no SAN.

### Classificacao e proximos passos
- PROVADO: redirect relativo /app/login; resposta HTTP302 com -k; certificado declarando DNS:wazuh.dashboard; falha de confianca em curl sem -k (verify20).
- NAO PROVADO: autenticidade da CA, hostname valido em cliente, sessao de login, acesso pelo Connector, protecao Twingate por grupo/MFA, reteste PA01..PA07.
- Proxima acao: inspecionar sem revelar chaves o nome wazuh.dashboard no DNS do host/Connector; testar SNI/hostname explicitamente, origem do certificado e CA interna apropriada; selecionar Resource alcançavel somente pelo Connector institucional antes de cadastramento.
- Nao cadastrar 127.0.0.1 como Resource remoto, nao aceitar o IP Docker efemero 172.19.0.3 como identificador permanente e nao publicar portas Wazuh na Intranet sem aprovacao.
- Evidencias: saidas de terminal trazidas pela operadora na sessao de 31/10/2026. Nenhuma chave privada, token ou certificado completo foi registrado.
EVIDENCIA

printf '\nMomento do registro local: %s\n' "$(date -Is)" >> "$TMP"
mv -f -- "$TMP" "$DIARIO"
trap - EXIT
sha256sum "$DIARIO" > "$BASE/diario.sha256"

echo "RESULTADO=DIARIO_LOCAL_ZT073_ATUALIZADO"
echo "MARCADOR=$MARCADOR"
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARIO"
echo "SHA256_ANTES=$HASH_ANTES"
echo "SHA256_DEPOIS=$(sha256sum "$DIARIO" | awk '{print $1}')"
echo "ALTERACAO_INFRAESTRUTURA=NAO"
