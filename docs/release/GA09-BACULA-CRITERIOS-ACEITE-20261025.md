# GA-09 — Bacula/Bacularis EP126: checklist de proteção e recuperação

**Data:** 25/10/2026 • **Status:** preparação documental para o operador; NÃO executar Jobs ou restaurações hoje.

## 1. Observações comprovadas e limites
- **Inventário EP126 25/10:** contêineres Bacula Director, Storage, PgBouncer e Catalog `running/healthy`; File Daemon do host ativo. Isto é saúde pontual, **não prova geração de backups novos, agendamento nem restauração íntegra**.
- **Bacularis (conta acadêmica `teste`, menor privilégio por desenho):** a aba de Jobs executados voltou a exibir histórico, sem o erro anterior `CF0019/Connection refused` para Director 9101. Jobs 22 (MariaDBBackup) e 23 (MariaDBRestore) datados de **06/10/2026**, com indicadores de sucesso; relatórios de outubro mostram atividades visíveis em 05–06/10. Nenhuma execução mais recente é visível nas três capturas de 25/10.
- **Aba de configurações Jobs:** lista vazia para `teste`. **Não** conclui ausência de Jobs ou schedules globais; é compatível com ACL restrita ou outro motivo a verificar pelo operador. Não elevar privilégios de `teste`.
- **Precedente da falha:** Director não conseguia alcançar Catalog PostgreSQL via PgBouncer; causa raiz do episódio não foi comprovada definitivamente. Um serviço `healthy` posterior não demonstra por si só a causa, correção permanente, ausência de lacunas ou integridade dos arquivos.

## 2. Perguntas que o suporte deve responder em 28/10
1. Existem Jobs ativos para MariaDB, OpenBao, Catalog e RecoveryState? Quais FileSets/Clients/Storage/Pool cada um cobre? Fornecer **resumo sanitizado**, nunca senhas ou paths sensíveis.
2. Há Schedules efetivamente associados e habilitados para cada Job? Em qual timezone? Qual a última e a próxima execução esperada?
3. Quais backups terminaram depois de 06/10, se houver? Se não houver, desde quando a rotina ficou interrompida e qual impacto em RPO/RTO?
4. A geração do material de staging (MariaDB/OpenBao/Catalog/RecoveryState) está atual? Os arquivos preparados em 05/10 podem estar desatualizados; o Catalog não deve ser confundido com dump consistente do banco.
5. Quais políticas de retenção, reciclagem, criptografia, permissão e armazenamento protegem os volumes? Existem mídia/cópias fora da VM adequadas ao requisito?
6. O Director voltou a utilizar PgBouncer conforme arquitetura com SCRAM/TLS `verify-full`? A falha histórica teve causa identificada? Não aplicar bypass direto ao Catalog como 'conserto' sem change control.
7. A conta `teste` deve ver apenas histórico? Quem tem permissão de visualizar definições de Jobs/efetuar restauração e quem aprova a operação?

## 3. Critérios de aceite para execução autorizada (somente com operador)
| Gate | Prova necessária | Não equivale |
|---|---|---|
| B01 — Catálogo disponível | Director e PgBouncer saudáveis, consulta Bacularis por operador autorizado | Apenas healthcheck ou histórico antigo |
| B02 — Rotina configurada | Config ativa dos Jobs, Client, FileSet, Storage e Schedule, última/próxima execução com timezone | Nome de Job cadastrado sem agendamento |
| B03 — Material recente | Artefatos de staging produzidos sob procedimento consistente com origem e sem PII exposta | Arquivos de teste de setembro/outubro como prova contemporânea |
| B04 — Backup recente | Job autorizado executado por operador, concluído sem erro, bytes/arquivos e integridade verificados | Ícone verde histórico ou `bacula-fd active` |
| B05 — Restore sintético | Restaurar amostra FICTÍCIA para destino isolado (nunca sobrescrever produção); comparar SHA-256 entrada vs. recuperada, autorizar e registrar | Job tipo Restore com `success` sem validação de conteúdo |
| B06 — Monitoramento | Alertas por Job perdido/falha, prazo de próxima execução e responsáveis/reação | `Running: 0` no momento da captura |
| B07 — Rollback/privacidade | Cópia de configurações, limites de permissões, logs sanitizados e operação reversível | Conceder papel de operador à conta `teste` |

## 4. Sequência de reunião/ensaio
1. Receber aprovação para leitura operacional e para qualquer Job futuro, janela, finalidade e perfis.
2. Com operador administrativo próprio, inspecionar (somente leitura) Jobs/Schedules/FileSets/Clients/volumes, logs e staging; conferir sem despejar credenciais, keys nem relatórios sensíveis.
3. Definir execução de backup e restore sintéticos num horário aprovado. Usar dados controlados; evitar reuso de catálogos/dumps com dados pessoais.
4. Registrar `jobId`, relógio BRT, código de retorno, integridade por hash e evidências sanitizadas com custódia; demonstrar comparação arquivo de origem/restaurado.
5. Qualquer falha/restart inesperado suspende a validação, aciona registro e avaliação do rollback; não desviar o Director para PostgreSQL direto sem aprovação.
6. Atualizar issue #196 **somente após** comprovação de rotina corrente e restore íntegro, sem extrapolar um único ensaio para todos os datasets.

## 5. Trabalho finalizado no Grupo A (25/10)
**Concluído documentalmente:** inventário de 25/10, consulta read-only da conta `teste`, interpretação de menor privilégio, definição dos gates B01–B07, perguntas para operador e handoff.  
**Pendente do suporte:** Jobs/Schedules efetivos, periodicidade, falhas desde 06/10, monitoramento, prova de backup contemporâneo e restauração controlada.

