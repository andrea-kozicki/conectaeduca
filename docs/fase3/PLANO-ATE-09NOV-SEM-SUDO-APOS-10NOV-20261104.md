# ConectaEduca — Janela final com sudo (04–09/11) e plano de operação restrita a partir de 10/11

**Elaborado em 04/11/2026 (BRT). Responsável técnica:** Andréa Kozicki. **Natureza:** planejamento e gates, sem intervenções em EP125/EP126, pfSense, Guacamole ou Twingate.

**Fato operacional informado:** a permissão de `sudo` nas VMs EP125 e EP126 será retirada em **terça-feira, 10/11/2026**. Até o dia **09/11 inclusive**, não presumir execução fora da janela institucional ou manutenção indefinida de privilégios. Os ensaios do Pentest B foram planejados para 08–14/11 e a entrega acadêmica para 17/11; o período de privilégio acaba no meio da campanha. Congelamento documental anterior previsto para 07/11, sujeito ao plano acadêmico efetivo.

## 1. Decisão de risco: o que precisamos terminar até 09/11

**Regra:** uma tarefa que exige root para mudar ACL, systemd, fontes persistentes, certificados ou diretórios protegidos deve ser **executada em janela aprovada antes de 10/11**, **delegada expressamente ao suporte** ou **documentada como bloqueada/risco residual**. Nunca contornar a retirada de sudo por grupos privilegiados novos, shells root, serviço persistente, setuid, cron, alteração de sudoers ou credenciais emprestadas.

O `sudo` e o grupo Docker são autorizações **distintas**. A retirada de sudo não comprova perda nem manutenção do Docker. Verificar permissões permitidas e políticas de acesso sem tentar escalar ou reatribuir acesso.

| Ordem | Frente | Status comprovado em 04/11 | Ação prioritária **se autorizada** antes de 10/11 | Depende de sudo/adm? | Se não der tempo |
| --- | --- | --- | --- | --- | --- |
| P0 | EP126 OpenBao → Bacula GA09 | Registro de 03/11: OpenBao selado, health 503 e materializador Bacula root-owned; staging e backup controlados preservados, refresh bloqueado | Custodiante autorizado valida estado atual do OpenBao e faz unseal **sem compartilhar shares**; testar materialização por caminho autorizado e backup/restore isolado com SHA, sem exportar segredos | **Sim/condicional**: custódia de shares, diretório root e execução autorizada; não basta sudo | Manter proteção e backups já feitos, reportar restore não demonstrado e delegar execução ao suporte; não prometer Bacula automatizado |
| P1 | EP125 GA08 / PA-02 | Primeiro cutover falhou no PHP-FPM, rollback real PASS 3/3 healthy; HTTPS E2E pós-rollback não comprovado; canário CI na imagem-base PASS | Confirmar HTTPS binding real, executar canário descartável com imagem personalizada, correlacionar mounts/health; só corrigir e pensar em novo cutover com **novo change ID**, aprovação e rollback | Docker **condicional**; criação/ACL dos socket dirs, mounts protegidos e suporte podem exigir root | **Não forçar cutover**; manter baseline saudável, PA-02 aberto com evidência de rollback |
| P1 | EP126 Ferret GA06 / PA-07 | Imagem candidata v5 e preflight anteriores; **GA06.10B backup protegido PASS**; runtime v5 não promovido | Se gate completo: aprovar TAR/janela, verificar backup/restore, aplicar somente drop-in dedicado do health monitor e cutover controlado, validar UI/CLI/Wazuh | **Sim/condicional**: `/etc/systemd/system`, caminhos protegidos; Docker separado | Não repetir backup sem razão; manter Ferret 2.4.3 ativo e registrar v5 pendente |
| P1 | EP125 audit.log / Wazuh PA-06 | Audit.log persistente e ingestão Wazuh já observadas; **rotação/retenção não homologadas** | Se política/operador aprovados, validar ownership, executor logrotate, troca de inode, leitura pós-rotação no Wazuh em teste único | **Sim**, potencialmente; tentativa anterior foi bloqueada por controle institucional; não improvisar `sudo -s`, `setpriv` ou `sudo bash` | Preservar ingestão atual e não alterar log; declarar política pendente |
| P2 | EP126 Wazuh / DLP e backups | CI das PRs #206/#207 PASS, mas CI não substitui runtime; arquivos de DLP locais EP126 modificados intencionalmente | Reconciliar só diferença concreta e validar regras/monitor; preservar backups, não fazer reset do checkout; obter evidência permitida de health/evento | **Condicional**: Manager e diretórios Wazuh/systemd protegidos | Manter regras comprovadas, documentar o restante como pendência |
| P2 | pfSense / Guacamole / PA-01 | Regras personalizadas LAN33/LAN49 desativadas pelo suporte; Guacamole voltou a funcionar; falha Xvnc histórica local não demonstra culpabilidade do pfSense | Aguardar suporte com IP real do guacd, porta/protocolo, tracker e estado; backup pfSense e mudança de **uma regra por ciclo**, com canal de rollback independente | **Suporte**, não `sudo` EP125/126 | Não reativar regras em lote; PA-01 segmentação de Fase 3 fica pendente |
| P2 | Twingate / Zero Trust | Fluxos portal/Wazuh e MFA possuem evidências positivas em recortes; não fecha bypass de bridge | Consolidar evidências ZT; reteste positivo/negativo por identidade com contas já existentes | Geralmente sem sudo para teste de cliente; console web com seus próprios papéis | Documentar limite dos testes, não reinstalar Connector saudável |

