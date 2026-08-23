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
scripts/implantacao/vms/00-preflight-ubuntu.sh
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
