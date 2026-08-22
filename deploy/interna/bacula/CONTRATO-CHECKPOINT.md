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

## Resultado

Somente após zero falhas o Bacula entra no checkpoint mestre e o baseline pode
avançar de `1.4-dlp-integrado` para a versão de backup.
