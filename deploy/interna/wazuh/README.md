# Wazuh — ConectaEduca

Stack Wazuh single-node usada como núcleo de SIEM e observabilidade de segurança do ConectaEduca.

## Evolução do bloco Wazuh

O Wazuh passou por quatro estados distintos:

1. **laboratório central:** Manager/Indexer/Dashboard e certificados;
2. **integração DLP:** regras para eventos sanitizados do Ferret validadas por `wazuh-logtest`;
3. **preparação anti-APT:** FIM, Active Response e YARA versionados;
4. **validação nas VMs:** agentes EP125/EP126 ativos, FIM/YARA exercitado e porta de enrollment fechada após bootstrap.

Essa sequência é importante: a telemetria de endpoint não foi declarada pronta apenas porque os arquivos existiam no Git; ela só passou a estado **validado** depois do teste operacional nas VMs.

## Baseline atual

- Wazuh Manager, Indexer e Dashboard 4.14.7;
- imagens fixadas por digest;
- certificados, chaves e credenciais somente em `.runtime/`, fora do Git;
- Indexer API 9200 e Manager API 55000 sem publicação externa;
- Dashboard restrito à superfície administrativa definida na implantação;
- TCP/1514 publicado somente para tráfego de agentes necessário;
- TCP/1515 removido da publicação de host após o enrollment;
- regras DLP/Ferret carregadas;
- decoder/regras YARA carregados;
- Active Response YARA integrado ao Manager;
- agentes das duas VMs registrados e ativos no checkpoint operacional.

## Testes e resultados

| Teste | Resultado |
|---|---|
| `wazuh-logtest` DLP | eventos JSONL sanitizados classificados pelas regras customizadas |
| configuração Manager | `configtest` aprovado após integração das regras/decoders |
| agents EP125/EP126 | ambos permaneceram **Active** por TCP/1514 |
| FIM em diretório sintético EP125 | criação/modificação produziu evento compatível com regras 110200/110201 |
| Active Response YARA | acionamento local executado sobre marcador sintético |
| resultado YARA | decoder `conectaeduca_yara_decoder*` + regra 110211 nível 12 |
| enrollment | após registro dos agentes, TCP/1515 deixou de ser publicado pelo overlay de host |

## Integração Ferret / DLP

O Wazuh não deve ingerir `inbox/` nem `reports/raw/`.

Fluxo:

```text
Ferret
  -> relatório bruto local
  -> sanitizador allowlist
  -> events/dlp.jsonl
  -> Wazuh Agent da VM interna
  -> Wazuh Manager
```

A classificação do contrato no Manager foi validada. A documentação não deve assumir que relatório bruto ou conteúdo sensível atravessa para o SIEM.

Consulte `INTEGRACAO-FERRET-DLP.md`.

## YARA / anti-APT

Fluxo validado:

```text
Wazuh Agent / FIM
    -> arquivo sintético criado ou modificado
    -> regra 110200/110201
    -> Active Response local
    -> YARA
    -> active-responses.log
    -> decoder
    -> regra 110211 nível 12
```

Consulte `INTEGRACAO-YARA-ANTIAPT.md`.

## Superfície administrativa

O estado pós-enrollment segue o princípio de fechar superfícies temporárias:

- 1514: necessário para agentes já registrados;
- 1515: não publicado permanentemente;
- 9200: não publicado para outras zonas;
- 55000: não publicado para outras zonas;
- Dashboard: acesso administrativo restrito.

Uma nova operação de enrollment deve ser tratada como mudança controlada e temporária.

## Limites e pendências

- DLP ponta a ponta via Agent deve manter evidência sanitizada quando executado;
- pfSense → Wazuh syslog permanece separado enquanto não houver receptor/protocolo definido;
- regras YARA externas de inteligência de ameaças não entram automaticamente na baseline;
- retenção deve ser recalibrada com consumo real da VM interna.
