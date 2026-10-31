# EP126 — fila de mudanças preparada, não aplicada

| Ordem | Task CLI | Rastreabilidade | Gate de implantação |
|---|---|---|---|
| P0 | `twingate` | ZT-07/08, PR #214 documental | Resource Wazuh CRIADO; faltam Twingate Client, TLS confiável, MFA efetivo e allow/deny |
| P1 | `wazuh` | PR #206, PA-06/07 | Conferir regras ativas, PCRE2 e logtest controlado; sem reaplicar audit E2E |
| P1 | `ferret` | PR #207, GA-06, PA-07 | Baseline 2.4.3; candidata v5 apenas após plano de mudança e regressão fail-closed |
| P1 | `firewall` | ZT-05/09 | Validar caminhos de SSH, XRDP, Bacula e serviços sem quebrar acesso institucional |
| P1 | `tls` | CA WAF EP125 e Wazuh | Resolver cadeia CA e nome DNS sem copiar chaves privadas |
| P1 | `bacula` | GA-09, issue #196 | Agendamento autorizado, backup atual e restore sintético com SHA-256 |
| P1 | `openbao` | ZT-09 | AppRole e auditoria, política de menor privilégio e plano de re-unseal |

Uso quando o kit estiver disponível na máquina:

```bash
bash ops/fase3/ep126/ce-ep126.sh list
bash ops/fase3/ep126/ce-ep126.sh check twingate
bash ops/fase3/ep126/ce-ep126.sh prepare ferret
bash ops/fase3/ep126/ce-ep126.sh reconcile
```

Não executar restauração Bacula, mudar regras do Manager, abrir portas, trocar imagens Ferret ou reconfigurar OpenBao sem controle de mudança. A fila é um plano operativo, não um atestado de conclusão.
