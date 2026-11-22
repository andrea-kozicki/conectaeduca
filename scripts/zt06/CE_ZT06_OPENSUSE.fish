#!/usr/bin/env fish
# CE ZT-06: snapshot somente leitura do cliente openSUSE.
# Nao conecta/desconecta Twingate, nao altera rotas, nem desliga FortiClient.
set stamp (date +%Y%m%dT%H%M%S)
set out "$HOME/CE_Twingate_Logs/ZT06_CLIENTE_$stamp"
mkdir -p "$out"
chmod 700 "$out"
echo "=== DATA ===" | tee "$out/resumo.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' | tee -a "$out/resumo.txt"
echo "=== SERVICO ===" | tee -a "$out/resumo.txt"
systemctl is-active twingate.service | tee -a "$out/resumo.txt"
echo "=== CLIENTE ===" | tee -a "$out/resumo.txt"
twingate status | tee -a "$out/resumo.txt"
echo "=== RECURSOS ===" | tee -a "$out/resumo.txt"
twingate resources | tee -a "$out/resumo.txt"
echo "=== ROTA ===" | tee -a "$out/resumo.txt"
ip -4 route get 192.168.6.34 | tee -a "$out/resumo.txt"
echo "=== INTERFACE ===" | tee -a "$out/resumo.txt"
ip -brief address show sdwan0 | tee -a "$out/resumo.txt"
echo "=== FIM ==="
sha256sum "$out/resumo.txt" > "$out/SHA256SUMS.txt"
echo "Arquivo: $out/resumo.txt"
echo "Nao execute curl para a aplicacao se o recurso estiver ausente ou a rota nao usar sdwan0."
