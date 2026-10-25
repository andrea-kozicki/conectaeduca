# ConectaEduca EC8 — handoff do Grupo A ao suporte e ao professor
**Data do levantamento:** 25/10/2026 (BRT)  
**Janela solicitada:** 28/10/2026, às 15h BRT (**a confirmar com o suporte**)  
**Estado:** preparação e diagnóstico autônomo concluídos no escopo abaixo; solicitações operacionais ainda pendentes.  
**Escopo de alteração:** nenhuma alteração é autorizada por este documento; cada ação exige aprovação e rollback.

## 1. Objetivo
Preparar as VMs **EP125 / DMZ** e **EP126 / interna** para a introdução **autorizada** do Twingate e para o segundo pentest comparativo, preservando o baseline do primeiro pentest. A implementação do Connector e a administração do tenant Twingate são atividades da responsável acadêmica, com limites e permissões definidos pela instituição. O suporte deve tratar os ajustes de infraestrutura/privilegios institucionais que forem aprovados.

## 2. O que foi demonstrado até 25/10 (sem executar pentest B)
| Ativo | Comprovado | Evidência/limitação |
|---|---|---|
| EP125 | Ubuntu 24.04.5, Docker/Wazuh Agent/Bacula FD ativos, NTP sincronizado; PHP-FPM/WAF/Nginx running/healthy. | `EP125-GRUPOA-READONLY-20261025T102445023237.txt`; diário EP125 0600, custódia confirmada. |
| EP125 rede | WAF mapeado em `192.168.6.34:80/443`; PHP/Nginx não têm host port bindings; 8088 não escuta. | Não prova isolamento da bridge Docker nem ausência de bypass interno; issue #204. |
| EP125 aplicação | HTTPS com TLS válido no próprio host, login 200, chave pública híbrida v2 disponível; PHP ativo 8.5.12 e auditoria PHP persistente previamente demonstrados. | Preflight PR #205; não equivale a implantação da criptografia híbrida do login nem a testes pós-Twingate. |
| EP126 | Ubuntu 24.04.5, NTP sincronizado; Manager/Dashboard/Indexer Wazuh, Bacula Director/Storage/PgBouncer/Catalog, MariaDB, OpenBao e phpMyAdmin running/healthy. | `EP126-GRUPOA-READONLY-20261025T103015487546.txt`; o estado de saúde pontual não prova Jobs recentes ou restore. |
| EP126 auditoria | Ingestão sintética PHP→Wazuh agent001→manager, regra 110250, demonstrada (EP126-F2-0062). | Rotação/retenção, privacidade e durabilidade sob reinício ainda não validadas; PR #203 / issue #195. |
| EP126 Bacula | Bacularis voltou a consultar histórico de Jobs de 05–06/10; Director healthy; a conta `teste` possui menor privilégio deliberado. | Aba Jobs vazia **não** prova que não haja Jobs globais; Jobs correntes/schedules/restore recente não comprovados; issue #196. |
| EP126→EP125 | TCP 443 alcançável. | HTTPS com certificado **não confiável na EP126**: `VERIFY_CODE=20`, `unable to get local issuer certificate`. Diagnóstico e diário EP126 preservados (0600); falta validar cadeia e depois SAN/nome. |
| Código e CI | PR #205 (login híbrido) e #206 (DLP Ferret/Wazuh) preparados e CI aprovada. | Ambos DRAFT, **sem merge/deploy**; testes operacionais posteriores. PRs #200 e #203 também DRAFT. |

## 3. Solicitações ao suporte, por prioridade
**P0 — pré-requisito TLS (EP126):** identificar a CA raiz/intermediária emissora do certificado de `192.168.6.34:443`; conferir se o WAF serve cadeia completa; se CA interna legítima, disponibilizar e instalar *somente com aprovação* no trust store adequado na EP126/cliente autorizado. Validar cadeia + SAN para o endereço efetivamente usado, sem `-k`, `verify=False` ou enfraquecer HTTPS. A falha atual é de cadeia (verify 20); incompatibilidade de nome ainda **não foi comprovada**.

