# Observabilidade Bacula → Wazuh

O Bacula não deve enviar conteúdo dos backups ao SIEM. O Wazuh receberá somente
eventos operacionais minimizados.

## Eventos de interesse

- `backup_job_success`;
- `backup_job_failed`;
- `restore_test_success`;
- `restore_test_failed`;
- `catalog_backup_failed`;
- `storage_capacity_warning`;
- `storage_capacity_critical`;
- `openbao_snapshot_failed`;
- `mariadb_dump_failed`.

## Campos permitidos

- timestamp;
- component=`bacula`;
- event_type;
- job_name lógico;
- client_id lógico;
- level/severity;
- duration;
- bytes/arquivos agregados;
- status;
- backup_set_id/JobId quando não revelar segredo.

## Campos proibidos

- conteúdo do arquivo;
- dump SQL;
- senha;
- token;
- unseal share;
- chave privada;
- caminho que revele segredo desnecessário;
- linha de comando contendo credencial.

## Integração

O futuro Wazuh Agent nativo da VM interna poderá ler um JSONL sanitizado de
eventos Bacula. Não haverá bind de volumes de backup no Wazuh Manager.

Reservar para implementação a faixa de regras customizadas:

```text
110200-110219
```

A numeração será efetivada somente quando o contrato JSON for implementado e
testado com `wazuh-logtest`.

A falha de restore-test deve ter severidade superior a um job incremental
isolado que falhou, pois indica perda de confiança na recuperabilidade.
