# Ferret Scan — DLP interno

Este diretório define o serviço Ferret Scan persistente da VM interna do ConectaEduca.

## Papel arquitetural

O Ferret realiza detecção/redação de conteúdo sensível em arquivos e fluxos controlados. Ele não recebe, por padrão, credenciais do MariaDB nem acesso ao OpenBao.

A integração inicial ocorre por quatro superfícies:

1. Web UI administrativa local em `127.0.0.1:18082` no laboratório;
2. diretório runtime `inbox/` para varreduras CLI controladas;
3. diretório runtime `reports/raw/` para relatórios brutos locais do Ferret;
4. diretório runtime `events/` para eventos minimizados que poderão ser ingeridos/monitorados pelo Wazuh posteriormente.

O binding da Web UI é parametrizável por `FERRET_BIND_ADDRESS` e `FERRET_WEB_PORT`, mas o padrão seguro continua sendo loopback. A mudança para um endereço da VM só deve ocorrer junto com a política de acesso administrativo da equipe.

## Persistência

O container usa `restart: unless-stopped`. O estado operacional que precisa sobreviver à recriação do container fica em `deploy/interna/ferret/.runtime/`, fora do Git:

- `state/`: supressões e estado do Ferret;
- `inbox/`: material potencialmente sensível a analisar;
- `reports/raw/`: resultados brutos de varredura, nunca destinados diretamente ao SIEM;
- `events/`: eventos JSONL minimizados para futura ingestão pelo Wazuh Agent.

Não versionar conteúdo desses diretórios.

## Segurança do container

- imagem fixada por digest;
- usuário não-root original da imagem (`ferret`, UID/GID 1000);
- root filesystem somente leitura;
- capabilities removidas;
- `no-new-privileges` habilitado;
- `/tmp` em tmpfs com limite;
- nenhuma montagem do Docker socket;
- única porta publicada no laboratório: `127.0.0.1:18082`.

A Web UI não deve ser publicada diretamente em rede não confiável. O acesso remoto definitivo deverá passar pela camada administrativa da arquitetura (pfSense/Twingate ou mecanismo equivalente definido pela equipe).

## Fronteira de integração

O baseline não concede ao Ferret credenciais do MariaDB nem tokens do OpenBao. A integração com dados ocorre por material controlado em `inbox/`; a integração de observabilidade com o Wazuh será feita somente sobre eventos sanitizados em `events/`, nunca sobre o relatório bruto. Isso permite comunicação entre componentes sem criar uma rede plana nem ampliar privilégios do DLP.

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

O baseline fixa Ferret Scan 2.2.1. Nessa versão, uma varredura JSON sem findings pode resultar em `[]`, enquanto uma varredura com findings usa um objeto com `results` e `stats`. O sanitizador aceita somente o array **vazio** como shape legado conhecido e o canonicaliza antes de criar o evento SIEM. Arrays não vazios e outros shapes inesperados continuam falhando de forma fechada.

Essa camada pode ser simplificada após uma futura atualização validada do Ferret que incorpore o formatter JSON sempre-objeto descrito no changelog upstream.

## Pipeline operacional de eventos

A partir do baseline DLP operacional, a saída do Ferret é separada em duas camadas:

```text
inbox/ -> Ferret -> reports/raw/ -> sanitizar_ferret.py -> events/dlp.jsonl
```

O relatório bruto permanece local e protegido. O arquivo `events/dlp.jsonl` usa contrato próprio do ConectaEduca, com allowlist de campos, e é a única superfície prevista para futura ingestão pelo Wazuh Agent.

Para processar todos os arquivos regulares da inbox em modo detect-only:

```fish
fish scripts/dlp/processar_inbox_ferret.fish --todos
```

Para processar apenas um arquivo diretamente dentro da inbox:

```fish
fish scripts/dlp/processar_inbox_ferret.fish --arquivo exemplo.txt
```

O pipeline registra o SHA-256 do artefato em `.runtime/state/processed.sha256` e evita reprocessamento acidental. Use `--force` apenas quando uma nova varredura do mesmo conteúdo for intencional.

Consulte `CONTRATO-EVENTOS-DLP.md` antes de integrar o JSONL ao Wazuh e `RETENCAO.md` antes de habilitar qualquer limpeza automática.
