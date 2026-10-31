# Diario operacional complementar — EP126 — 31/10/2026 (BRT)

## Evidencias observadas na sessao
- Acesso atual via Guacamole a EP126 confirmado pela responsavel.
- EP126 hostname ep126-pucpr-br, IP 192.168.6.50; xrdp active/running em TCP 3390.
- Conexao RDP estabelecida: 10.96.43.36:45130 -> 192.168.6.50:3390. Estado no pfSense associado a LAN49, ESTABLISHED:ESTABLISHED.
- EP125 recebe RDP do mesmo IP institucional 10.96.43.36 na porta 3389.
- Nao foi identificada a regra que impediu acesso historico. Suporte acionado para avaliar restauracao segura da segmentacao LAN33/LAN49; nenhuma alteracao de firewall autorizada neste registro.
- Bacula EP126: bacularis-webapi, bacula-director, bacula-storage, bacula-pgbouncer e bacula-catalog Up 9 hours no momento da coleta; quatro ultimos healthy.
- Estado de Schedule/execucao automatica NAO comprovado por esse comando.
- BAC-05: decisao historica de backup manual por falta de janela operacional; mudanca exige aprovacao.
- Twingate EP126: pendente definicao de Connector/Remote Network/Resources e preflight; nao implantado nem homologado nesta sessao.
- EP125 Connector Twingate: instabilidade anterior permanece em investigacao; nao usar como evidencia de E2E funcional.

## Scripts preparados no GitHub (nao executados nesta etapa)
- scripts/zt06/CE_ZT06_EP126_PREFLIGHT.sh: preflight read-only de rede/containers/egress, sem segredos.
- scripts/ga09/CE_GA09_EP126_SCHEDULE_READONLY.sh: contagem de agendamentos no arquivo runtime Bacula, sem mostrar conteudo sensivel e sem executar Jobs.

## Proximos gates
1. Rodar scripts na EP126 e preservar os relatórios e SHA256 locais.
2. Decidir topologia de Connector Twingate e autorizacao de mudanca; nao copiar tokens em chat, logs, GitHub ou Trello.
3. Obter parecer do suporte sobre regra efetiva de Guacamole e restauracao de segmentacao.
4. Confirmar politica BAC-05 antes de qualquer Schedule, backup ou restore.
5. Reconciliar codigo/VM somente apos diff, backup e rollback revisados.

**Nota de custodia:** este documento e um espelho no GitHub das evidencias informadas pela responsavel. O diario local em /home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md NAO foi alterado remotamente.
