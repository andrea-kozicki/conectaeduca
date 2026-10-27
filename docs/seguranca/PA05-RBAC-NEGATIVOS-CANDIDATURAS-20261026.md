# PA-05 / Pentest B — duas contas com o mesmo papel e testes horizontais de propriedade (26/10/2026)

**Correção documental de premissa, solicitada pela responsável:** não existe regra de negócio que restrinja as candidaturas ao papel `usuario`. A aplicação mantém `Authorization::requireAuth()` em `InscricaoController::minhas/criar/cancelar`, intencionalmente. A responsável preparou **duas contas distintas com o mesmo papel** para o Pentest B. Não substituir essa regra por `requireRole('usuario')`.

## 1. Correção da análise anterior e PR #209

A versão inicial do PR #209 inferiu equivocadamente uma exigência de candidato exclusivo por papel e propôs `requireRole('usuario')` nos três handlers. Essa inferência **não correspondia à regra de negócio informada pela responsável**. A alteração foi **revertida integralmente na branch em draft** (commit `edb90b24c87018298d498e8a9081c824fa238712`); o arquivo `src/Controller/InscricaoController.php` voltou a refletir `main`. O teste antigo de restrição por papel foi removido da branch.

O foco agora é **BOLA/IDOR horizontal**, não escalonamento entre papéis: usuários A e B com o mesmo `role` e `id` diferentes, cada um com recurso próprio, devem ser impedidos de acessar/modificar recursos privados de outro usuário, mantendo acessíveis os seus. Isso exige verificar propriedade em serviço e consultas, não apenas igualdade de `role`.

## 2. Preparação offline na branch PR #209

`tests/Unit/Security/HorizontalOwnershipContractTest.php` observa o **contrato implementado no código**:
- `InscricaoController`: handlers pessoais continuam a usar `requireAuth()` e repassam o ID de sessão, sem acrescentar regra vertical nova.
- `InscricaoRepository::listarPorUsuario`: filtro `usuario_id = :usuario_id`.
- `buscarPorIdEUsuario`: exige `id` **e** `usuario_id`.
- `cancelarPorUsuario`: checagem de propriedade anterior no serviço e filtro no `UPDATE`, com restrição aos status canceláveis.
- `EmpresaRepository::buscarPorUsuarioId` e `InscricaoRepository::buscarPorIdEEmpresa`: identidade empresarial e propriedade por `empresa_id`.
- `InscricaoService::atualizarStatusPorEmpresaOuAdmin` e `OportunidadeService::autorizarAcessoOportunidade`: ramos de administrador identificáveis; para empresa, verificação por empresa vinculada e ID do recurso.
- Guardas originais de `empresa/admin` nas rotas empresariais não são modificados.

**Natureza da evidência:** verificação de código com `ReflectionMethod` e asserções de presença de chamadas/consultas; não executa SQL em MariaDB, não emula sessão HTTP e **não comprova ausência de BOLA**. A execução positiva/negativa real será registrada quando as VMs retornarem. Nenhuma conta de teste, credencial ou ID real deve ser versionado no Git.

## 3. Matriz de reteste horizontal (após autorização operacional)

| Caso | Duas identidades do mesmo papel | Ação | Resultado esperado |
|---|---|---|---|
| BOLA-U01 | Conta A e conta B | A lista suas próprias inscrições | Mostra somente inscrições de A |
| BOLA-U02 | Conta A e conta B | A tenta consultar inscrição privada de B (quando houver endpoint aplicável) | Negado/não localizado; **nenhum dado de B** |
| BOLA-U03 | Conta A e conta B | A tenta cancelar inscrição de B por ID | Negado/não localizado; inscrição de B inalterada |
| BOLA-U04 | Conta A e conta B | A cancela sua inscrição elegível | Fluxo autorizado e alteração apenas em A |
| BOLA-E01 | Duas contas empresa distintas, **caso existam no fixture autorizado** | Empresa A tenta listar/alterar inscrição vinculada à empresa B | Negado/não localizado; registros de B inalterados |
| BOLA-E02 | Duas contas empresa distintas, **caso existam no fixture autorizado** | Empresa A altera sua própria inscrição elegível | Fluxo autorizado apenas no próprio escopo |

A existência das duas contas de mesmo papel foi informada pela responsável. **Não presumir que sejam contas empresa nem que existam dois recursos de propriedade distinta sem confirmação de fixture**; selecionar os casos aplicáveis, com IDs fictícios comprovados, quando a VM estiver disponível. Evitar inventar códigos HTTP exatos: alguns handlers retornam redirecionamentos em vez de 403, portanto registrar resposta/estado efetivo e a inexistência de efeito sobre o recurso alheio.

## 4. Relação com PA-05 e Zero Trust

- O primeiro Pentest A **foi encerrado administrativamente com cobertura parcial**; BOLA horizontal era pendência de cobertura, não evidência de vulnerabilidade explorada.
- No Pentest B, Twingate pode restringir visibilidade de serviços por grupos de rede, mas **não substitui checagem de dono em aplicação**. Mesmo duas contas do mesmo `role` precisam estar isoladas por recurso.
- Os controles verticais preexistentes seguem preservados. Não alterar comportamento nem criar novas regras de negócio sem solicitação explícita.
- **PR #209 permanece DRAFT**, sem merge. CI prova regressões de código no escopo realmente testado; reteste HTTP/BD/ownership permanece pendente.

## 5. Critérios de aceite futuros

A pessoa responsável pela campanha deverá registrar para cada caso: ator A/B, papéis iguais, ID de recurso fictício, URL/método/ação, estado antes/depois, código HTTP observado, resposta sanitizada, decisão esperada e diferença Pentest A vs. B. Usar snapshots/rollback e não tocar em dados reais. Resultado da consulta da própria conta também precisa ser positivo para evitar falso PASS por indisponibilidade global do serviço.

**Conclusão:** não há restrição nova às candidaturas; o trabalho do PR #209 serve exclusivamente para preparar a avaliação **horizontal** com as duas identidades de mesmo papel.
