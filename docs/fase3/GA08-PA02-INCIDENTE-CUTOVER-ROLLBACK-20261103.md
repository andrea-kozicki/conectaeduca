# ConectaEduca — GA-08 / PA-02: incidente e rollback real

**Consolidado em 04/11/2026** a partir das saídas informadas pela responsável na EP125, da [PR #217](https://github.com/andrea-kozicki/conectaeduca/pull/217) e dos registros do Trello.

**Estado atual:** primeiro cutover **FALHOU** na saúde do PHP-FPM; rollback Docker posterior **PASS** (PHP, Nginx e WAF saudáveis); recuperação funcional HTTPS, SQL, MFA e auditoria **AINDA NÃO COMPROVADA**; PA-02 **ABERTO**. Este documento não autoriza novo cutover.

## Escopo e fatos comprovados

O objetivo da GA-08 é eliminar o bypass do WAF via Nginx TCP/8080 na bridge Docker, utilizando sockets Unix WAF→Nginx (HTTP) e Nginx→PHP-FPM (FastCGI), mantendo o portal público HTTPS/443. A topologia baseline efetiva usa nove arquivos Compose para WAF/Nginx e dez para PHP, incluindo overlay local de auditoria não rastreado.

O suporte informou snapshot da EP125 com referência **ubuntu.33**, e a operadora atestou cobertura/restaurabilidade no gate. Esta referência não deve ser apresentada como UUID inequívoco do hipervisor. O snapshot **não foi restaurado**: houve rollback Docker.

| Etapa | Saída informada | Alcance |
| --- | --- | --- |
| GA08.18D | Baseline 9 e 10 Compose FAIL variável obrigatória; 10 sem interpolação PASS | Problema com ambiente de interpolação, não atribuído ao candidato |
| GA08.18E | Arquivos .env ausentes em raiz e DMZ | Não criar placeholders ou copiar segredos |
| GA08.18F | Referências runtime 13/13; preflight configuração/imagens PASS | Ambiente temporário em memória |
| GA08.18G | Contexto privado 18/18; SHA256 a3f9dc0de86da3136abae2163b66e6efc14c01df00bc304c1e21eb604f9c5d36 | Referências protegidas, sem conteúdo de segredos |
| GA08.18H | Atestação 9/9; approval.json privado 0600 | Aprovação operacional humana registrada |
| GA08.19 | Gate FAIL_CLOSED: servico_nao_healthy_php; execução RC3 | PHP foi recriado com candidato, mas não chegou a HEALTHY; sequência não avançou ao Nginx/WAF |
| GA08.19R | Rollback PHP/Nginx/WAF HEALTHY; Docker_3_SERVICOS_HEALTHY; execução PASS | **Rollback real bem-sucedido quanto à saúde dos contêineres** |
| GA08.19S | Três serviços running/healthy; php-fpm -t PASS; HTTPS em 127.0.0.1:18443 HTTP000/curl7 | Recuperação de saúde/sintaxe comprovada; teste HTTPS mirou porta de laboratório |
| GA08.19T | Apenas rodapé: configurações e contêineres não modificados; concluída | Sem as linhas HTTPS_BIND e ROTA/HTTP/CURL_RC, **não comprova HTTP funcional** |

## Interpretação do teste HTTPS

O Compose de produção carrega deploy/dmz/compose.host.yml, cujo ports: !override substitui o bind 127.0.0.1:18443 do overlay TLS pelo IP/porta configurados para a EP125 (443 padrão). A recusa de conexão na porta 18443 **não equivale a prova de indisponibilidade do WAF**. Deve-se consultar o binding real do Docker e testar esse destino. Um teste curl com --insecure não valida confiança na CA.

## PHP-FPM: causa ainda indeterminada

A imagem executa como www-data e tem healthcheck php-fpm -t. O candidato substitui o listener TCP/9000 pelo socket Unix /run/conectaeduca-fpm/php-fpm.sock com montagem gravável esperada para UID/GID 82. O erro de saúde **não comprova**, isoladamente, erro no listener, permissões, montagem, sintaxe ou healthcheck.

Na PR #217 foi preparado o teste de diagnóstico com scripts/ga08-canario-fpm-offline-ep125.py e tests/python/test_ga08_fpm_canary_offline.py. O canário temporário é **sem rede, sem secrets, sem Compose e com filesystem somente leitura**; faz teste de sintaxe, socket e saúde, removendo o contêiner isolado. Ainda **não executado na EP125**. Seu tmpfs isolado não substitui teste das permissões do bind real da VM. CI representa somente testes offline.

## Continuidade — uma só sequência, sem repetir inventários

1. Recuperar as linhas HTTPS_BIND/ROTA HTTP/CURL_RC da execução GA08.19T; se indisponíveis, fazer smoke mínimo pelo binding real do WAF. Confirmar HTTPS funcional e TLS confiável em teste separado.
2. Quando houver acesso à EP125, executar o canário isolado GA08.20 e documentar estado, saúde, socket e categoria sanitizada de erro. Correlacionar com mounts e credenciais por metadados, sem leitura de segredo.
3. Corrigir causa **demonstrada** na PR #217; validar CI e ensaio isolado. Não modificar a aplicação ou repetir cutover com base apenas em hipóteses.
4. Próximo cutover requer **novo change ID**: o GA08-20261103-EP125 já contém manifesto de mudança e rollback e não deve ser reutilizado. Reconfirmar preflight, contexto, snapshot, autorização, janela e rollback.
5. Só depois de corte bem-sucedido executar E2E HTTPS com CA, benigno 200, CRS 403, PHP→SQL EP126, login/MFA/RBAC, telemetria/audit.log e negações do PA-02 (host e peer sem rota TCP direta ao Nginx). PA-02 só pode ser encerrado após esses testes.

## Custódia e rastreabilidade

O conteúdo privado da GA08.18G/18H e manifesto ficam sob o diretório local ~/ConectaEduca_Fase2_Evidencias/EP125/GA08/GA08-20261103-EP125. **Não enviar** runtime-refs.json, approval.json, manifest.json bruto, .env, certificados, chaves ou logs não sanitizados para GitHub/Trello. A evidência pública é o estado dos testes e os hashes já divulgados.

**Síntese final em 04/11:** preflight PASS; cutover FAIL-CLOSED no PHP; rollback Docker real PASS 3/3 HEALTHY; aplicação E2E indeterminada; PA-02 aberto.
