# Checklist Twingate — preencher somente no Pentest B

**Estado em 09/10/2026:** não executado. **Não iniciar antes de autorização escrita.**

**Change Control:** ______  **Executor:** ______ **Host:** ______ **Data UTC:** ______ **Baseline A / hash:** ______

## Gates (qualquer NÃO = PARAR)

- [ ] G0 relatório Pentest A encerrado, hashes preservados, Twingate OFF.
- [ ] G1 autorização institucional para o host/operador, egress, tokens e rollback.
- [ ] G2 host Connector aprovado, rota validada para EP125:443.
- [ ] G3 tenant Twingate, Admin Console, Client, conta permitida e negada disponíveis.
- [ ] G4 HTTPS confiável no cliente, CA e SAN do WAF verificados, sem `--insecure`.
- [ ] G5 Resource **IP EP125 / TCP 443 somente**, grupo mínimo (não Everyone).
- [ ] G6 rollback, privacidade, relógios e revogação de tokens aprovados.

**Rota de implantação:** [ ] EP126 [ ] host alternativo com rota EP125 [ ] bloqueada.
**Acesso direto HTTPS poderá ser restringido?** [ ] sim [ ] não [ ] não respondido.

## Implantação autorizada

- [ ] Commit/handoff e estado pré-mudança identificados.
- [ ] Digest, plataforma, compatibilidade e políticas revisados.
- [ ] Tokens introduzidos interativamente e protegidos; `/dev/shm` 0600.
- [ ] Readiness realizado, sem expor tokens.
- [ ] Connector iniciado por operador com Docker.
- [ ] Checkpoint operacional realizado, Console Online confirmado **separadamente**.
- [ ] Resource/Group/Policy configurados e Client autorizado.
- [ ] Sem portas extras, serviços internos, chave ou segredo no Git.

## Matriz de resultados

| Caso | Observado (sem segredo) | Evidência/SHA-256 | Conclusão |
|---|---|---|---|
| ZT-01 Client autorizado | | | |
| ZT-02 Client não autorizado | | | |
| ZT-03 caminho HTTPS direto | | | |
| ZT-04/05 RBAC app | | | |
| ZT-06 WAF | | | |
| ZT-07 serviços excluídos | | | |
| ZT-08 TLS/MFA/cookies/CSRF | | | |
| ZT-09 telemetria | | | |
| ZT-10 revogação | | | |

## Encerramento

- [ ] Resource e grupo revertidos se previsto; Connector parado/retirado pelo operador.
- [ ] `restart: unless-stopped` e estado após reinício considerados.
- [ ] Tokens revogados/rotacionados; nenhuma credencial em log.
- [ ] Fase 1 permanece intacta e evidências sanitizadas com hashes.
- [ ] Classificação: ACESSO-CONTROLADO / ISOLAMENTO-COMPROVADO-NO-ESCOPO / ISOLAMENTO-NAO-DEMONSTRADO / BLOQUEADO.

Ver [runbook](../seguranca/TWINGATE-RUNBOOK-POS-PENTEST-A.md).
