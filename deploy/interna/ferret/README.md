# Ferret Scan — DLP interno

Este diretório define o serviço Ferret Scan persistente da VM interna do ConectaEduca.

## Papel arquitetural

O Ferret realiza detecção/redação de conteúdo sensível em arquivos e fluxos controlados. Ele não recebe, por padrão, credenciais do MariaDB nem acesso ao OpenBao.

A integração inicial ocorre por quatro superfícies:

1. Web UI administrativa local em `127.0.0.1:18082` no laboratório;
2. diretório runtime `inbox/` para varreduras CLI controladas;
3. diretório runtime `reports/raw/` para relatórios brutos locais do Ferret;
4. diretório runtime `events/` para eventos minimizados destinados à coleta pelo Wazuh Agent.

O binding da Web UI é parametrizável por `FERRET_BIND_ADDRESS` e `FERRET_WEB_PORT`, mas o padrão seguro continua sendo loopback. A mudança para um endereço da VM só deve ocorrer junto com a política de acesso administrativo da equipe.

## Persistência

O container usa `restart: unless-stopped`. O estado operacional que precisa sobreviver à recriação do container fica em `deploy/interna/ferret/.runtime/`, fora do Git:

- `state/`: supressões e estado do Ferret;
- `inbox/`: material potencialmente sensível a analisar;
- `reports/raw/`: resultados brutos de varredura, nunca destinados diretamente ao SIEM;
- `events/`: eventos JSONL minimizados destinados ao Wazuh Agent nativo da VM interna.

Não versionar conteúdo desses diretórios.

### Drop-zone do pentest sem sudo

Quando `/etc/conectaeduca/pentest-principal.uid` estiver materializado, o
bootstrap preserva o runtime sob UID/GID 1000 e aplica ACL mínima somente no
caminho de entrada:

- `.runtime/`: o principal de pentest recebe apenas `--x` para atravessar o
  diretório sem listá-lo;
- `.runtime/inbox/`: recebe `-wx`, sem permissão de listagem;
- a inbox mantém sticky bit para impedir remoção de entradas pertencentes a
  outros usuários;
- arquivos novos herdam uma ACL que concede leitura ao UID 1000 do runtime
  Ferret;
- `state/`, `reports/raw/`, `events/` e a configuração permanecem sem
  escrita para o principal de pentest.

O projeto não cria uma conta Linux `teste` dentro do container. A identidade
humana permanece no host e o daemon continua usando a service account
`ferret`. Em VMs institucionais, o UID numérico 1000 pode corresponder a uma
conta administrativa do host; isso é tratado como trust boundary da
infraestrutura e não deve ser alterado pelo projeto.

A submissão suportada pelo pentest não é `mv`/rename direto para a inbox.
Arquivos já existentes podem preservar modo/ACL incompatíveis com a leitura do
runtime UID 1000. Use o helper zero-sudo, que cria um novo inode dentro da
drop-zone, força o contrato de ACL herdável e valida a leitura do UID runtime:

```bash
python3 scripts/dlp/submeter_ferret_pentest.py ./artefato-sintetico.txt
```

O pipeline, por sua vez, não monta o pathname controlado pelo remetente:
`snapshot_ferret_input.py` abre a entrada com `openat(O_NOFOLLOW)`, copia o
inode aberto para `.runtime/state/incoming/` protegido, calcula o SHA-256 sobre
esse snapshot e monta somente o snapshot no scanner efêmero. Snapshots ativos
são limpos também em `EXIT/HUP/INT/TERM`.

## Segurança do container

- imagem fixada por digest;
- usuário não-root original da imagem (`ferret`, UID/GID 1000);
- root filesystem somente leitura;
- capabilities removidas;
- `no-new-privileges` habilitado;
- `TMPDIR=/home/ferret/tmp` da imagem atendido por tmpfs dedicado, sem relaxar o root filesystem read-only;
- nenhuma montagem do Docker socket;
- única porta publicada no laboratório: `127.0.0.1:18082`.

A Web UI não deve ser publicada diretamente em rede não confiável. O acesso remoto definitivo deverá passar pela camada administrativa da arquitetura (pfSense/Twingate ou mecanismo equivalente definido pela equipe).

## Fronteira de integração

O baseline não concede ao Ferret credenciais do MariaDB nem tokens do OpenBao. A integração com dados ocorre por material controlado em `inbox/`; a integração de observabilidade usa somente eventos sanitizados em `events/`, nunca o relatório bruto. As regras que classificam esse contrato já foram validadas no Wazuh Manager; a coleta real por agente será ativada na VM interna. Isso permite comunicação entre componentes sem criar uma rede plana nem ampliar privilégios do DLP.

## Varredura CLI controlada

Após colocar arquivos em `.runtime/inbox/`, um exemplo de auditoria profunda é:

```bash
docker compose -f deploy/interna/ferret/compose.yml run --rm --no-deps ferret \
  --file /data/inbox \
  --profile conectaeduca-deep \
  --config /etc/ferret/ferret.yaml \
  --suppression-file /var/lib/ferret/suppressions.yaml \
  --output /data/reports/raw/ferret-deep.json
```

O perfil automático mantém `show_match: false`.

