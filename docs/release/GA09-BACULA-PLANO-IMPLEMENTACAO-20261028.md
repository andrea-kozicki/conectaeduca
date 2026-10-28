# GA-09 — Bacula EP126: proposta de implementação e aceite (28/10/2026)

**Status:** proposta técnica versionada, **não aplicada**. Sem alterações nas VMs, no Docker, no Director ou no catálogo. Sem execução de backup/restore. A GA-09 permanece aberta.

## 1. Base factual e limites

A investigação da EP126 encontrou Bacula Director 15.0.3 healthy, 12 blocos `Job`, nenhum `Schedule` ou referência a `Schedule` reconhecidos por filtro textual em `/etc/bacula-runtime/bacula-dir.conf`, ausência de `bconsole.conf` nos caminhos examinados e ausência de jobs futuros exibidos no Bacularis para 90 dias. Histórico de JobId 22 (backup MariaDB, 06/10/2026, 0 erros) e JobId 23 (restore histórico) foi observado. Timers systemd, cron principal e crontab da conta atual não demonstraram agendamento Bacula. Crontabs de outras contas, includes não convencionais e mecanismos internos de containers **não foram exaustivamente auditados**.

**Hipótese:** não há agendamento periódico demonstrado; **não afirmar inexistência universal**. Ver detalhes e evidências em `GA09-EP126-BCONSOLE-AGENDAMENTOS-20261028.md`.

## 2. Pré-condições antes de habilitar

- [ ] Confirmar com suporte/professor a política de RPO/RTO e janela de backup (horário local, carga e manutenção).
- [ ] Confirmar os **nomes reais** dos recursos `Job`, `JobDefs`, `Pool`, `Storage`, `Client` e `FileSet` da configuração ativa; não inferir nomes a partir de Jobs históricos.
- [ ] Confirmar que a configuração em disco é a configuração carregada pelo Director e como ela é gerada (volume, Compose, templates, CI).
- [ ] Verificar volume de dados, espaço livre, crescimento, retenção, volumes e reciclagem do pool.
- [ ] Definir usuário autorizado para operar console, sem copiar credenciais do Director nem publicar `bconsole.conf` com segredo.
- [ ] Aprovar rollback: backup da configuração original, checksum, revisão de diff, teste sintático e retorno à versão anterior.
- [ ] Validar proteção de credenciais e de dados pessoais em backups, logs e evidências.

## 3. Modelo de Schedule — EXEMPLO NÃO APLICÁVEL SEM AJUSTES

O trecho abaixo é **modelo Bacula** para revisão, não um arquivo pronto para deploy. A periodicidade é **hipótese de projeto** e depende de aprovação de RPO/RTO. Não acrescentar ao runtime sem verificar a sintaxe na versão instalada e os nomes dos Jobs.

```bacula
Schedule {
  Name = "ConectaEducaMariaDBDailyExample"
  Run = Full daily at 02:00
}
```

Após aprovação, associar **ao Job correto identificado na configuração efetiva**, com `Schedule = "ConectaEducaMariaDBDailyExample"` e avaliar uma política Full/Incremental separadamente. Não habilitar todos os 12 Jobs indiscriminadamente: há Jobs de restauração e possivelmente tarefas operacionais que **não devem** ser disparadas automaticamente. Em particular, **não agendar Jobs de Restore**.

A retenção é configurada em recursos apropriados (`Pool`, `Client` e/ou catálogo), **não** pelo `Schedule`. Dimensioná-la conforme política aprovada e capacidade real; não presumir valores.

## 4. Plano de mudança controlada

1. Revisar PR e evidências, obter aceite institucional.
2. Identificar fonte de verdade do arquivo de configuração (Git/Compose/volume); nunca editar manualmente o arquivo gerado sem garantir persistência e rollback.
3. Preparar patch mínimo apenas para os Jobs de backup aprovados e respectivos schedules; evitar mexer em Jobs de Restore.
4. Validar sintaxe/configuração com ferramenta da imagem em ambiente de teste autorizado, sem expor segredos.
5. Aplicar em janela aprovada, registrar hash de configuração e versão; reinício/reload somente se previsto e autorizado.
6. Confirmar agendamento **carregado** no Director e próximo disparo (não apenas presença de texto no arquivo).
7. Acompanhar ao menos uma execução real concluída, logs de erro, número de arquivos, bytes e catálogo.
8. Realizar restore controlado em destino isolado e autorizado; comparar SHA-256 dos dados restaurados com referência válida e registrar duração.
9. Verificar monitoramento/alerta de falha, rotação/retenção e plano de recuperação. Só então avaliar aceite GA-09.

## 5. Critérios objetivos de aceite

| Gate | Evidência necessária | Estado em 28/10 |
| --- | --- | --- |
| GA09-A | Jobs de backup e restore identificados, sem automatizar Restore | Pendente |
| GA09-B | Schedule aprovado e efetivamente carregado no Director | Pendente |
| GA09-C | Próxima execução visível e consistente com RPO | Pendente |
| GA09-D | Backup recente concluído sem erro e catálogo verificável | Pendente |
| GA09-E | Restauração real supervisionada, hash SHA-256 comparado | Pendente |
| GA09-F | Retenção/capacidade/alerta de falha comprovados | Pendente |
| GA09-G | Rollback, evidências e diário registrados | Pendente |

**Importante:** os 20/20 testes de restore sintético em CI são válidos como teste de lógica/verificador, **não substituem** GA09-E.

## 6. Handoff para suporte e Daily 9

**Achado:** infraestrutura Bacula operacional com histórico consultável, mas agendamento automático não demonstrado no Director nem nos agendadores examinados. **Risco:** janela de perda de dados potencialmente maior que o RPO pretendido, ainda não quantificada. **Ação:** aprovar política de backup, configurar schedules apenas para Jobs de backup, comprovar execução recente e restore supervisionado com hash. **Situação:** correção preparada em documentação, **não implementada em runtime**.

**Próxima frente do Grupo A:** avançar na GA-08 (WAF/bridge Docker) ou GA-07 (retenção/rotação audit.log) apenas por revisão documental/código, sem alterar EP125/EP126/pfSense antes do aceite.
