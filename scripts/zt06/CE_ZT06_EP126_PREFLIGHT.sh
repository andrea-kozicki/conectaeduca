#!/usr/bin/env bash
# CE ZT-06: preflight SOMENTE LEITURA, sem sudo, sem tokens, sem mudancas de rede.
set -u
umask 077
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="${HOME}/ConectaEduca_Fase2_Evidencias/EP126/ZT06_PREFLIGHT_${STAMP}"
mkdir -p "$OUT" || exit 1
REPORT="$OUT/resumo.txt"
{
 echo "CE ZT06 EP126 — READ ONLY — $(date -Is)"
 echo "Host: $(hostname)"
 echo "=== Interfaces IPv4 ==="
 ip -o -4 addr show scope global 2>&1 | sed -E 's/(inet )([0-9.]+\/)[0-9]+/\1\2MASK/'
 echo "=== Rota default ==="
 ip -4 route show default 2>&1
 echo "=== Docker disponivel ==="
 docker info --format 'Server={{.ServerVersion}}' 2>&1 || true
 echo "=== Containers Twingate existentes (nomes/estado) ==="
 docker ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | grep -iE 'twingate|^Error|permission denied' || true
 echo "=== Redes Docker (nomes/driver) ==="
 docker network ls --format '{{.Name}} | {{.Driver}}' 2>&1 || true
 echo "=== Portas relevantes em escuta (SEM processos) ==="
 ss -ltnH 2>&1 | awk '$4 ~ /:(3390|9000|9101|9102|9103|1514|1515|3306|18200|9443)$/ {print $1,$4}' || true
 echo "=== Teste DNS de endpoint publico (sem autenticacao) ==="
 getent ahostsv4 connect.twingate.com 2>&1 | awk 'NR<=3 {print $1}' || true
 echo "=== Egress HTTPS publico — apenas status HTTP ==="
 curl -4 -sS -o /dev/null --connect-timeout 4 --max-time 10 -w 'http_code=%{http_code} tls_verify=%{ssl_verify_result}\n' https://connect.twingate.com 2>&1 || true
 echo "=== Conclusao ==="
 echo "Nao comprova conectividade com todos os endpoints Twingate, autorizacao, ou aptidao para deploy."
} > "$REPORT" 2>&1
sha256sum "$REPORT" > "$OUT/SHA256SUMS.txt"
echo "RELATORIO=$REPORT"
echo "HASHES=$OUT/SHA256SUMS.txt"
echo "Nao envie arquivos com enderecos internos publicamente sem revisao."
