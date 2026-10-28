# GA-09 / PA-07 — EP126: Bacula, histórico e investigação de agendamentos (28/10/2026)

> **Status:** diagnóstico parcial; sem reconciliação, deploy, execução de Job ou restore.
> Fonte: saídas de terminal e capturas Bacularis fornecidas pela responsável na sessão de 28/10/2026. Horários da interface não tiveram fuso confirmado. Este documento integra a seção GA-09 do pré-relatório; não equivale a aceite de recuperação.

## 1. Estado observado

- `conectaeduca-bacula-director` (Bacula 15.0.3), `conectaeduca-bacula-storage`, `conectaeduca-bacula-pgbouncer` e `conectaeduca-bacula-catalog`: `Up 23 hours (healthy)` na consulta.
- `conectaeduca-bacularis-webapi`: `Up 23 hours`, publicado apenas em `127.0.0.1:9097`. HTTP GET `/` respondeu **302**; acesso à interface como `teste` confirmado.
- Aba **Jobs**: tabela vazia para `teste`; **não** comprova inexistência de definições de Jobs.
- Aba **Jobs executados**, filtro `All jobs`: histórico visível, incluindo JobId **22** `ConectaEducaMariaDBBackup` (Full, 06/10/2026 01:21:44, 3 arquivos, 41,6 kB) e JobId **23** `ConectaEducaMariaDBRestore` (06/10/2026 01:24:28, 3 arquivos, 41,6 kB). Ícones verdes na tabela; **não** equivalem a teste de integridade atual.
- Detalhes do Job **22**: `Job Errors=0`, cliente `conectaeduca-interna-fd`, FileSet `ConectaEducaMariaDBSet`, pool `ConectaEducaOperationalPool`, volume `ConectaEducaOp002`, execução exibida de 01:21:44 a 01:21:45.
- Aba **Jobs agendados**: filtro data **28/10/2026**, **90 dias**, tabela vazia. Não prova inexistência de schedules: pode refletir permissão, configuração ou resposta da API.

## 2. Diagnóstico pontual do bconsole

```text
docker exec conectaeduca-bacula-director sh -c 'command -v bconsole || true'
/usr/sbin/bconsole
```

Tentativa de consulta **não executou os comandos internos** `status director`, `show schedules`, `list jobs`, pois o binário encerrou antes com:

```text
Config error: Cannot open config file "/etc/bacula/bconsole.conf": No such file or directory
```

Verificação de caminhos e montagens:

```text
/etc/bacula-runtime  <- volume
/run/pgbouncer       <- volume
/etc/bacula-runtime/tls <- volume
/etc/bacula-runtime/bacula-dir.conf  EXISTE
/etc/bacula-runtime/bconsole.conf   AUSENTE
/etc/bacula-runtime/bacula-fd.conf  AUSENTE
```

O `bacula-dir.conf` existe com permissões **0600**, proprietário **root:root**. A inspeção por cabeçalhos de recursos (sem valores, senhas ou certificados) revelou:

```text
Director: linha 1
Storage: linha 21
Client: linhas 38 e 103
FileSet: linhas 55, 120, 183, 193, 203 e 213
Job: linhas 75, 86, 140, 151, 235, 246, 257, 268, 279, 290, 301 e 312
Console: linha 165
```

**Conclusão restrita:** há 12 blocos `Job` e 1 bloco `Console` no arquivo consultado; **nenhum bloco `Schedule` foi identificado pelo filtro de cabeçalhos**, o que justifica investigação específica. Isso não comprova que não haja agendamento efetivo: diretivas internas de Job, includes, geração dinâmica e configuração efetivamente carregada ainda não foram inspecionados. O `bconsole -?` informa `-c <file>`, `-L`, `-t`; não presumir que o arquivo do Director possa ser usado como configuração do cliente.

## 3. Próximos passos seguros e critérios de aceite

1. **Somente leitura, sem segredos:** confirmar se o `bacula-dir.conf` inclui outros arquivos e se os Jobs referenciam `Schedule`, usando parser que imprima apenas nomes de diretivas e contagens, nunca valores ou o conteúdo completo do arquivo.
2. Localizar a configuração própria de `bconsole` ou procedimento institucional de console; **não gerar nem copiar credenciais do Director para a estação** e não criar `bconsole.conf` improvisado. Não usar `-c /etc/bacula-runtime/bacula-dir.conf` como se fosse configuração de console.
3. Confirmar schedules carregados e Jobs efetivamente programados com acesso autorizado, distinguindo limitação da interface `teste` de ausência de agendamentos.
4. Com aprovação, verificar Job recente, cobertura FileSet, retenção e teste de restauração supervisionado com hash de entrada/saída. Sem isso, GA-09 permanece **aberta**.
5. Registrar os resultados em `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md`; as capturas estão no chat e não foram copiadas para o repositório.

**Segurança:** `docker exec` oferece acesso privilegiado ao ambiente de contêiner; a autorização institucional e a não exposição de segredos permanecem necessárias. Nenhuma alteração de configuração, restart, Job, restore ou merge é documentada nesta etapa.
