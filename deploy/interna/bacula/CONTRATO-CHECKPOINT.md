# Contrato do checkpoint Bacula

O checkpoint operacional futuro deve testar pelo menos:

## Estático

- arquivos obrigatórios;
- imagem/tag/digest e `linux/amd64`;
- Compose válido;
- ausência de `privileged`, `network_mode: host` e Docker socket;
- nenhum segredo versionado;
- FileSets allowlisted;
- TLS requerido;
- portas parametrizadas;
- Storage não localizado na DMZ;
- staging/volumes com permissões restritas;
- política de retenção versionada.

## Dinâmico

- Director, Storage e Catalog sobem;
- File Daemons respondem somente nos endpoints previstos;
- Director alcança FD;
- FD alcança Storage;
- Catalog persiste após recriação de container;
- backup sintético conclui;
- restore sintético conclui;
- SHA-256 pós-restore é idêntico;
- dump MariaDB sintético restaura e consulta corretamente;
- falha proposital é registrada como falha, não sucesso;
- relatório não contém senha/token/conteúdo;
- uso de disco é medido.

## Observabilidade

- evento sintético de sucesso é aceito;
- evento sintético de falha aciona regra esperada no Wazuh;
- conteúdo de backup nunca chega ao SIEM.

## Evidência operacional — cross-zone DMZ em 14/09/2026

O subconjunto crítico de backup/restore cross-zone foi validado nas VMs finais.

Controles comprovados:

- Director, Storage, Catalog e PgBouncer `healthy`;
- Director conectado às redes `bacula-backend` e `bacula-uplink`;
- Director -> File Daemon DMZ em TCP/9102;
- File Daemon DMZ -> Storage em TCP/9103;
- TLS observado no status do Client DMZ;
- backup sintético fresh concluído;
- origem removida após confirmação do backup;
- restore sintético concluído em diretório isolado;
- SHA-256 restaurado idêntico ao original;
- tamanho restaurado idêntico ao original;
- zero erros nos Jobs fresh;
- artefatos sintéticos removidos ao final;
- relatórios sanitizados sem material secreto.

Jobs da prova:

```text
DmzSmokeBackup  -> JobId 6 -> T -> 2 arquivos -> 8233 bytes -> 0 erros
DmzSmokeRestore -> JobId 7 -> T -> 2 arquivos -> 8233 bytes -> 0 erros
```

Evidência detalhada:

```text
docs/evidencias/bacula-crosszone-dmz-20260914.md
```

## Limitação de aceite

A prova funcional acima não elimina o risco de perda física total da VM interna
enquanto o Storage permanecer no mesmo disco virtual dos demais dados da VM.

A disponibilização de um segundo disco ou outro destino em domínio de falha
distinto depende de autorização acadêmica no ambiente fornecido.

Essa limitação deve ser tratada como risco residual separado do resultado do
backup/restore funcional; não deve ser mascarada por loop device criado no mesmo
disco.

## Resultado

Somente após zero falhas o Bacula entra no checkpoint mestre e o baseline pode
avançar de `1.4-dlp-integrado` para a versão de backup.

A evidência de 14/09/2026 comprova o fluxo cross-zone e o contrato de restore
sintético, mas não altera automaticamente os demais gates estáticos, de
observabilidade e de domínio de falha que continuem pendentes.
