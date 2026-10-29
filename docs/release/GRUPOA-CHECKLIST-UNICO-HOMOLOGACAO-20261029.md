# Grupo A — Checklist único de execução e aceite (29/10/2026)

**Uso:** próxima sessão autorizada EP125/EP126. Não é autorização de mudança; não executar automaticamente.

## Estado offline verificado
- GitHub Actions no commit `7397e260`: 8/8 workflows **success** (GA08 #99, GA09 #93, PA07 #86, Gitleaks #1243, PHPUnit #1324, Integrity #998, Semgrep #1284, Supply Chain #259).
- GA08 socket candidato: redes isoladas, `php.expose: !reset []`, testes offline aprovados em CI anterior.
- PHP base atualizada **somente no GitHub** para `php:8.5.12-fpm-alpine3.24@sha256:4c2818074ec49f6abe46620f3965e0cb75bc3a5f2b417edd1aacaba6f091c40e`, commit `9bf1875`; digest de índice multiarch informado pelo Docker Hub. **Não inferir build/scan/implantação aprovada**.
- Branch vs main: `diverged`, 114 commits à frente e 29 atrás, 72 arquivos na comparação realizada antes do patch PHP. **Não mergear sem reconciliação**.
- PR #200: sem reviews submetidos nem threads inline retornados pela API; isso não significa aprovação. Draft e gate de VM mantidos.
- Issues #201 (PHP), #204 (PA-02), #195 (auditoria), #196 (Bacula) abertas.

## Pré-condições obrigatórias
- [ ] Professor/suporte autorizam janela, escopo e operador; registrar horário e plano de comunicação.
- [ ] Confirmar estado da EP126, Git HEAD das duas VMs, serviços, Compose efetivo, imagens e variáveis **sem imprimir segredos**.
- [ ] Snapshot/backup identificado e restauração testável; rollback aprovado.
- [ ] Validar conflitos/divergência da branch e revisão dos PRs; não confundir CI PASS com merge autorizado.
- [ ] Confirmar certificados ZeroSSL, hostname, CA e DNS.
- [ ] Conferir grupos Twingate e endpoint administrativo privado, negação da rota pública.

## Sequência de homologação
1. **PHP P0:** build da imagem corrigida em ambiente autorizado, validar `php -v`, digest da imagem em execução, dependências, SAST e healthchecks. Caso falhe, não promover.
2. **GA08:** resolver Compose na ordem completa e checar portas, redes, socket e mounts RO/RW; testar WAF→Nginx→PHP, HTTP/TLS, SQL autenticado e ausência de acesso lateral não autorizado.
3. **Twingate:** Connector online, grupos e Resources com menor privilégio; testar acesso permitido e negado por identidade, inclusive insider e usuário sem grupo.
4. **PA-06:** validar persistência do `audit.log`, rotação e ingestão Wazuh de eventos sintéticos; não expor dados reais.
5. **PA-07:** suporte confirma causa do Director/Catalog; verificar Jobs e restauração sintética somente se autorizada.
6. **Pentest B:** executar sete PAs com evidências por origem/destino, timestamps, resultados, hashes e classificação `PASS/FAIL/INCONCLUSIVO`.
7. **Rollback:** ensaio em janela própria, recuperar baseline e comprovar TLS, WAF, PHP, SQL, telemetria e disponibilidade.

## Abortar imediatamente se
- WAF/HTTPS/SQL falharem, acesso lateral indevido aparecer, Connector expuser Resource a grupo errado, telemetria crítica desaparecer, versão PHP vulnerável continuar ativa, ou rollback não for demonstrável.

## Resultado e fechamento
- [ ] Relatório de evidências atualizado, sem dados sensíveis.
- [ ] Issue #201: patch ativo demonstrado, não só Dockerfile.
- [ ] Issue #204: isolamento runtime positivo e negativo demonstrado.
- [ ] Issues #195/#196: persistência/restore comprovados.
- [ ] PRs revisados; merge só após autorização.
- [ ] Grupo A formalmente aceito antes do Grupo B.

**Não declarar a lista operacional zerada antes dos testes e aceites.**
