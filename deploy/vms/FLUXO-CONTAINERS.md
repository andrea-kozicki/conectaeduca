# Como os containers sobem na fase 1

O repositório é a fonte das **receitas** de implantação: Dockerfiles, arquivos
Compose, scripts e configurações declarativas. As imagens Docker não ficam no
Git. Quando necessário, o Docker faz pull dos registries ou usa imagens
previamente carregadas pelo handoff (`docker load`).

## Regra principal

O IPv4 da VM identifica **qual host está sendo operado**. Ele não vira o IP
individual de cada container.

```text
CE-PFSENSE
  IPv4 próprio
  Docker: não

CE-UBUNTU-DMZ
  IPv4 próprio
  Docker local
    -> PHP-FPM
    -> Nginx
    -> WAF / ModSecurity / CRS

CE-UBUNTU-INT
  IPv4 próprio
  Docker local
    -> MariaDB
    -> Wazuh Manager
    -> Wazuh Indexer
    -> Wazuh Dashboard
    -> OpenBao
    -> Ferret
```

Dentro da mesma Ubuntu, o Compose cria redes privadas Docker e os serviços
podem se comunicar pelos nomes dos serviços. Entre VMs, usa-se o IPv4 da VM e
a porta publicada. Por exemplo, PHP na DMZ acessa MariaDB pelo IPv4 da interna
na porta 3306; não pelo nome Docker `mariadb` da outra máquina.

## O que `docker compose up -d` faz

Em alto nível:

```text
valida Compose
  -> obtém/constrói imagens necessárias
  -> cria redes e volumes declarados
  -> cria/inicia containers
  -> executa healthchecks
  -> deixa serviços rodando em segundo plano
```

Os scripts de implantação encapsulam os comandos Compose para evitar execução
manual da combinação errada de overlays.

## Despachante da fase 1

Use primeiro o cartão não secreto:

```text
/etc/conectaeduca/vms/topologia.env
```

com três IPv4:

```text
CONECTAEDUCA_PFSENSE_IPV4
CONECTAEDUCA_DMZ_IPV4
CONECTAEDUCA_INTERNA_IPV4
```

O script:

```text
scripts/implantacao/vms/00-base/07-despachar-containers-fase1.sh
```

possui dois modos:

- `--plan`: somente identifica a máquina e mostra quais containers pertencem a
  ela;
- `--apply`: executa o preflight `deploy` e, somente se aprovado, chama o
  orquestrador correspondente àquela Ubuntu.

O modo `--apply` nunca executa containers no pfSense.
