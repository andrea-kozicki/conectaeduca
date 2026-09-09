# Wazuh — ConectaEduca

Stack Wazuh single-node usada como núcleo de SIEM e observabilidade de segurança do ConectaEduca.

## Evolução do bloco Wazuh

O Wazuh passou por cinco estados distintos:

1. **laboratório central:** Manager/Indexer/Dashboard e certificados;
2. **integração DLP:** regras para eventos sanitizados do Ferret validadas por `wazuh-logtest`;
3. **preparação anti-APT:** FIM, Active Response e YARA versionados;
4. **validação nas VMs:** agentes EP125/EP126 ativos, FIM/YARA exercitado e porta de enrollment fechada após bootstrap;
5. **centralização por zona:** EP125 e EP126 migradas para grupos dedicados com policies byte-exatas canonicalizadas e telemetria pós-migração validada.

Essa sequência é importante: a telemetria de endpoint não foi declarada pronta apenas porque os arquivos existiam no Git; ela só passou a estado **validado** depois do teste operacional nas VMs e da observação do estado no Manager.

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
- agente EP125 (`001`) centralizado exclusivamente em `conectaeduca-dmz`, `Active` e `synchronized`;
- agente EP126 (`002`) centralizado exclusivamente em `conectaeduca-interna`, `Active` e `synchronized`;
- policy DMZ canonicalizada em `groups/conectaeduca-dmz/agent.conf` com SHA-256 `a4df1ce1b8e2affa766fa1164c157d25aea150e07fa43d90b3a4e3d43610b57b`;
- policy interna canonicalizada em `groups/conectaeduca-interna/agent.conf` com SHA-256 `41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b`;
- Ferret DLP → Wazuh Agent EP126 → Manager → regra 110113 → alerta validado ponta a ponta;
- EP125 pós-centralização com estado FIM, SCA, Syscollector e continuidade Suricata comprovados no Manager.

## Policies centralizadas por zona

```text
Wazuh Manager
├── conectaeduca-dmz
│   └── Agent 001 / ep125-pucpr
└── conectaeduca-interna
    └── Agent 002 / ep126-pucpr
```

As fontes declarativas canonicalizadas ficam em:

```text
deploy/interna/wazuh/groups/
├── conectaeduca-dmz/agent.conf
└── conectaeduca-interna/agent.conf
```

Esses arquivos foram extraídos diretamente do Manager somente depois da validação operacional e conferidos byte a byte pelos SHAs conhecidos. Não foram reconstruídos a partir de inventário semântico.

## Testes e resultados

| Teste | Resultado |
|---|---|
| `wazuh-logtest` DLP | eventos JSONL sanitizados classificados pelas regras customizadas |
| configuração Manager | `configtest` aprovado após integração das regras/decoders |
| agents EP125/EP126 | ambos permaneceram **Active** por TCP/1514 |
| centralização EP126 | agente `002` migrou de `default` para `conectaeduca-interna`, permaneceu `Active` e `synchronized` |
| DLP E2E EP126 | finding sintético `high` gerou alerta real `110113` level 12 no Manager, `ALERT_DELTA=1`, `E2E_PROVEN=1` |
| centralização EP125 | agente `001` migrou de `default` para `conectaeduca-dmz` após poda de oito colisões locais; sync estrito validado em leituras consecutivas |
| telemetria EP125 pós-centralização | FIM 4883 registros, 150 sob `/opt/conectaeduca`; SCA 3954; Syscollector 2417; 41 alertas frescos e pelo menos 1 Suricata após o restart |
| FIM em diretório sintético EP125 | criação/modificação produziu evento compatível com regras 110200/110201 |
| Active Response YARA | acionamento local executado sobre marcador sintético |
| resultado YARA | decoder `conectaeduca_yara_decoder*` + regra 110211 nível 12 |
| enrollment | após registro dos agentes, TCP/1515 deixou de ser publicado pelo overlay de host |

Consulte também `docs/evidencias/wazuh-ep125-centralizacao-telemetria-20260909.md`.

## Integração Ferret / DLP

O Wazuh não deve ingerir `inbox/` nem `reports/raw/`.

Fluxo validado na EP126:

```text
Ferret
  -> relatório bruto local
  -> sanitizador allowlist
  -> events/dlp.jsonl
  -> Wazuh Agent 002 / EP126
  -> Wazuh Manager
  -> decoder JSON
  -> regra 110113 / level 12
  -> alerta
```

A classificação do contrato e o transporte pelo Agent foram validados. O teste ponta a ponta usou evento sintético e sanitizado, sem dado pessoal ou segredo real, e resultou em `ALERT_110113_DELTA=1` e `E2E_PROVEN=1`.

A documentação não deve assumir que relatório bruto ou conteúdo sensível atravessa para o SIEM.

Consulte `INTEGRACAO-FERRET-DLP.md` e `ESTADO-VALIDADO-EP126.md`.

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

O validador `scripts/implantacao/validar_wazuh_operacional.sh` segue esse baseline: por padrão, reprova TCP/1515 publicada. Durante uma janela consciente de enrollment, a exceção deve ser explícita com `--permitir-enrollment-1515` e removida ao final da operação.

## Limites e pendências

- os checkouts operacionais EP125/EP126 ainda precisam ser reconciliados com o `main` canônico antes do freeze, sem alterar o runtime já validado durante essa reconciliação;
- pfSense → Wazuh syslog permanece separado enquanto não houver receptor/protocolo definido;
- regras YARA externas de inteligência de ameaças não entram automaticamente na baseline;
- retenção deve ser recalibrada com consumo real da VM interna;
- revisão de API/RBAC e módulos restantes do Wazuh ainda precede a declaração do bloco de serviço como integralmente concluído;
- o fechamento pós-merge/overlays e o gate `.runtime/stack.env` permanecem separados do fechamento funcional das integrações.

### Preflight de permissões das regras/decoders customizados

Antes de recriar o `wazuh.manager`, execute:

```bash
./preparar-permissoes-config.sh
```

O preflight normaliza para `0644` apenas os arquivos XML versionados em
`config/decoders/` e `config/rules/`. Esses arquivos contêm configuração
não secreta e precisam ser legíveis pelo processo `wazuh-analysisd`
(UID/GID 999 no container). Isso evita que um `umask` restritivo do host
materialize regras/decoders como `0600`, fazendo o Manager ignorá-los com
`Permission denied`.

O script não acessa `.runtime/`, certificados, credenciais ou outros
artefatos locais.
