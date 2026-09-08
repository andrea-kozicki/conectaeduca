# Evidência — hardening do `HOME_NET` do Suricata na EP125 (07/09/2026)

## Objetivo
Restringir o `HOME_NET` do Suricata da EP125 ao segmento real da DMZ, reduzindo o escopo genérico RFC1918 sem interromper a captura local nem a integração com o Wazuh.

## Ambiente validado
- Host: `ep125-pucpr`
- Interface: `eth0`
- IPv4: `192.168.6.34/28`
- Rede diretamente conectada: `192.168.6.32/28`
- Suricata: serviço `active` e `enabled`
- Wazuh Manager: `192.168.6.50:1514`

## Estado anterior
A configuração ativa continha:

```yaml
HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
```

Esse baseline abrangia as redes privadas RFC1918 de forma ampla.

## Alteração aplicada
O `HOME_NET` foi restringido para a DMZ real:

```yaml
HOME_NET: "[192.168.6.32/28]"
```

A mudança foi aplicada somente depois de confirmar o host, o IP e a rede diretamente conectada.

## Segurança e rollback
Antes da edição:
- foi criado backup preservando atributos em `/var/backups/conectaeduca/suricata/`;
- o SHA-256 do backup foi comparado ao arquivo original e conferiu;
- a alteração foi mínima e isolada à linha `HOME_NET`;
- nenhum shell root persistente foi utilizado;
- elevação administrativa ocorreu somente em comandos específicos.

Backup produzido:

`/var/backups/conectaeduca/suricata/suricata.yaml.pre-homenet-20260907-214409.bak`

SHA-256 original do `suricata.yaml`:

`458226a8b5660236b951dee84667e291390c3271a303990394c573180eb8e99d`

SHA-256 após a alteração:

`3257e2e18bd0c81f013583dc4f5a230d434d7ea707bfc357b94ce98d79a6c825`

O rollback automático não foi necessário.

## Validação técnica
A nova configuração foi validada antes do restart:

```text
suricata -T -c /etc/suricata/suricata.yaml
Configuration provided was successfully loaded. Exiting.
```

Após restart controlado:
- Suricata permaneceu `active`;
- `eve.json` permaneceu disponível;
- tráfego HTTPS benigno foi gerado;
- `eve.json` cresceu de `12048064` para `12079414` bytes;
- Wazuh Agent permaneceu `active`;
- sessão TCP para `192.168.6.50:1514` permaneceu presente;
- a coleta de `/var/log/suricata/eve.json` continuou configurada no Wazuh Agent.

## Resultado

```text
PASS=23 WARN=0 FAIL=0
Alteração aplicada: 1
Rollback executado: 0
```

Gate final aprovado: `HOME_NET` restrito a `192.168.6.32/28` e Suricata ativo.

## Evidência e integridade
Relatório operacional:

`conectaeduca-homenet-suricata-20260907-214409.txt`

SHA-256 do relatório enviado para validação:

`0e04e9cacd68c316a238ee2eb93a0f96ea8d17b12d87034d791930c6ddcfbf2b`

## Conclusão
O hardening reduziu o domínio considerado interno pelo IDS para o segmento efetivamente atribuído à DMZ da EP125, mantendo a validação sintática, o serviço Suricata, a produção de telemetria e o envio ao Wazuh sem regressão observada.