**Separação obrigatória:** snapshot EP125 informado como `ubuntu.33`, EP126 como `ubuntu.49`; suporte confirmou cobertura e capacidade de restaurar em 03/11. Referências não são UUID garantidos. Snapshot de VM não substitui backup pfSense nem materializa automaticamente backups consistentes externos. Evidência de autorização de um host não libera outro.

## 2. Calendário de execução enxuto

| Dia | Foco principal | Condição para avançar | Resultado documental |
| --- | --- | --- | --- |
| **04/11 (quarta)** | GitHub/Trello: priorização das tarefas dependentes de privilégio; CI e roteiros sem acessar VMs. Aguardar resposta do suporte Guacamole | Nenhuma operação real | Este mapa e card P0 no Trello |
| **05–06/11 (qui/sex)** | Quando houver janela nas VMs: recuperar HTTPS real da EP125 e canário do PHP; EP126 confirmar gate OpenBao/Bacula sob custódia e disponibilidade do backup Ferret | Testes limitados, não reiterar inventário geral | Provas sanitizadas de saúde, entrada/saída e decisão |
| **07–08/11 (sáb/dom)** | Freeze de evidências e preparação do Pentest B em usuário `teste`; alterações privilegiadas somente se cabíveis e expressamente autorizadas | Não executar Pentest B em meio a cutover | Checklist de baseline e mapa de bloqueios por PA |
| **09/11 (segunda)** | **Última conferência de acesso privilegiado previsto**: fechar ou delegar tarefas com root/systemd/backup/ACL, preservar rollback e obter aceite do estado operacional | Não iniciar mudança irreversível de última hora | Termo de congelamento e riscos residuais |
| **10/11 (terça) em diante** | Pentest B estritamente como identidade de teste sem sudo, leitura e teste funcional; suporte assume atos administrativos futuros se autorizados | Não tentar contornar redução de privilégios | Comparação Pentest A × B, evidências, relatório final |

Os dias são ordem operacional proposta, **não compromisso de disponibilidade institucional**. Se janela ou suporte não estiverem disponíveis, preservar serviço estável e declarar bloqueio em vez de acelerar o risco.

## 3. Matriz de autorização pós-10/11 (sem presunções)