**P0 — gates para Connector Twingate (EP126):** confirmar formalmente host e executor autorizados, permissões Docker, tráfego de saída estritamente necessário ao tenant/relay Twingate, imagem/digest aprovado, CA e relógio, instalação do Client em equipamento autorizado, processo de introdução de tokens sem envio ao chat/Git/logs, revogação e rollback. Não iniciar Connector antes dos gates G0–G6.

**P0 — decisão de isolamento por rede:** aprovar política de acesso direto ao `192.168.6.34:443`, matrizes pfSense e segmentação de acesso ao Nginx upstream/bridge Docker. Se HTTPS público direto permanecer, só é possível demonstrar **acesso condicionado pelo Twingate em paralelo**, não isolamento exclusivo da aplicação. Twingate não aplica ACL por URL `/admin` na mesma origem IP:443 e não substitui PHP RBAC/MFA.

**P1 — Wazuh/Auditoria:** deliberar política de retenção/rotação, direitos de leitura e privacidade dos eventos de auditoria PHP, validar continuidade/recovery; para DLP (#206), conferir regras efetivamente carregadas no Manager, depois testar casos LOW/MEDIUM/HIGH sintéticos em `wazuh-logtest` e change control separado.

**P1 — Bacula:** operador com perfil apropriado (não alterar privilégios da conta `teste`) deve consultar read-only definições de Jobs, schedules, última execução e falhas desde 06/10, Catalog/FileSets e registros de restore, diferenciando os horários históricos da rotina atual. Restore sintético somente em janela autorizada e com dados fictícios, evidência de integridade e rollback.

**P1 — correção de login (#205):** homologar em ambiente isolado fluxos existentes/MFA novo e estabelecido, CSRF, WAF, HTTP 401/419, TLS e rollback antes de aprovar merge/deploy; a mudança não requer migração dos hashes ou recadastro.

## 4. Procedimento de 28/10 — sequência proposta
1. Confirmar autorização escrita, operador, hora exata, baseline, cópias de configuração/snapshot aprovadas e rollback.
2. Corrigir/validar cadeia TLS e SAN da EP125 a partir da EP126/dispositivo Client, **antes** de validar Twingate.
3. Revisar roteamento/pfSense/egress e definir Resource IP/porta mínima, grupos e controles MFA; proibir `Everyone` e CIDRs amplos.
4. A responsável acadêmica configura tenant/Client/identidades e instala Connector **apenas no host aprovado**; suporte garante pré-requisitos e age nos ajustes institucionais de sua responsabilidade.
5. Registrar Connector Online no Console, resultado de acesso com conta positiva e negativa, acesso direto e portas adicionais; **não testar BOLA/IDOR até o Pentest B**.
6. Registrar mudança, evidências sanitizadas e SHA-256; se gate falhar, **não prosseguir e acionar rollback aprovado**.

## 5. Itens que não autorizamos agora
Não reiniciar/recriar contêineres, modificar pfSense/WAF/Compose/Wazuh, rodar Jobs, emitir eventos adicionais, elevar a conta `teste`, expor portas internas ou tokens, adicionar bypass TLS, executar pentest B antecipado, nem fazer merge dos PRs DRAFT em nome desta minuta.

## 6. Acompanhamento
- PR arquitetura Zero Trust: #200
- PR auditoria PHP/Wazuh: #203; issue #195
- PR login híbrido: #205
- PR classificação DLP: #206; issue #194
- Issue Bacula: #196
- Issue upstream/WAF: #204
- Issue patch PHP: #201 (PHP 8.5.12 observada na EP125; manter trilha de rollout dos demais runtimes)

**Ponto de decisão:** sem aprovação para alterações no firewall/rota pública e sem TLS confiável, o relatório do segundo pentest não poderá afirmar isolamento exclusivo por Twingate. O grupo não deve confundir saúde de serviço com prova de disponibilidade operacional ou de Zero Trust.
