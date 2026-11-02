#!/usr/bin/env bash
# CE ZT06: localizar possivel Connector Twingate na EP126. Somente leitura.
set -u
umask 077
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="$BASE/ZT06_CONNECTOR_ORIGIN_$STAMP"
mkdir -p "$OUT" || exit 1
R="$OUT/resumo.txt"
{
 echo "ZT06 CONNECTOR ORIGIN — READ ONLY — $(date -Is)"
 echo "HOST=$(hostname)"
 echo "=== Docker: imagens/nomes com Twingate ==="
 docker ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | grep -Ei 'twingate|connector' || echo "Nenhum container identificado"
 echo "=== Podman (se presente) ==="
 if command -v podman >/dev/null 2>&1; then podman ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | grep -Ei 'twingate|connector' || echo "Nenhum container identificado"; else echo "Podman nao instalado"; fi
 echo "=== Units systemd Twingate (nomes/estados) ==="
 systemctl list-units --all --type=service --no-pager --no-legend 2>&1 | grep -i twingate || echo "Nenhuma unit carregada identificada"
 echo "=== Arquivos unit instalados (somente nomes) ==="
 systemctl list-unit-files --type=service --no-pager --no-legend 2>&1 | grep -i twingate || echo "Nenhuma unit identificada"
 echo "=== Processos (somente nomes, sem argumentos ou segredos) ==="
 ps -eo comm= 2>&1 | grep -iE 'twingate|connector' | sort -u || echo "Nenhum processo identificado"
 echo "=== Rota ate EP125 (sem pacotes) ==="
 ip route get 192.168.6.34 2>&1 | sed -E 's/ uid [0-9]+//g'
 echo "=== Aviso ==="
 echo "Painel Connected nao identifica host de execucao nem prova acesso a recursos. Nao instalar conector duplicado."
} > "$R" 2>&1
sha256sum "$R" > "$OUT/SHA256SUMS.txt"
echo "RELATORIO=$R"
echo "HASHES=$OUT/SHA256SUMS.txt"
