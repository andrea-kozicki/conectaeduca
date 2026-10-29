# GA-08 / Fase 3 — Índice de evidências e gates (29/10/2026)

## Evidências existentes
| ID | Fonte | Resultado demonstrado | Limitação |
|---|---|---|---|
| E01 | GA08_COMPOSE_TIPOS_20261028T224843.txt | 10 arquivos Compose base PASS | estático |
| E02 | GA08_COMPOSE_CANDIDATO_20261028T224951.txt | candidato Compose PASS | não prova rede runtime |
| E03 | GA08_NGINX_FPM_INTEGRADO_V4_20261028T215119.txt | socket efêmero Nginx↔FPM pong | não implantado |
| E04 | GA08_EP126_CONECTIVIDADE_20261028T221525.txt | EP126 TCP 3306 alcançável | SQL autenticado pendente |
| E05 | commit 9a7f47c | gate de implantação documentado como fechado | não realiza deploy |
| E06 | commit 7e3646b | revisão offline e oito gates de homologação | plano, não execução |
| E07 | commit 1d610d6 | plano integrado ZT/Twingate/Pentest B | plano, não execução |
| E08 | commit 6af69b8 | workflow GA08 passa a observar arquivos do socket candidato | novo teste de contrato ainda pendente |
| E09 | GitHub Actions no commit 1d610d6 | 8 workflows completed/success | não prova runtime |

## Aprovação PR #200
- [ ] Revisão de professor/suporte: separação de redes, endpoint admin privado, TLS/CA, egress/NTP, rollback.
- [ ] Teste estático específico do socket candidato criado, executado e vinculado ao workflow.
- [ ] Evidência de teste positivo WAF→Nginx→PHP e negativo PHP→Nginx.
- [ ] EP126 SQL autenticado, TLS, WAF e regressão funcional.
- [ ] Rollback ensaiado com snapshot identificado.
- [ ] PR continua DRAFT até aprovação; issue #204 permanece aberta.

## Twingate
Grupos TG-OPERACAO, TG-SEGURANCA, TG-ADMIN, TG-BACKUP: propostos, não verificados no tenant. Sem grupo = sem Resource privado. RBAC PHP não implica acesso de rede. WAF público em :443 não separa /admin. Endpoint privado distinto ainda requer decisão de desenho e teste. Recursos OpenBao, MariaDB e Catalog não devem ser publicados como Resources.

## Sete PAs — pendência de rastreabilidade
PA-02 é o único deste pacote com correspondência de evidência diretamente conferida nesta rodada (issue #204). Para PA-01,03,04,05,06,07, preencher do relatório original: ID do cenário, ativo, evidência, impacto, controle ZT, teste antes/depois e limitação. Não inventar achados ausentes.

## Rollback — roteiro não executado
1. Autorização formal, operador e janela; snapshots e IDs verificados.
2. Guardar configuração Compose efetiva, configs, imagens/digests e hashes sem segredos.
3. Preparar retorno ao baseline e dependências de DB/rede, sem supor que o preflight atual execute reversão.
4. Definir gatilhos de aborto: indisponibilidade HTTPS, FPM, SQL, isolamento falho ou perda de telemetria.
5. Ensaio controlado com evidências de restauração e validação funcional.
6. Registrar diário, timestamps e SHA256; não divulgar tokens ou .env.

**Status:** trabalho documental concluído, implantação e rollback NÃO executados.
