# PA-05 — Hardening de publicação e propriedade horizontal (08/11/2026)

**Responsável:** Andréa Kozicki · **Alvo do código:** PHP na DMZ/EP125 · **Fase:** patch no GitHub, implantação EP125 sujeita a change control. **Sem alteração OpenBao, EP126, pfSense ou Twingate.**

## Achado e correção concreta

A primeira campanha S05 comprovou RBAC vertical no recorte (controle 200, quatro negativas 403) e os filtros SQL de propriedade para inscrição/favorito. O PA-05 foi encerrado **administrativamente com cobertura parcial**, não como vulnerabilidade explorada. O cartão PA-05 de 26/10 corrigiu uma premissa: **qualquer perfil autenticado pode candidatar-se**. Não devemos implantar `requireRole('usuario')`.

A revisão desta tarefa identificou duas superfícies suscetíveis a contorno de autorização, que serão endurecidas sem inventar regras de papel:

### 1. Criação de candidatura a oportunidade não publicada

**Antes:** `InscricaoRepository::criar` executava `INSERT ... VALUES (:usuario_id, :oportunidade_id, ...)` após verificar apenas duplicidade; não verificava `status` de oportunidade. A UI `OportunidadeController::detalhe` oculta oportunidades não publicadas, mas o handler de candidaturas não as restringia na gravação. **É lacuna demonstrável no código, não exploração HTTP comprovada.**

**Depois:** `INSERT INTO inscricoes ... SELECT ... FROM oportunidades o WHERE o.id=:oportunidade_id AND o.status=:status_publicada`, verificando `rowCount()===1` antes de retornar o ID. Garante verificação de publicação na própria sentença SQL (não uma consulta anterior sujeita a TOCTOU). Se não estiver publicada/inexistente, `DomainException` capturada pelo `InscricaoController::criar`, que devolve JSON genérico `404`; nenhum detalhe do rascunho é revelado.

### 2. Atualização de candidatura por empresa

**Antes:** `InscricaoService::atualizarStatusPorEmpresaOuAdmin` buscava a inscrição escopada à empresa, mas gravava com `InscricaoRepository::atualizarStatusComObservacao($id,...)`, cujo `UPDATE` filtra apenas por ID. Separação SELECT→UPDATE deixa janela de mudança de propriedade/status entre autorização e escrita.

**Depois:** novo método `atualizarStatusComObservacaoAutorizado`, chamado pelo fluxo normal de empresa/admin, executa `UPDATE inscricoes i INNER JOIN oportunidades o ... WHERE i.id=:id AND i.status <> :status_cancelada`, adicionando `AND o.empresa_id=:empresa_id` para empresa. Admin continua autorizado para todas, sem escopo empresarial indevido. Se `rowCount()=0`, o serviço falha fechado antes de registrar auditoria de sucesso. A rotina antiga permanece para compatibilidade de outros chamadores; **se algum outro endpoint a utilizar futuramente, deverá ser migrado ao método autorizado**. Atualizações idempotentes com zero linhas afetadas podem retornar erro genérico, uma troca conservadora por fail-closed a ser observada.

## Alterações de código na PR

- `src/Repository/InscricaoRepository.php`
- `src/Service/InscricaoService.php`
- `src/Controller/InscricaoController.php`
- `tests/Unit/Security/Pa05OwnershipPublicationContractTest.php` — quatro verificações estáticas pontuais, sem MariaDB, sem fixtures, sem usuários reais.

Não alteramos schemas, contas, MFA, permissões do Twingate, dados da base, texto de segredos ou variáveis do ambiente.

## Implementação operacional real

A DMZ PHP é embutida na imagem pelo Dockerfile `deploy/dmz/php/Dockerfile` (`COPY src/`): **alterar somente os arquivos em `/opt/conectaeduca/src` no host não significa que o PHP em execução recebeu a correção**, pois não há prova de bind do `src` no container. Necessário construir imagem candidata imutável com os 3 blobs aprovados a partir do `main@04f88d27`, sem destruir imagem baseline, e substituir **somente** serviço PHP respeitando todos os overlays efetivos e variáveis obrigatórias. Antes do cutover, recuperar lista exata de arquivos Compose do container em execução, projeto, Image ID e digest/imagem de rollback; **não improvisar** comando `docker compose` só com arquivo base. O projeto já teve GA-08 cutover fail-closed por variável obrigatória ausente, portanto não repetir a falha.

**Status atual:** patch implementado no GitHub, **ainda não implantado nem executado na EP125**. PR DRAFT até janela e prova mínima. A `main` e checkouts EP125/EP126 permanecem em `04f88d27` e as modificações controladas PA-07 na EP126 são preservadas. Nenhum `git reset --hard`, `git clean`, `docker compose down`, `docker prune` ou alteração em OpenBao.

## Critério de aceite — mínimo necessário

1. CI GitHub PHPUnit, SAST, integrity e Gitleaks PASS (sem novo pentest);
2. Rebuild rastreável e deploy somente do PHP no Compose efetivo, com rollback de imagem e snapshot/backup;
3. Uma verificação funcional dirigida: candidatura por ID de oportunidade fictícia **não publicada** deve devolver 404 sem nova inscrição; candidatura normal em oportunidade fictícia publicada segue aceita;
4. Uma confirmação curta de negativa cruzada entre as duas identidades fictícias do mesmo papel (já existentes, conforme retificação de 26/10). Não repetir o RBAC vertical S05-DYN14;
5. Monitor de saúde PHP/WAF não regrediu. **Não alegar PA-05 integral PASS** antes da evidência dinâmica.

O controle por autorização horizontal é independente da integração OpenBao/AppRole da PR #228, atualmente bloqueada por ausência legítima de token administrativo.