**Nada foi executado na EP126:** sem `bconsole`, SQL, scripts de backup/restore, ajuste de privilégio, Docker restart/compose, ou mudança em PgBouncer/Director.

Rastreabilidade: issue #196, PR #200, cartão Grupo A e capturas Bacularis de 25/10.

## 6. GA-09.B — verificador de integridade de restauração sintética (26/10/2026)

**Estado:** ferramenta e suíte de regressão offline implementadas no PR #200 DRAFT. Não foi executado nenhum Job, restore ou procedimento administrativo Bacula na EP126. O resultado da CI não substitui os critérios **B01–B07**.

### Implementação e evidência executada

- **Script de validação:** `scripts/evidencias/ga09_verificar_restore_sintetico.py`.
- **Bateria:** `tests/python/test_ga09_restore_sintetico.py` com **20 cenários sintéticos** (TemporaryDirectory, sem dados institucionais).
- **Workflow:** `.github/workflows/ga09-restore-offline.yml` (`contents: read`, checkout por SHA fixado, sem secrets, Docker ou conexão às VMs).
- **Prova:** [GA09 Synthetic Restore Integrity — run 40408677705](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40408677705), job `121872966798`: **20/20 testes PASS**, `Ran 20 tests in 0.088s / OK` em 26/10/2026.

A ferramenta calcula **SHA-256 de cada arquivo** em duas árvores independentes, compara os nomes relativos, a estrutura de diretórios, os tamanhos e os conteúdos e exige ao menos um arquivo real na amostra. Faz uma releitura da origem ao final para reduzir o risco de aceitar uma amostra que mudou durante a conferência. Rejeita sem seguir links simbólicos, arquivos especiais, hardlinks, árvores aninhadas, amostras vazias, arquivos extras/ausentes ou maiores que o limite. Tenta identificar modificações durante a leitura pelo inode, tamanho e carimbos. Limites deliberados: **64 arquivos**, **8 MiB por arquivo** e **32 MiB totais** por árvore; não é utilitário para restauração integral de grandes bancos.

A saída imprime somente **PASS/FAIL, motivo categórico, contagem e total de bytes**, sem nomes, hashes individuais, conteúdo ou caminhos dos arquivos. Não cria/edita/apaga dados nem escreve relatórios no disco; o operador pode capturar a saída sanitizada em evidência externa. Exige `--synthetic`, confirmação explícita do caráter **fictício** das amostras.

### Utilização futura — somente com autorização para restaurar em sandbox

Após validação dos gates B01–B04 e autorização expressa do operador Bacula:

1. Criar **amostra fictícia original** com dois ou mais arquivos sem PII/segredos em diretório isolado fora das árvores reais da aplicação. **Preservar a referência original** e assegurar que a referência corresponde ao instante do backup aprovado; não recriar a origem após a restauração e chamá-la prova.
2. Operador realiza **backup da amostra** com Job, FileSet, Client/Storage e janela conhecidos; registrar `jobId`, status, timestamp/timezone e custódia.
3. Operador realiza **restore para segundo diretório isolado**, nunca sobrepondo sistema, dados ou a amostra original. Confirmar permissões e que os arquivos restaurados são exclusivamente sintéticos.
4. Executar a verificação **somente leitura** no checkout autorizado do mesmo código:

```bash
python3 scripts/evidencias/ga09_verificar_restore_sintetico.py \
  --synthetic \
  --source /CAMINHO_APROVADO/amostra-original \
  --restored /CAMINHO_APROVADO/amostra-restaurada
```

Saída **esperada, não observada na EP126**:

```text
GA09_RESTORE_VERIFY=PASS algorithm=SHA256 files=2 bytes=...
GA09_BACULA_RESTORE_EXECUTED=NAO
GA09_OPERATIONAL_RECOVERY_PROVEN=NAO
```

Os dois últimos campos sinalizam que o **verificador isoladamente não comprova** que o Bacula executou um restore; a prova conjunta exige correlação humana do `jobId`, mídia, FileSet, diretório destino, evidência do restore e controle de custódia. Um `PASS` só prova igualdade dos arquivos *lidos* no momento do teste.

**Não executar o comando em diretórios com dados reais**, nem usar com sudo, nem criar/manipular backups sem aprovação. Se qualquer verificação falhar, coletar apenas categorias de erro e interromper o aceite, sem copiar nomes ou conteúdo para GitHub/Trello.

### Cobertura negativa da suíte (todos em CI, não na EP126)

- Igualdade de um arquivo e dois arquivos em pastas aninhadas;
- Conteúdo alterado de mesmo tamanho, truncado, arquivo ausente ou extra;
- Link simbólico em origem, restauração ou raiz; hardlink; FIFO;
- Raízes iguais/aninhadas, árvore vazia e diretório vazio divergente;
- Arquivo acima do limite, ausência de `--synthetic`, saída minimizada e ausência de mutação dos arquivos.

**Limites residuais:** verificações estáticas/localizadas e hashes SHA-256 não atestam que o backup foi produzido *pelo* Bacula, agendamentos, restaurabilidade dos outros conjuntos (MariaDB/OpenBao/Catalog), RPO/RTO, consistência de transações, logs de mídia nem políticas de retenção. Condições de corrida envolvendo substituição de diretórios por operador externo ainda exigem sandbox confiável e quiescência. A integridade completa do backup/restore continua **NÃO COMPROVADA operacionalmente** até ensaio autorizado.

**Status GA-09:** critério B05 **instrumentado offline**, **não validado em produção**. Issue #196 e achado associado permanecem abertos.
