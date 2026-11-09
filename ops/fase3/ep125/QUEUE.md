# EP125 — fila de mudanças preparada, não aplicada

As prioridades abaixo são para o Pentest B e o congelamento até 07/11/2026.

| Ordem | Task CLI | Rastreabilidade | Gate de implantação |
|---|---|---|---|
| P0 | `twingate` | PR #213, ZT-06/07 | Conector DMZ efetivo + egress + Resource DMZ com testes allow/deny |
| P0 | `waf` | PA-02, GA-08 | Negar caminho direto ao nginx da bridge, preservar WAF→nginx→PHP |
| P1 | `login` | PR #205, PA-05 | Homologar login/MFA/RBAC + rejeições e rollback; não aplicar PR automaticamente |
| P1 | `audit` | PR #203, PA-06/AUD07 | Persistência e E2E Wazuh JÁ comprovados; fechar retenção, PII e recreate |
| P1 | `tls` | ZT-09/ZeroSSL | Domínio, autoridade de confiança, SAN e HTTPS nos endpoints aprovados |

Uso quando o kit estiver disponível na máquina:

```bash
bash ops/fase3/ep125/ce-ep125.sh list
bash ops/fase3/ep125/ce-ep125.sh check twingate
bash ops/fase3/ep125/ce-ep125.sh prepare waf
bash ops/fase3/ep125/ce-ep125.sh reconcile
```

Nenhuma dessas opções faz deploy, modifica WAF, firewall, Docker ou Git. A correção real de cada item exige um patch/PR específico, backup aprovado e procedimento de retorno validado.
