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
