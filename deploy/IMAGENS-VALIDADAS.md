# Imagens validadas — ConectaEduca

**Estado documental:** baseline Git pós-hardening de 04/09/2026.

**Plataforma-alvo:** `linux/amd64`.

Este inventário distingue a referência declarativa presente na `main` do estado observado em runtimes de VM. Uma versão executada fora do Git não é promovida automaticamente a baseline.

## Referências externas fixadas na `main`

| Componente | Referência atual |
|---|---|
| Nginx base | `nginx:stable-alpine@sha256:dc5069ad14f19660b141b21236140b91656bf89bbc3e2417c70ae650cd66104c` |
| PHP-FPM base | `php:8.5.9-fpm-alpine3.24@sha256:9dc81f4086ea5402227a6bcc489b04b4baba12394624d9621faa92ed812fb8ee` |
| Composer base | `composer:2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040` |
| WAF / OWASP CRS base | `owasp/modsecurity-crs:4.25.1-nginx-lts@sha256:60af5abe3175856b8945d8827ab3f52e3906d66ebbb2c8617f45a771b38facad` |
| MariaDB | `mariadb:12.3.2-ubi10@sha256:e45834e9fd4a51f92f746fcfd549ff507d55cf58e3c34b8c2fd4af3439fc506d` |
| Wazuh Manager | `wazuh/wazuh-manager:4.14.7@sha256:8665c9807a5765253c79e4b072a1b7462c997bd69be949118a8d82ce44dd33e9` |
| Wazuh Indexer | `wazuh/wazuh-indexer:4.14.7@sha256:66b7640cce54f5f20a65e8320601b4570a1306d9f9b334d30bcaa324720a517c` |
| Wazuh Dashboard | `wazuh/wazuh-dashboard:4.14.7@sha256:eeff857a664b3c09d3df4407b8749a351f321e4f366ca60ea1dffaa76f2146a7` |
| Wazuh Certs Generator | `wazuh/wazuh-certs-generator:0.0.4@sha256:369b4d58509aab074b188596870c81584f7120e653d9ef83c591f0f785dcf325` |
| OpenBao | `openbao/openbao:2.6.1@sha256:5b2486ab0fb90bbc788cc345b0a08616dfb375873ee8be5df3a2fd4d378a67e0` |
| Ferret Scan DLP | `public.ecr.aws/awslabs/ferret-scan:2.2.1@sha256:898951c5d81d249858ce400bf2c727f028ebe27e7c89e2a23448e483897f0f21` |

## Imagens construídas pelo projeto

A DMZ constrói:

- `conectaeduca/php-fpm:dmz`;
- `conectaeduca/nginx:dmz`;
- `conectaeduca/waf:dmz`.

A referência upstream do WAF é base de build; a workload final usada pelo projeto é a imagem própria construída a partir dela.

## Evolução e resultado dos hardenings pós-VMs

| Componente | Antes | Evolução | Resultado esperado/validado no código |
|---|---|---|---|
| PHP-FPM | base Bookworm anterior | PHP 8.5.9 Alpine 3.24; remoção de build deps; permissões explícitas | imagem menor e runtime com superfície reduzida |
| PHP-FPM runtime | writable por padrão | `read_only`, `cap_drop=ALL`, `pids_limit=128`, tmpfs delimitados | escrita restrita somente às superfícies necessárias |
| Nginx | digest anterior | novo digest stable-alpine + permissões explícitas nos artefatos públicos | atualização da base sem depender do umask do checkout |
| Nginx runtime | hardening incompleto | usuário `101:101`, `read_only`, `cap_drop=ALL`, `pids_limit=128`, tmpfs de cache/run | redução de privilégio e persistência |
| WAF | imagem upstream usada diretamente como referência conceitual | build próprio `conectaeduca/waf:dmz` sobre CRS fixado | atualização controlada da base e separação entre base e imagem do projeto |

Os novos hardenings foram integrados por PRs próprios. A reconciliação com runtimes já implantados deve ocorrer por novo freeze/checkpoint, e não por alteração manual fora do fluxo Git.

## Divergência conhecida — Ferret

A `main` permanece declarativamente em **Ferret 2.2.1** e os contratos do sanitizador ainda documentam o formatter JSON legado dessa versão.

Foi observado runtime 2.4.3 na VM interna durante a auditoria operacional. Isso deve ser tratado como **drift a reconciliar**, não como atualização documental automática.

Para promover 2.4.3 à baseline é necessário registrar, no mesmo PR:

1. imagem e digest;
2. compatibilidade do formatter JSON;
3. resultado do sanitizador;
4. checkpoint DLP;
5. integração com Wazuh;
6. atualização de `compose.yml`, README e contratos.

## Critério de validade

Uma imagem só entra como baseline operacional quando:

- versão/digest estão no Git;
- build/pull é reproduzível;
- plataforma é a esperada;
- serviço chega ao estado previsto;
- scanner/checkpoint correspondente foi executado;
- qualquer finding relevante foi corrigido ou triado;
- documentação e Compose apontam para a mesma referência.
