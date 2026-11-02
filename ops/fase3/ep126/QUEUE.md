# EP126 — fila operacional reconciliada (02/11/2026; nenhuma mudança aplicada pela atualização documental)

| Ordem | Task CLI | Rastreabilidade | Gate de implantação |
|---|---|---|---|
| P0 | `twingate` | ZT-07/08, PR #214 documental | **CONCLUÍDO NO ESCOPO:** Connector EP126 saudável, Client Linux com TLS/CA, login Wazuh `teste`, RBAC `teste`/`admin`; em 02/11 Android/identidade B: APP autorizado funcional, Wazuh invisível/inacessível; Network Events registraram Android→APP e Linux→Wazuh por Relay/Connector; Audit Logs export Access contém 4 eventos, inclusive grant SOC/MFA e grant grupo limitado. **Não repetir os testes.** Pendem apenas reconciliação do Connector com Git/runtime e auditoria de mudanças adicionais conforme necessidade; deny é PASS qualificado, não prova firewall lateral. |
| P0 | `wazuh` | PR #206, PA-06/07 | **Próxima mudança operacional sob responsabilidade da implementadora EP126:** versão corrigida das regras DLP (PCRE2 insensível a maiúsculas LOW/MEDIUM/HIGH e guarda do resumo) está na PR #206, CI 4/4 SUCCESS; drift 01/11 já comprovado, **não refazer diagnóstico sem causa**. Preparar e preservar backup do arquivo ativo e seu SHA; definir retorno; aplicar somente delta aprovado na VM, validar sintaxe e `wazuh-logtest` DEPOIS da alteração, recarregar Manager controladamente com janela e validar E2E agente 002/alertas sem exposição de segredos. Não reiniciar Indexer/Dashboard sem necessidade. Não requer que suporte faça a configuração Docker, mas qualquer fonte protegida fora das permissões precisa ser tratada por canal autorizado. |
| P1 | `ferret` | PR #207, GA-06, PA-07 | Baseline ativo EP126 2.4.3; candidata v5 na PR #207 com correções P2 validador/overlay, Codex no commit 1c7b8e1 **sem novos problemas relevantes**, CI 6/6 SUCCESS. Próximo gate: preservar imagem e configuração atuais, TAR/SHAs + `preflight` de override efetivo, rollout manual/reversível pela implementadora, validação UI fail-closed e E2E DLP/alertas. Não implantar apenas por CI; não exigir suporte para operar Ferret se permissões suficientes. |
| P1 | `firewall` | ZT-05/09 | A implementadora pode revisar matrizes/fluxos; **suporte só atua em regras pfSense/hipervisor fora de sua permissão**, sem quebrar Guacamole/RDP/FortiClient. Não declarar que Twingate corrige movimento lateral host↔Docker. |
| P1 | `tls` | CA WAF EP125 e Wazuh | Resolver cadeia CA e nome DNS sem copiar chaves privadas |
| P1 | `bacula` | GA-09, issue #196 | **GA-09.1–09.7 de 01/11 JÁ FEITAS:** quatro Jobs e seus últimos JobIds identificados; quatro FileSets apontam a `/var/lib/conectaeduca/bacula-staging/{mariadb,openbao,catalog,recovery-state}`. Staging pertence a `bacula:bacula` modo `0700` e usuário atual recebeu `SEM_PERMISSAO`; `sudo -n -u bacula` não autorizado. **NÃO repetir 09.4–09.7 ou contornar ACL**. Em 02/11 GA-09.3/3B psql RC2 inconclusivo; não refazer. BAC-05 = backups MANUAIS com risco aceito, não criar Schedule. Próximo passo: **a implementadora é a responsável por executar backup/restore operacional** quando o perfil Bacula/Bacularis permitir. Staging `0700` não autoriza leitura direta por sua conta; preferir Jobs existentes e interface Bacula autenticada, sem contornar ACL nem criar schedules (BAC-05 manual). Se algum passo exigir identidade Bacula ou dados protegidos indisponíveis, providenciar delegação/papel apropriado; só então atualizar backup manual e prova de recuperação sintética antes do freeze. |
| P1 | `openbao` | ZT-09 | AppRole e auditoria, política de menor privilégio e plano de re-unseal |

Uso quando o kit estiver disponível na máquina:

```bash
bash ops/fase3/ep126/ce-ep126.sh list
bash ops/fase3/ep126/ce-ep126.sh check twingate
bash ops/fase3/ep126/ce-ep126.sh prepare ferret
bash ops/fase3/ep126/ce-ep126.sh reconcile
```

Não executar restauração Bacula, mudar regras do Manager, abrir portas, trocar imagens Ferret ou reconfigurar OpenBao sem controle de mudança. A fila é um plano operativo, não um atestado de conclusão.


## Reconciliação de duplicidades — 02/11/2026

- A GA-09.4 (01/11) já localizou os quatro diretórios FileSet. A GA-09.5 encontrou bloqueio de acesso; a GA-09.6 confirmou `bacula:bacula`, modo `0700`; a GA-09.7 confirmou que a usuária não pode assumir a identidade Bacula. **Classificar como limite de autorização, não falha do sistema**.
- A GA-09.3 e 3B (02/11) foram duas tentativas redundantes de SQL com `psql` RC2: sem diagnósticos conclusivos de conexão/autenticação, sem alteração de banco ou Job. **Não repetir** e não confundir com dano ao Catalog.
- BAC-05 define `BAC05_SCHEDULE_ACTIVE=NO`, `BAC05_EXECUTION_MODE=MANUAL`, `BAC05_RISK_ACCEPTED=YES` apenas para o laboratório. A recomendação anterior de agendar automaticamente foi superada.
- Últimos pontos Bacula identificados em 01/11: MariaDB JobId 22 (06/10); OpenBao 19, Catalog 20 e RecoveryState 21 (05/10). Isso é **histórico documentado**, não prova backup válido atual nem restauração contemporânea.
- **Atualização 02/11:** a responsável EP126 é a própria operadora de Wazuh/Ferret/Bacula dentro das permissões que possui. O teste A/B de Twingate foi feito com identidade B no Android e A no Linux, e a auditoria Network+Access foi coletada; não há necessidade de nova identidade. O próximo marco operacional é **a aplicação controlada das regras Wazuh DLP (#206)**, seguida da candidata Ferret v5 (#207), com backups locais e rollback explícito; suporte apenas para snapshot, firewall e acesso a recursos efetivamente indisponíveis. A verificação SQL GA09.3/3B não deve ser repetida.
