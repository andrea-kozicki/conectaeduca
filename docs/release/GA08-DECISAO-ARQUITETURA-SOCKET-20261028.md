# GA-08 — Decisão técnica após evidência de bypass interno (28/10/2026)

## Evidências
- WAF, Nginx e PHP saudáveis; HTTPS pelo WAF HTTP 200; PHP → banco TCP OK.
- Nginx não publica portas no host; teste do host para 8088 falhou.
- De dentro do PHP, conexão direta com Nginx:8080 estabelecida; HTTP 404 para /healthz. Isso demonstra alcance HTTP sem passar pelo WAF, **não** exploração de endpoint.
- Nginx atual usa `fastcgi_pass php:9000` em múltiplas locations; PHP-FPM usa `listen = 9000`.
- Nenhum volume compartilhado Nginx/PHP observado.

## Decisão
**Não implantar** o overlay `compose.ga08-segmentacao.candidate.yml` como correção completa: PHP e Nginx ainda dividem `app_backend`, permitindo acesso direto ao HTTP Nginx.

## Arquitetura candidata — ainda não aplicada
1. Rede `waf_backend`: somente WAF + Nginx.
2. PHP fora de qualquer rede compartilhada com Nginx. PHP mantém uma rede de saída própria para alcançar banco na EP126; verificar rota e política.
3. FastCGI por socket Unix em volume nomeado compartilhado apenas entre PHP e Nginx (não usar diretórios de segredos ou logs existentes).
4. Ajustar `fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock;` em todas as locations; configurar `listen` do PHP-FPM no mesmo caminho.
5. Permissões: PHP executa como UID/GID 82, Nginx como UID/GID 101. Definir grupo compartilhado e `listen.owner`, `listen.group`, `listen.mode=0660`; validar escrita do socket com `read_only: true` e volume próprio. O volume não deve ser acessível por outros contêineres.
6. Atenção: Docker Compose `depends_on`/healthchecks, comportamento de volume nomeado, `read_only`, rede de saída PHP e política de firewall devem ser testados antes do deploy.

## Critérios de aceite
- `docker compose config` válido com os mesmos arquivos/variáveis de produção, sem expor segredos.
- Nginx → PHP via socket responde corretamente; WAF HTTPS retorna 200.
- PHP → banco permanece funcional.
- PHP → Nginx:8080 por rede **não conecta**; Nginx e PHP sem redes compartilhadas.
- Nginx e PHP não publicam portas do host.
- Rollback testável para configuração e imagens anteriores, com manutenção aprovada; não executar `down -v`.
- Registrar evidências e decisão no `diario.md` da EP125.

## Situação
Candidato de desenho; sem deploy. Próxima etapa: implementar alterações coordenadas em branch/PR, validar estaticamente e em ambiente isolado, depois preparar runbook de aplicação e rollback.
