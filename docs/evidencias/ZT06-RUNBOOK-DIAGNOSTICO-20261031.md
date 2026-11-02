# ZT-06 — Diagnostico seguro de intermitencia Twingate (31/10/2026)

## Estado comprovado
- EP125: conector Docker running/healthy sem reinicios durante 21 amostras de 10 min; erros pubnub-lib TLS/SSL codigo 104 em 16:11:16Z e 16:15:59Z (intervalo 283,67 s).
- Painel alternou Connected (Controller e Relay conectados) e Could not connect. Nao se conhece duracao exata de cada estado.
- Do namespace do conector para 192.168.6.34:443: HTTP 200 com -k, portanto certificado nao validado.
- openSUSE: cliente online, mas recurso ConectaEducaAPP desapareceu e rota mudou de sdwan0 para wlan0. Timeout nessa rota nao demonstra falha do tunel.
- Grupo CE-PORTAL, membro autorizado e recurso TCP443 presentes no painel.
- Zero Trust E2E e teste sem FortiClient: NAO homologados.

## Scripts preparados, NAO executados
- `scripts/zt06/CE_ZT06_EP125_DIAG.sh`: fotografia Docker e agregacao local de erros dos ultimos 15 minutos. Armazena logs brutos privados (600); publica apenas resumo agregado.
- `scripts/zt06/CE_ZT06_OPENSUSE.fish`: snapshot de servico, recursos, rota e interface, sem alterar sessao.

## Execucao futura
EP125 (Bash): `bash scripts/zt06/CE_ZT06_EP125_DIAG.sh`
openSUSE (fish): `fish scripts/zt06/CE_ZT06_OPENSUSE.fish`

Scripts precisam estar presentes na maquina antes da execucao; caminhos acima sao relativos a raiz do repositorio. Nao exigem sudo, mas o script EP125 exige acesso Docker ja existente. Docker logs podem conter dados sensiveis; NAO enviar o arquivo PRIVADO. O snapshot openSUSE pode expor IPs privados; revisar antes de publicar.

## Proximo gate
1. Comparar estados do painel Controller/Relay com horarios UTC dos erros.
2. Se necessario, suporte verificar conexoes persistentes, proxy/inspecao TLS e resets de rede, sem assumir culpa do pfSense.
3. Investigar entrega de recurso ao cliente se continuar ausente mesmo com conector Connected.
4. Somente depois de estabilidade: teste de acesso via sdwan0 e homologacao sem FortiClient, com plano de retorno.

Sem merges, alteracoes de firewall, reinicios, rotacao de tokens ou mudancas nas VMs nesta preparacao.
