# Imagens validadas — ConectaEduca

Data: 2026-08-19T16:51:15-03:00

Plataforma-alvo do checkpoint: `linux/amd64`

| Componente | Referência |
|---|---|
| Nginx base | `nginx:stable-alpine@sha256:97d490c12ba55b4946b01546d1c3ed324e8d41ab1c9fcb2a616aa470620e5b46` |
| PHP-FPM base | `php:8.5-fpm-bookworm@sha256:7b1deadd1d73c72d2eb952ebb494cd3e902d7b6ae4e4b3cd1113a1041b530c2c` |
| Composer base | `composer:2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040` |
| WAF / CRS | `owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad` |
| MariaDB | `mariadb:12.3.2-ubi10@sha256:e45834e9fd4a51f92f746fcfd549ff507d55cf58e3c34b8c2fd4af3439fc506d` |

Nginx, PHP-FPM, Composer e WAF foram fixados pelos digests já observados nos
checkpoints anteriores do projeto.

MariaDB: origem do digest nesta fixação: **cache local**.

A imagem MariaDB e todo o conjunto serão submetidos novamente ao checkpoint
completo de integração antes de qualquer commit.
