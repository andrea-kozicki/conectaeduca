# Inventário de componentes do handoff

Este documento define a chamada nominal dos componentes que devem existir no handoff final do ConectaEduca para a EC8.

## DMZ — containers de runtime

| Papel | Origem |
|---|---|
| PHP-FPM | imagem própria `conectaeduca/php-fpm:dmz` |
| Nginx | imagem própria `conectaeduca/nginx:dmz` |
| WAF ModSecurity/OWASP CRS | imagem própria `conectaeduca/waf:dmz` |

O MariaDB não pertence à DMZ final.

## Rede interna — containers de runtime

| Papel | Origem |
|---|---|
| MariaDB | imagem oficial pinada |
| OpenBao | imagem oficial pinada |
| Ferret Scan | imagem oficial pinada |
| Wazuh Manager | imagem oficial pinada |
| Wazuh Indexer | imagem oficial pinada |
| Wazuh Dashboard | imagem oficial pinada |
| PostgreSQL / Bacula Catalog | imagem oficial pinada |
| Bacula Storage | imagem própria |
| Bacula Director | imagem própria |

## Bootstrap

O `wazuh/wazuh-certs-generator` é imagem de preparação de certificados. Não é workload persistente.

## Componentes nativos

O Bacula File Daemon final é instalado nativamente nas duas VMs Ubuntu:

- DMZ;
- rede interna.

O container `filedaemon-lab` permanece apenas como artefato histórico/de laboratório e não entra no handoff operacional.

## Fora do handoff final

- Mailpit;
- Bacula File Daemon containerizado de laboratório;
- Trivy e outros scanners temporários;
- Twingate enquanto o Pentest A não tiver sido executado;
- `.runtime`, `.env` real, credenciais, chaves privadas e material Shamir.

## Critério de aprovação

O freeze não é aprovado apenas pela ausência de componentes proibidos. Ele também exige a presença nominal de todos os componentes esperados nas respectivas VMs.
