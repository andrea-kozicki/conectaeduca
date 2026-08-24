# Implantação das VMs — fase 1

Este diretório contém somente parâmetros **não secretos** e orientação de uso
dos scripts de implantação das duas VMs Ubuntu.

## Objetivo desta fase

Validar o host antes de subir containers e reutilizar os artefatos já
versionados no projeto. A fase 1 não ativa Twingate.

Identidades padronizadas:

- `CE-PFSENSE` / `conectaeduca-pfsense`;
- `CE-UBUNTU-DMZ` / `conectaeduca-dmz`;
- `CE-UBUNTU-INT` / `conectaeduca-interna`.

Papéis Ubuntu:

- `dmz`: Ubuntu da DMZ, classe 8 GiB RAM / 180 GB;
- `interna`: Ubuntu interna, classe 16 GiB RAM / 180 GB.

Consulte `IDENTIFICACAO-VMs.md` antes da implantação.

## Preflight

O primeiro gate é:

```text
scripts/implantacao/vms/00-base/05-preflight-ubuntu.sh
```

Ele possui três stages progressivos:

1. `base`: Ubuntu, amd64, RAM/disco, Docker, Compose, Git e baseline;
2. `network`: adiciona interface, IPv4, gateway e DNS esperados;
3. `deploy`: adiciona parâmetros dos serviços e presença/permissão dos arquivos
   de runtime/secrets, sem ler o conteúdo.

O stage `base` pode ser executado antes de existir arquivo de parâmetros.

Os stages `network` e `deploy` exigem um arquivo baseado nos exemplos desta
pasta.

## Segurança

O preflight:

- não instala pacotes;
- não altera sysctl;
- não altera interface, IP, gateway ou DNS;
- não altera firewall/pfSense;
- não executa `docker compose up/down`;
- não lê o conteúdo de secrets;
- não ativa Twingate;
- escreve somente o relatório de diagnóstico solicitado.

Os arquivos reais de runtime/secrets devem ficar fora do Git.

## Ordem da fase 1

```text
pfSense pronto
  -> preflight base Ubuntu
  -> rede Ubuntu
  -> preflight network
  -> preparar runtime/segredos
  -> preflight deploy
  -> subir componentes por papel
```

O Wazuh exige `vm.max_map_count >= 262144` na VM interna.

Docker Compose deve ser 2.24.4 ou superior, conforme o contrato de implantação
do projeto.


## Runbook completo

Consulte `RUNBOOK-FASE1.md`.

## Organização dos scripts

Os scripts foram separados por etapa para que a implantação possa ser seguida
como uma sequência de "disquetes": conclua uma pasta antes de avançar para a
próxima.

```text
scripts/implantacao/vms/
├── 00-base/
├── 10-interna/
├── 20-dmz/
├── 30-integracao/
├── 40-bacula/
├── 90-evidencias/
└── lib/
```



## Cartão de topologia

Copie `topologia-fase1.env.example` para `/etc/conectaeduca/vms/topologia.env`
nas duas Ubuntu. Ele é não secreto e concentra os IPs da DMZ, interna e das
interfaces correspondentes do pfSense, além do commit/tag do freeze.

O script `00-base/00-orientar-topologia.sh` usa esse arquivo para identificar a
VM pelo IPv4 atual e imprimir os componentes e o próximo diretório a executar.

O preflight recebe o mesmo arquivo com `--topology`. Nos stages `network` e
`deploy` ele é obrigatório. No stage `deploy`, commit e tag já precisam estar
fixados e o HEAD local deve corresponder exatamente aos dois.

## Modelo mental dos containers

O Docker de cada Ubuntu só cria containers naquela própria VM.

```text
CE-PFSENSE
  containers: nenhum

CE-UBUNTU-DMZ
  Docker local
    -> PHP-FPM
    -> Nginx
    -> WAF / ModSecurity / CRS

CE-UBUNTU-INT
  Docker local
    -> MariaDB
    -> Wazuh
    -> OpenBao
    -> Ferret
```

Dentro da mesma VM, serviços Docker conversam por redes/nomes de serviço do
Compose. Entre VMs, usa-se o IP da VM/porta publicada; nunca o nome de container
de outra VM.

O `00-base/07-despachar-containers-fase1.sh` detecta a máquina pelo IP e só
despacha o stack permitido para aquele papel.

Para a lógica de criação/subida e comunicação dos containers, consulte `FLUXO-CONTAINERS.md`.
