# EP126 — fila de mudanças preparada, não aplicada

| Ordem | Task CLI | Rastreabilidade | Gate de implantação |
|---|---|---|---|
| P0 | `twingate` | ZT-07/08, PR #214 documental | Connector EP126 healthy; Client openSUSE autenticado via `twingate auth`; TLS/CA por curl PASS; GUI de login Wazuh acessível. **Falta** login Wazuh e teste NEGATIVO com segunda identidade Twingate independente, além da telemetria. Testar do CLIENTE, não no host EP126 como substituto. |
| P1 | `wazuh` | PR #206, PA-06/07 | Em 01/11 `wazuh-logtest` mostrou desvio MEDIUM/HIGH e regra silenciosa 110101; hash repositório/runtime conferido. **Não repetir logtest sem mudança causal**. Preparar backup/rollback e promoção da PR #206 sob autorização; preservar E2E audit 110250 já comprovado. |
| P1 | `ferret` | PR #207, GA-06, PA-07 | Baseline 2.4.3; candidata v5 apenas após plano de mudança e regressão fail-closed |
| P1 | `firewall` | ZT-05/09 | Validar caminhos de SSH, XRDP, Bacula e serviços sem quebrar acesso institucional |
| P1 | `tls` | CA WAF EP125 e Wazuh | Resolver cadeia CA e nome DNS sem copiar chaves privadas |
| P1 | `bacula` | GA-09, issue #196 | **GA-09.1–09.7 de 01/11 JÁ FEITAS:** quatro Jobs e seus últimos JobIds identificados; quatro FileSets apontam a `/var/lib/conectaeduca/bacula-staging/{mariadb,openbao,catalog,recovery-state}`. Staging pertence a `bacula:bacula` modo `0700` e usuário atual recebeu `SEM_PERMISSAO`; `sudo -n -u bacula` não autorizado. **NÃO repetir 09.4–09.7 ou contornar ACL**. Em 02/11 GA-09.3/3B psql RC2 inconclusivo; não refazer. BAC-05 = backups MANUAIS com risco aceito, não criar Schedule. Próximo passo depende de operador autorizado: atestar freshness de staging, eventualmente backup manual antes do freeze e confirmação de restauração conforme BAC-04. |
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
- Enquanto a usuária estiver na EP126 sem operador e sem identidades secundárias, dar preferência à preparação *offline* de rollback Ferret (#207) e Wazuh DLP (#206). A homologação de negação Twingate requer a identidade externa independente e execução pelo **cliente**; não alegar deny a partir de curl local no host.
