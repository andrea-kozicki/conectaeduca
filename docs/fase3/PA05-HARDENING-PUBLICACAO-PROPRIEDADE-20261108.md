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

**Depois:** novo método `atualizarStatusComObservacaoAutorizado`, chamado pelo fluxo normal de empresa/admin, executa `UPDATE inscricoes i INNER JOIN oportunidades o ... WHERE i.id=:id AND i.status <> :status_cancelada`, adicionando `AND o.empresa_id=:empresa_id` para empresa. Admin continua autorizado para todas, sem escopo empresarial indevido. Se `rowCount() > 0`, o serviço considera a atualização bem-sucedida. Caso o MySQL/MariaDB informe zero linhas alteradas, a correção da PR #251 executa **somente um SELECT parametrizado**, reaplicando as guardas por empresa e cancelamento, com igualdade exata dos valores solicitados. Repetições idempotentes autorizadas são aceitas; empresa alheia e inscrição cancelada continuam negadas. A rotina antiga permanece apenas para compatibilidade de possíveis chamadores: **qualquer novo endpoint deverá utilizar a variante autorizada**. O registro de auditoria ainda não distingue uma gravação efetiva de uma repetição idempotente.

## Alterações de código na PR

- `src/Repository/InscricaoRepository.php`
- `src/Service/InscricaoService.php`
- `src/Controller/InscricaoController.php`
- `tests/Unit/Security/Pa05OwnershipPublicationContractTest.php` — contratos estáticos para publicação, propriedade e idempotência.
- `tests/Integration/Security/pa05_mysql_regression.php` — 15 cenários no MariaDB descartável do GitHub Actions (apenas dados sintéticos).
- `.github/workflows/pa05-mariadb-regression.yml` — PHP, PHPUnit, MariaDB e Semgrep em propostas à branch da #229 e à `main`.

Não alteramos schemas, contas, MFA, permissões do Twingate, dados da base, texto de segredos ou variáveis do ambiente.

## Operação e evidência histórica — não há deploy atual aprovado

A DMZ incorpora o `src/` na imagem PHP, portanto editar o checkout Git **não equivale** a implantar a correção no contêiner. A proposta de cutover CE-PA05-DEP02, preparada em 08/11/2026, era fixada em um commit de código anterior à idempotência (#251), hashes de três arquivos PHP e um Image ID daquela data. **Não é seguro reutilizá-la com a árvore atual.**

O script, runbook e workflow antigos foram **retirados dos caminhos operacionais da proposta** e preservados como evidência no histórico imutável do Git. Consulte [PA05-DEP02-HISTORICO-NAO-EXECUTAR.md](PA05-DEP02-HISTORICO-NAO-EXECUTAR.md) antes de qualquer planejamento de implantação.

**Status da revisão:** a correção de código e os testes estão no GitHub; não se alega instalação nem aceite dinâmico na EP125. O runtime presente na VM e a topologia Compose devem ser novamente medidos por uma janela autorizada. Um próximo deploy exigirá change ID novo, baseline atual, artefatos reproduzíveis e verificação de rollback, sem comandos destrutivos ou segredos em logs.

## Critério de aceite — mínimo necessário

1. CI GitHub PHPUnit, SAST, integrity e Gitleaks PASS (sem novo pentest);
2. Rebuild rastreável e deploy somente do PHP no Compose efetivo, com rollback de imagem e snapshot/backup;
3. Uma verificação funcional dirigida: candidatura por ID de oportunidade fictícia **não publicada** deve devolver 404 sem nova inscrição; candidatura normal em oportunidade fictícia publicada segue aceita;
4. Uma confirmação curta de negativa cruzada entre as duas identidades fictícias do mesmo papel (já existentes, conforme retificação de 26/10). Não repetir o RBAC vertical S05-DYN14;
5. Monitor de saúde PHP/WAF não regrediu. **Não alegar PA-05 integral PASS** antes da evidência dinâmica.

O controle por autorização horizontal é independente da integração OpenBao/AppRole da PR #228, atualmente bloqueada por ausência legítima de token administrativo.
