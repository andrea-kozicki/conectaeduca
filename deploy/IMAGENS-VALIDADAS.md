# Imagens validadas — ConectaEduca

Data de consolidação: 2026-08-21

Plataforma-alvo do baseline: `linux/amd64`

## Referências externas fixadas

| Componente | Referência validada |
|---|---|
| Nginx base | `nginx:stable-alpine@sha256:97d490c12ba55b4946b01546d1c3ed324e8d41ab1c9fcb2a616aa470620e5b46` |
| PHP-FPM base | `php:8.5-fpm-bookworm@sha256:7b1deadd1d73c72d2eb952ebb494cd3e902d7b6ae4e4b3cd1113a1041b530c2c` |
| Composer base | `composer:2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040` |
| WAF / OWASP CRS | `owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad` |
| MariaDB | `mariadb:12.3.2-ubi10@sha256:e45834e9fd4a51f92f746fcfd549ff507d55cf58e3c34b8c2fd4af3439fc506d` |
| Wazuh Manager | `wazuh/wazuh-manager:4.14.7@sha256:8665c9807a5765253c79e4b072a1b7462c997bd69be949118a8d82ce44dd33e9` |
| Wazuh Indexer | `wazuh/wazuh-indexer:4.14.7@sha256:66b7640cce54f5f20a65e8320601b4570a1306d9f9b334d30bcaa324720a517c` |
| Wazuh Dashboard | `wazuh/wazuh-dashboard:4.14.7@sha256:eeff857a664b3c09d3df4407b8749a351f321e4f366ca60ea1dffaa76f2146a7` |
| Wazuh Certs Generator | `wazuh/wazuh-certs-generator:0.0.4@sha256:369b4d58509aab074b188596870c81584f7120e653d9ef83c591f0f785dcf325` |
| OpenBao | `openbao/openbao:2.6.1@sha256:5b2486ab0fb90bbc788cc345b0a08616dfb375873ee8be5df3a2fd4d378a67e0` |
| Ferret Scan DLP | `public.ecr.aws/awslabs/ferret-scan:2.2.1@sha256:898951c5d81d249858ce400bf2c727f028ebe27e7c89e2a23448e483897f0f21` |

## Imagens construídas pelo projeto

A DMZ constrói localmente as tags `conectaeduca/php-fpm:dmz` e `conectaeduca/nginx:dmz` a partir das bases fixadas acima. O checkpoint completo recompila essas imagens e valida a plataforma e o funcionamento do conjunto.

## Critério

Uma referência entra neste inventário somente depois de ter sido validada no baseline do projeto. Tags históricas de desenvolvimento não fazem parte do inventário operacional. O checkpoint geral verifica pinning, plataforma e presença local; checkpoints específicos exercitam os serviços e suas propriedades de segurança.
