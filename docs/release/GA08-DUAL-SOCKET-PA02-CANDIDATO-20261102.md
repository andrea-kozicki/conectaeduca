# GA-08.8 — PA-02: segundo socket Unix HTTP WAF→Nginx (02/11/2026)

**Estado:** candidato source-only na PR #200 (DRAFT), **não implantado** na EP125. A issue #204 permanece aberta.

## Evidência direta EP125 (GA-08.7/8, somente leitura)

- WAF `nginx -T`: um `proxy_pass` efetivo em `/etc/nginx/includes/proxy_backend.conf`.
- Os dois templates `/etc/nginx/templates/includes/proxy_backend.conf.template` e `/usr/local/bootstrap/nginx/templates/includes/proxy_backend.conf.template` são idênticos, fazem referência à variável `${BACKEND}` e possuem uma diretiva `proxy_pass` cada.
- Proxy atual é HTTP/TCP; Nginx possui somente listener TCP 8080; healthcheck do Nginx depende de TCP.
- O bootstrap restaura `/etc/nginx` da árvore `/usr/local/bootstrap/nginx` durante a inicialização. **Não editar configuração efêmera gerada.**
- **Ainda é necessário provar** que a variável `${BACKEND}` ocupa o argumento inteiro de `proxy_pass`, sem sufixo de URI ou parâmetros que invalidem o candidato.

## Proposta de dois sockets

1. **Socket A (HTTP):** WAF UID101 → Nginx UID101 por `/run/conectaeduca-http/nginx.sock`; `BACKEND` candidato `http://unix:/run/conectaeduca-http/nginx.sock:`, `listen unix:/run/conectaeduca-http/nginx.sock;`. WAF monta pasta somente leitura, Nginx monta escrita; não modificar ModSecurity/CRS.
2. **Socket B (FastCGI):** Nginx UID101+grupo82 → PHP-FPM UID82 por `/run/conectaeduca-fpm/php-fpm.sock`, conforme o candidato anterior (já ensaiado isoladamente), conservando todos os seis `fastcgi_pass`.
3. **Redes:** WAF e Nginx em `waf_backend`; PHP em `php_egress`. Sem listener TCP no Nginx, host/peers não deveriam alcançar HTTP pela bridge. Root/Docker admin permanece um risco privilegiado residual.

## Artefatos adicionados à PR #200

| Arquivo | Objetivo |
|---|---|
| `deploy/dmz/ga08/app-http.dual-socket.candidate.conf` | Cópia do candidato Socket B com alteração **exclusiva** de `listen 8080` para `listen unix:`. |
| `deploy/dmz/compose.ga08-dual-socket.candidate.yml` | Overlay final, aplicado **depois** de `compose.ga08-socket.candidate.yml`, para BACKEND, volumes, remoção das portas e healthcheck. |
| `tests/python/test_ga08_dual_socket_candidate_offline.py` | Contratos estáticos source-only, sem Docker/VM. |
| `.github/workflows/ga08-zt-offline.yml` | Novo passo de CI para testar o candidato. |

O Compose mescla volumes pelo `target`: o mount do Nginx em `/etc/nginx/conf.d/default.conf` deve ficar com a origem do último overlay. **Verificar a mesclagem real** com os overlays efetivos da EP125, inclusive `compose.audit-persistent.yml` local não rastreado; preservar este arquivo sem alterações.

O diretório host dedicado ao socket A deverá ser provisionado somente com autorização, dono 101:101 e modo 0700. Não reutilizar a pasta Socket B (UID82), nem pastas de segredos/logs. Validar em runtime que o WAF conecta ao socket em mount read-only e que o socket não fica obsoleto após restart.

## Gates pendentes antes de implantação

- **T1 Template WAF:** confirmar argumento inteiro de `proxy_pass`; testar interpolação, `nginx -t` e preservação de `MODSEC_RULE_ENGINE=On`/CRS.
- **T2 Compose:** resolver a configuração na ordem real com variáveis sanitizadas; confirmar sockets, montagens RO/RW, redes, identidades, absence de TCP/portas Nginx e WAF HTTPS preservado.
- **T3 Ensaio isolado:** imagens reais sem tráfego de produção, WAF→socket HTTP→Nginx→socket FastCGI→PHP e teste negativo de origem não autorizada.
- **T4 Health:** Nginx `nginx -t && test -S` substitui wget/TCP, **mas não comprova E2E HTTP**; exigir testes funcionais pelo WAF. `/healthz` do WAF pode não passar pelo backend.
- **T5 Regressões:** login/MFA, rotas, HTTPS/TLS/CA, WAF 403 com payload autorizado, logs/Wazuh, PHP→DB EP126.
- **T6 Negação PA-02:** host EP125→bridge Nginx TCP8080 negado, PHP→Nginx negado, vizinho Docker não autorizado→upstream negado, WAF→app permitido.
- **T7 Rollback:** autorização, snapshots/digests, backup imutável, plano de recriação da configuração, teste de reversão; nunca `down -v`. Script de rollback existente é preflight, **não rollback funcional**.
- **T8 Limites:** administradores root/Docker ainda podem manipular mounts/contêineres; não alegar isolamento absoluto.

**Decisão:** não fazer merge, deploy ou mudança pfSense. PA-02 **ABERTO** até implantação autorizada, testes de negação e integração, evidências e rollback.
