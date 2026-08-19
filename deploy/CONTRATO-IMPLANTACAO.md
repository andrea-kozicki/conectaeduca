# Contrato de implantação dos containers — ConectaEduca

Este documento separa duas responsabilidades:

1. **containers e Compose**: entregues pelo repositório, reproduzíveis e testados;
2. **infraestrutura das VMs**: configurada posteriormente pela equipe (endereçamento,
   pfSense, DNS, certificados reais, firewall do host, rotas e políticas operacionais).

O objetivo é evitar que uma decisão de laboratório fique embutida nas imagens e
cause retrabalho quando os containers forem levados às duas VMs Ubuntu.

## Escopo atualmente pronto

### VM DMZ

Componentes já validados em conjunto:

- WAF ModSecurity + OWASP CRS;
- terminação TLS no WAF;
- Nginx interno;
- PHP-FPM;
- secrets da aplicação separados dos secrets TLS;
- política CRS PL2;
- healthchecks;
- aplicação real, CSRF, login e pré-autenticação MFA.

Arquivos principais:

```text
deploy/dmz/compose.yml
deploy/dmz/compose.database.yml
deploy/dmz/compose.app-secrets.yml
deploy/dmz/compose.waf.yml
deploy/dmz/compose.waf-tls.yml
deploy/dmz/compose.waf-policy.yml
deploy/dmz/compose.host.yml
```

`compose.host.yml` é o adaptador da VM. Ele substitui bindings de laboratório e
faz `DB_HOST`/`DB_PORT` apontarem para um endpoint TCP real.

### VM interna

O MariaDB versionado usa:

```text
deploy/interna/mariadb/compose.yml
deploy/interna/mariadb/compose.host.yml
```

`compose.host.yml` publica o MariaDB somente no endereço configurado pela equipe.
A regra de firewall/pfSense deve permitir a origem estritamente necessária.

O Wazuh permanece em seu próprio bloco `deploy/interna/wazuh/`, já validado em
checkpoint próprio. A integração operacional de logs com o WAF será tratada em
etapa separada.

## Contrato de software do host

Para os Compose atuais:

- Docker Engine em host Linux suportado;
- Docker Compose **2.24.4 ou superior**;
- plugin `docker compose`, não o binário legado como requisito do projeto;
- arquitetura alvo declarada antes do deploy;
- acesso às imagens/base images ou imagens previamente distribuídas;
- diretórios persistentes com espaço suficiente para os serviços de estado.

O mínimo de Compose decorre do uso de `!reset` e `!override` nos overlays.

## Arquitetura alvo

```text
Internet
   |
pfSense
   |
   +------------------ VM DMZ ------------------+
   |                                             |
   |  WAF/TLS -> Nginx -> PHP-FPM               |
   |                         |                   |
   +-------------------------|-------------------+
                             |
                       TCP DB_HOST:DB_PORT
                             |
   +------------------ VM interna --------------+
   |                                             |
   |  MariaDB                                    |
   |  Wazuh (bloco independente)                 |
   |  futuros Bacula / Twingate                  |
   |                                             |
   +---------------------------------------------+
```

Não existe rede Docker atravessando as duas VMs. A integração entre elas é TCP
normal roteado pela infraestrutura.

## Variáveis não secretas de implantação

A equipe deverá definir, conforme o endereçamento real:

```text
CONECTAEDUCA_WAF_BIND_ADDRESS
CONECTAEDUCA_HTTP_PORT
CONECTAEDUCA_HTTPS_PORT

CONECTAEDUCA_DB_HOST
CONECTAEDUCA_DB_BIND_ADDRESS
CONECTAEDUCA_DB_PORT
```

Exemplo conceitual, sem prescrever IPs:

```text
VM DMZ:
  CONECTAEDUCA_WAF_BIND_ADDRESS=<IP_DA_INTERFACE_DMZ>
  CONECTAEDUCA_HTTP_PORT=80
  CONECTAEDUCA_HTTPS_PORT=443
  CONECTAEDUCA_DB_HOST=<IP_OU_FQDN_DA_VM_INTERNA>
  CONECTAEDUCA_DB_PORT=3306

VM interna:
  CONECTAEDUCA_DB_BIND_ADDRESS=<IP_DA_INTERFACE_INTERNA>
  CONECTAEDUCA_DB_PORT=3306
```

## Secrets exigidos

Os valores reais não pertencem ao Git.

DMZ:

```text
conectaeduca_db_password
conectaeduca_private_key
conectaeduca_public_key
waf_tls_cert
waf_tls_key
```

VM interna / MariaDB:

```text
mariadb_root_password
conectaeduca_db_password
```

A equipe poderá escolher o mecanismo de provisionamento dos arquivos na VM,
desde que os caminhos entregues ao Compose sejam legíveis somente por quem
necessita deles.

## Regras de compatibilidade

Um container só é considerado pronto para handoff quando:

- o Compose resultante é válido;
- a imagem constrói/puxa na arquitetura alvo;
- o serviço chega a `healthy`;
- secrets entram em runtime e não na imagem;
- armazenamento persistente é explícito quando o serviço tem estado;
- não há `privileged: true`, `network_mode: host` nem Docker socket sem
  justificativa documentada;
- endereços de laboratório não são necessários para operação;
- dependências entre VMs usam hostname/IP e porta configuráveis;
- nenhuma rede Docker é usada como mecanismo de comunicação entre hosts;
- os bindings de host são configuráveis;
- o teste de integração continua passando.

## Uso posterior nas VMs

Este arquivo não define IPs, regras do pfSense ou certificados de produção. A
equipe deverá configurar esses elementos depois que as VMs estiverem
disponíveis.

Antes do deploy real, execute o checkpoint em modo de host:

```bash
CHECK_MODE=target \
TARGET_PLATFORM=linux/amd64 \
bash scripts/evidencias/checkpoint_portabilidade_containers.sh
```

O modo `target` verifica o host em que o comando está sendo executado, mas não
altera firewall, rede, Docker ou arquivos do sistema.