## Compatibilidade do formatter JSON

O baseline fixa Ferret Scan 2.4.3 pelo digest validado na EP126. Em validação isolada realizada em 2026-09-04 com a mesma imagem implantada, tanto o scan limpo quanto o scan com finding retornaram objeto JSON com `stats` e `results`; o caso limpo retornou `results: []` e o caso sintético produziu um finding real.

O relatório bruto pode conter campos como `text` e `filename`. O perfil `conectaeduca-deep` mantém `show_match: false` e, na evidência do finding sintético, o campo `text` foi devolvido como `[HIDDEN]`. Ainda assim, esses campos não pertencem à allowlist do evento SIEM e não são propagados pelo sanitizador.

A compatibilidade de transição com o array vazio do Ferret 2.2.1 foi retirada do pipeline atual. O contrato pós-2.4.3 exige objeto JSON e falha de forma fechada para shapes inesperados.

## Pipeline operacional de eventos

A partir do baseline DLP operacional, a saída do Ferret é separada em duas camadas:

```text
inbox/ -> Ferret -> reports/raw/ -> sanitizar_ferret.py -> events/dlp.jsonl
```

O relatório bruto permanece local e protegido. O arquivo `events/dlp.jsonl` usa contrato próprio do ConectaEduca, com allowlist de campos, e é a única superfície prevista para coleta pelo Wazuh Agent. O Manager já possui regras validadas para classificar esses eventos.

Para processar todos os arquivos regulares da inbox em modo detect-only nas VMs Ubuntu:

```bash
bash scripts/dlp/processar_inbox_ferret.sh --todos
```

Para processar apenas um arquivo diretamente dentro da inbox:

```bash
bash scripts/dlp/processar_inbox_ferret.sh --arquivo exemplo.txt
```

O pipeline registra o SHA-256 do artefato em `.runtime/state/processed.sha256` e evita reprocessamento acidental. Use `--force` apenas quando uma nova varredura do mesmo conteúdo for intencional.

Consulte `CONTRATO-EVENTOS-DLP.md` antes de integrar o JSONL ao Wazuh e `RETENCAO.md` antes de habilitar qualquer limpeza automática.

## Temporários, health e limites de recursos

A imagem Ferret Scan 2.4.3 define `TMPDIR=/home/ferret/tmp`. Com `read_only: true`, montar tmpfs somente em `/tmp` deixava o caminho realmente usado pelos uploads Web no root filesystem read-only. O serviço agora fornece tmpfs diretamente em `/home/ferret/tmp`, preservando `read_only`, `cap_drop: ALL` e `no-new-privileges`.

O endpoint funcional é `GET /health`. A imagem final é `scratch` e não traz shell, `curl` nem `wget`; portanto o projeto monitora esse endpoint pelo host com `scripts/observabilidade/verificar_ferret_health.sh` e timer systemd em vez de adicionar ferramentas à imagem só para um `HEALTHCHECK`.

### Limites medidos

Medição em 2026-09-12, depois da correção do TMPDIR:

- 1 MiB: pico ~29,9 MiB RSS e ~0,94 CPU equivalente;
- 32 MiB: pico ~331,6 MiB RSS e ~1,01 CPU equivalente; dois scans em ~56,5 s, cerca de 28,2 s por scan;
- 64 MiB: estresse chegou a ~609,4 MiB RSS e ~1 CPU, mas a resposta Web ultrapassou o `WriteTimeout` de 30 s do servidor upstream.

Por isso o upload máximo de 100 MiB da Web UI é tratado como limite de admissão, não como garantia de conclusão dentro do timeout HTTP.

O perfil CLI `conectaeduca-deep` usa `checks: all` e `fail_on_incomplete: true`. No Ferret 2.4.3, o validator `CLOUD_RESOURCES` possui um hard cap upstream de 5 MiB de conteúdo (`maxContentBytes = 5 << 20`). Acima desse conteúdo ele recusa a própria análise de forma explícita para reduzir risco de DoS; o scanner transforma a recusa em `coverage incomplete` e, com `fail_on_incomplete`, retorna código 3.

Por isso o ConectaEduca não remove `CLOUD_RESOURCES` só para produzir um resultado verde: a cobertura total do perfil profundo é validada com um workload conservador de 4 MiB. Conteúdo maior pode continuar sendo analisado parcialmente por outros validators, mas uma recusa de qualquer validator permanece fail-closed, não entra no ledger e não deve ser interpretada como "limpo". O limite de 5 MiB é sobre o conteúdo entregue ao validator, não uma promessa universal baseada apenas no tamanho bruto do arquivo.

Os limites de contenção adotados, com margem sobre o maior pico observado, são:

- memória: `1280m`;
- CPU: `2.00`;
- PIDs: `128`.

Os mesmos limites e o mesmo TMPDIR gravável são aplicados ao scanner efêmero do pipeline DLP.

### Operação

Após merge, o monitor de health, a retenção e o logrotate podem ser instalados por:

```bash
bash scripts/implantacao/instalar_ferret_operacao.sh install
```

Para somente verificar uma instalação existente:

```bash
bash scripts/implantacao/instalar_ferret_operacao.sh --check
```
