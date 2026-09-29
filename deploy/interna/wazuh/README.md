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
- as chaves privadas de assinatura `root-ca.key` e
  `root-ca-manager.key` são retidas somente no host emissor, com modo
  `0400` ou `0600`; não são montadas nos serviços Wazuh de longa duração;
- Indexer API 9200 e Manager API 55000 sem publicação externa;
- Dashboard restrito à superfície administrativa definida na implantação;
- TCP/1514 publicado somente para tráfego de agentes necessário;
- TCP/1515 removido da publicação de host após o enrollment;
- regras DLP/Ferret carregadas;
- decoder/regras YARA carregados;
- Active Response YARA integrado ao Manager;
- agente EP125 (`001`) centralizado exclusivamente em `conectaeduca-dmz`, `Active` e `synchronized`;
- agente EP126 (`002`) centralizado exclusivamente em `conectaeduca-interna`, `Active` e `synchronized`;
- policy DMZ canonicalizada em `groups/conectaeduca-dmz/agent.conf` com SHA-256 `2d8ef25b84b4f7a0af0faa9c3008fc3101570e7ed7c4c7abed9e5bda6dea376b`;
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
| pfSense Remote Logging → receiver host | três probes sintéticos distintos da EP125 foram correlacionados dentro dos datagramas recebidos em `192.168.6.50:5514/UDP`; `MATCHED_PROBE_INDICES=[1,2,3]`, `FINAL=PASS` |

Consulte também `docs/evidencias/wazuh-ep125-centralizacao-telemetria-20260909.md` e `docs/evidencias/pfsense-wazuh-live-receiver-20260917.md`.

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

## Identidade técnica de pentest e PKI da API

Em 16/09/2026 foi validado o caminho read-only da identidade técnica
`teste` no Wazuh:

```text
teste
  -> Wazuh Dashboard / Indexer Security
  -> backend_roles kibanauser + readall
  -> wazuh-wui com run_as=true
  -> Wazuh RBAC readonly (role id=2)
  -> Manager API interna :55000
```

A API Manager deixou de usar o certificado self-signed padrão como endpoint do
fluxo do Dashboard. O reconciliador versionado
`scripts/implantacao/reconciliar_wazuh_api_pki.py` emite um certificado
assinado pela CA do runtime, com SANs `wazuh.manager` e `localhost`, cria
backup privado antes da troca, reinicia somente o Manager e valida o acesso do
`wazuh-wui` sem `-k`.

Para tornar esse APPLY reproduzível, o preparador canônico
`scripts/implantacao/vms/10-interna/12-preparar-wazuh-runtime-vm.sh`
considera o runtime completo somente quando as chaves privadas de assinatura
`root-ca.key` e `root-ca-manager.key` também existem e permanecem privadas
(`0400`/`0600`). Essas chaves ficam apenas em `.runtime/certs`, diretório
ignorado pelo Git, e não são expostas aos containers Wazuh permanentes.

A identidade é gerenciada por
`scripts/implantacao/reconciliar_wazuh_teste_readonly.py`, que oferece:

- CHECK somente leitura;
- APPLY com confirmação explícita e rollback;
- REVOKE com confirmação explícita;
- senha recebida por `getpass`, nunca por argv;
- fallback por bcrypt nativo quando a política do Indexer rejeita a senha
  padrão obrigatória do laboratório, sem relaxar a política global;
- testes E2E positivo/negativo do RBAC.

O E2E independente confirmou autenticação real pelo Dashboard publicado em `https://wazuh.dashboard:443`, leitura de agentes, filtragem da listagem administrativa, HTTP 403 para consulta explícita de usuário administrativo e HTTP 403 para um `POST /security/users` mutante com credencial sintética efêmera gerada apenas em memória, mantendo 55000/9200 sem publicação no host.

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

- os checkouts operacionais EP125/EP126 ainda precisam terminar sincronizados com o
  `FREEZE_COMMIT` canônico; essa reconciliação não deve alterar o runtime já
  validado;
- o receptor pfSense → Wazuh teve transporte e correlação inicial comprovados.
  O gate live remanescente é o **OPS-01 pós-reboot**, que exige nova correlação
  do marker pfSense no Wazuh depois da retomada final; a prova histórica do
  receiver não substitui esse teste;
- na validação atual, `logall=no` e `logall_json=no`; por isso um syslog
  recebido que não dispare alerta pode não aparecer em `archives.json` ou
  Threat Hunting;
- regras YARA externas de inteligência de ameaças não entram automaticamente na
  baseline;
- retenção deve ser recalibrada com consumo real da VM interna;
- a revisão de API/RBAC/identidade read-only da camada de serviço já foi
  concluída e não permanece como gate aberto;
- o contrato runtime atual **não usa `.runtime/stack.env`**. Os artefatos
  canônicos são `.runtime/manager.env`, `.runtime/dashboard.env`,
  `.runtime/internal_users.yml`, `.runtime/wazuh.yml` e o conjunto de
  certificados/chaves em `.runtime/certs/`. O fechamento final deve usar
  `scripts/implantacao/validar_wazuh_operacional.sh` para verificar esses
  artefatos e a composição efetivamente aplicada.

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
