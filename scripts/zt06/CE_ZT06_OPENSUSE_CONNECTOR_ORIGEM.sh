#!/usr/bin/env bash
# CE ZT06 — openSUSE — investigacao somente leitura de Connector Twingate.
# Nao acessa tokens, variaveis de ambiente, docker inspect, logs ou conteudo de compose.
set -u
umask 077
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT="$HOME/ConectaEduca_Evidencias_Local/ZT06_OPENSUSE_ORIGEM_$STAMP"
mkdir -p "$OUT" || exit 1
REPORT="$OUT/resumo.txt"
{
 printf 'CE ZT06 OPEN-SUSE ORIGEM — %s\n' "$(date -Is)"
 printf 'HOST=%s\n' "$(hostname)"
 echo '=== Docker containers (nome, imagem, estado; sem detalhes sensiveis) ==='
 if command -v docker >/dev/null 2>&1; then
   docker ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | grep -Ei 'twingate|connector|permission denied|Cannot connect' || true
 else echo 'Docker nao encontrado'; fi
 echo '=== Podman containers (nome, imagem, estado) ==='
 if command -v podman >/dev/null 2>&1; then
   podman ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}' 2>&1 | grep -Ei 'twingate|connector|permission denied' || true
 else echo 'Podman nao encontrado'; fi
 echo '=== Servicos systemd com nome Twingate ==='
 systemctl list-units --all --type=service --no-pager --no-legend 2>&1 | grep -i twingate || true
 systemctl --user list-units --all --type=service --no-pager --no-legend 2>&1 | grep -i twingate || true
 echo '=== Arquivos Compose possiveis (somente caminhos, limite 25; sem abrir) ==='
 for d in "$HOME" /opt/conectaeduca; do
   [ -d "$d" ] || continue
   find "$d" -maxdepth 5 -type f \( -iname '*twingate*.yml' -o -iname '*twingate*.yaml' -o -iname '*twingate*.sh' \) -print 2>/dev/null | head -25
 done
 echo '=== Historico shell: SOMENTE contagem de referencias, sem linhas ou tokens ==='
 for f in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.local/share/fish/fish_history"; do
   if [ -r "$f" ]; then
     count="$(grep -Eic 'twingate|docker[[:space:]]+compose|podman[[:space:]]+compose' "$f" 2>/dev/null || true)"
     printf '%s: entradas_correspondentes=%s\n' "$(basename "$f")" "$count"
   fi
 done
 echo '=== Processos: apenas nome executavel ==='
 ps -eo comm= 2>&1 | grep -iE 'twingate|connector' | sort -u || true
 echo '=== Limites ==='
 echo 'Sem achados nao prova ausencia historica; compose pode ter outro nome e historico pode ser incompleto.'
 echo 'Hostname no painel indica maquina declarada pelo Connector, nao o metodo exato de instalacao.'
} > "$REPORT" 2>&1
sha256sum "$REPORT" > "$OUT/SHA256SUMS.txt"
printf 'RELATORIO=%s\nHASHES=%s\n' "$REPORT" "$OUT/SHA256SUMS.txt"