| Ação | Sujeita a sudo/root antes do corte | Após 10/11, somente se permissão comum conservar |
| --- | --- | --- |
| `whoami`, `id`, `date`, testes Python permitidos, curl, screenshots | Não | **SIM** (conforme regras de usuário e escopo) |
| Leitura de `systemctl is-active`, `ss -lnt`, health HTTP público e comandos de inspeção sem segredos | Geralmente não | **SIM** se ACLs permitirem |
| Contêiner Docker: `docker inspect`, `docker exec`, `docker run` | Não necessariamente, mas acesso ao socket Docker é **equivalente a privilégio elevado** em Docker rootful | **NÃO PRESUMIR**; solicitar decisão institucional explícita |
| `systemctl daemon-reload`, instalação de drop-in systemd, troca de UID/ACL/mount | Tipicamente sim | **NÃO**; suporte autorizado |
| `logrotate` sobre arquivos root/UID82 protegidos, mudança em `/var/log` | Tipicamente sim | **NÃO** sem privilégio delegado |
| Backup/restore de diretórios root e materializador Bacula root-owned | Sim/condicional | **NÃO**; suporte/custodiante |
| Unseal do OpenBao | Não substituível por sudo: exige custodiante e shares autorizadas | Somente custodiante autorizado, independentemente do sudo |
| Regras pfSense e administração guacd | Externas às VMs | Só suporte/admin institucional, independentemente do sudo EP |
| Pentest B `teste` sem sudo/Docker | **Intencionalmente sem privilégios** | **SIM**, sujeito a autorização de testes |

**Não criar atalhos permanentes para root antes de 10/11.** Não deixar execução privilegiada agendada para depois, não inserir conta `teste` no grupo Docker ou criar mecanismos de elevação para viabilizar Pentest B.

## 4. Gate documental antes de 10/11 — registrar somente status, não segredos

- **GA08/EP125:** HTTPS real no binding publicado; causa de `unhealthy_php` caracterizada ou classificada como pendência; rollback já comprovado. Se outro corte, change ID novo e snapshot/autorizações atualizados.
- **GA06/EP126:** backups GA06.10B preservados; autorização TAR/monitor e restauração; imagem baseline mantida.
- **GA09/EP126:** estado atual OpenBao confirmado por custodiante; staging/materializador/Jobs Bacula não presumidos concluídos. Restore real com SHA somente se viável e autorizado.
- **PA06:** ingestão já evidenciada; retenção e rotação apenas se política institucional permitir.
- **PA01:** pfSense sob suporte, Guacamole sob admin Guacamole; responsável só opera EP125 e EP126 e utiliza Guacamole como cliente.
- **Pentest B:** assegurar usuário `teste` sem sudo/Docker e scripts da PR #219 em cópias autorizadas; registrar antes/depois por origem/identidade, sem inventar PASS.
- **Backup de evidências:** hashes/prints sanitizados com data/identidade, arquivos privados protegidos, jamais `.env`, login/cookie, shares/tokens, config.xml, manifesto com referências sensíveis em GitHub/Trello.

## 5. Decisão de escalonamento (não confundir urgência com permissão)

**Se até 09/11 ficar pendente um serviço que só funciona com root:** documentar qual comando/arquivo exige privilégio, impacto real, pré-condições e rollback, e solicitar **uma janela específica e ação do operador institucional**, sem pedir prorrogação genérica nem alteração de sudoers. Controles que não forem retestados serão reportados como PENDENTE ou INCONCLUSIVO no relatório acadêmico, com risco residual e data.

**Não abrir nova frente, não repetir GA06.10B, GA07.8R, inventário Docker 9/10 ou snapshot já confirmado.** Foco em concluir o essencial com segurança e registrar o que permanece dependente de autorização.

## Links

- [PR #217 — GA08/PA02 e canário FPM](https://github.com/andrea-kozicki/conectaeduca/pull/217)
- [PR #207 — GA06/Ferret v5](https://github.com/andrea-kozicki/conectaeduca/pull/207)
- [PR #203 — AUD07/PA06](https://github.com/andrea-kozicki/conectaeduca/pull/203)
- [PR #219 — Kit Pentest B](https://github.com/andrea-kozicki/conectaeduca/pull/219)
- [PF01 — testes pfSense/Guacamole](PF01-PLANO-TESTES-PFSENSE-GUACAMOLE-EP126-20261104.md)
- [GA08 — incidente, rollback e pendência E2E](GA08-PA02-INCIDENTE-CUTOVER-ROLLBACK-20261103.md)
- [Plano de cutover e snapshots informados pelo suporte](PLANO-CUTOVER-03NOV2026-SNAPSHOTS-E-ROLLBACK.md)

**Status:** documento planejado em 04/11; nenhuma mudança executada em VM, firewall, Guacamole, Twingate ou backups por esta atualização.
