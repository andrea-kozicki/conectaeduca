# PF-01 — Investigacao das regras desabilitadas nas interfaces 33 e 49

Data: 31/10/2026. Estado: PREPARADO, NAO EXECUTADO.

## Problema
O suporte informou que o acesso institucional a EP126 voltou apos desabilitar regras antigas do pfSense nas interfaces 33 e 49. Nao ha exportacao das regras, IDs de tracker, horarios precisos da mudanca, nem evidencias de log para atribuir causa. O conector Twingate DMZ apresenta intermitencia; nao presumir causa comum.

## Coleta segura com suporte (sem alterar regras)
1. Registrar horario BRT/UTC da perda e restauracao do acesso EP126, origem, destino, protocolo e porta dos testes de acesso.
2. Em Firewall > Rules, fotografar as regras DESABILITADAS nas interfaces 33 e 49, com ordem, action, direction, source/destination, port, gateway, schedule, log e description. Capturar tambem aliases referenciados, sem divulgar dados sensiveis.
3. Em Status > System Logs > Firewall, filtrar pelos IPs envolvidos e pela janela do incidente. Se os logs anteriores a mudanca nao estiverem retidos, registrar a ausencia; nao inventar evidencia.
4. Verificar regras Floating, quick, regras automaticas de VPN/NAT, e estados de firewall existentes, sem limpar estados.
5. Identificar os fluxos institucionais necessarios a EP126 (DNS, dominio/AD, Kerberos/LDAP quando aplicavel, horario/NTP, Guacamole/RDP, administracao) com origem, destino e porta validados pelo suporte. Nao presumir que todos sao usados.
6. Comparar o caminho da EP126 ao da DMZ e ao egress do conector. A conectividade HTTPS para um endpoint nao valida todos os servicos do Twingate.
7. Documentar se o bloqueio foi comprovado por log, apenas correlacionado no tempo, ou permanece hipotese.

## Criterios para proposta de correcao
- Preservar segmentacao e minimo privilegio; nunca deixar regras antigas permanentemente desabilitadas sem avaliacao de risco.
- Elaborar matriz de fluxos necessarios e mudanca controlada, com backup de configuracao, janela autorizada, rollback, teste positivo e negativo e aceite do suporte.
- Nao reabilitar em massa, nao limpar states, nao reiniciar pfSense, nao exportar config.xml ou credenciais para GitHub.
- Sem acesso autorizado ao pfSense, este roteiro e apenas preparacao. Coleta e alteracoes ficam com suporte/administrador.

## Matriz a preencher com evidencias
| Origem | Destino | Protocolo/porta | Interface/regra/tracker | Acao/log | Evidencia | Necessidade | Correcao proposta |
|---|---|---|---|---|---|---|---|
| EP126 | Servicos institucionais (a identificar) | A validar | A identificar | A identificar | Pendente | A validar | Pendente |
| Cliente institucional | EP126 | A validar | A identificar | A identificar | Pendente | A validar | Pendente |
| Conector DMZ | Servicos Twingate | A validar | A identificar | A identificar | Pendente | A validar | Pendente |

## Perguntas objetivas ao suporte
- Quais regras exatas (interfaces, trackers e descricoes) foram desabilitadas, e em que horario?
- Qual fluxo falhava antes e passou a funcionar depois? Ha log de bloqueio com origem/destino/porta?
- Havia regra Floating/quick, alias ou NAT interferindo?
- As regras foram desabilitadas provisoriamente? Qual o plano de restaurar a segmentacao com excecoes minimas?
- Ha inspecao TLS/proxy ou politica de saida aplicavel ao conector da DMZ? Verificar sem concluir causalidade.
