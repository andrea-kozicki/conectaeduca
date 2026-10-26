# PA-05 / preparação do Pentest B — segregação de candidaturas (26/10/2026)

**Status:** PR #209 **DRAFT**, sem implantação nas VMs, sem alteração em `main`.

## Linha de base e classificação correta
- A primeira campanha **encerrou PA-05 administrativamente com cobertura parcial**: testes históricos de RBAC vertical tiveram resultados favoráveis no recorte, mas o teste BOLA/IDOR horizontal não foi executado de ponta a ponta. **Não reabrir/renomear essa conclusão retroativamente.**
- Esta revisão apresenta uma **nova divergência de desenho do código**, não uma exploração comprovada: `InscricaoController::minhas`, `criar` e `cancelar` permitiam entrada a qualquer sessão autenticada via `Authorization::requireAuth()`. O controle de papel não era aplicado nesses três handlers; demais restrições downstream precisam ser avaliadas separadamente.
- Correção **proposta** no PR #209: os três handlers passam a utilizar `Authorization::requireRole('usuario')` como primeira operação. Mantêm-se `requireAnyRole(['empresa','admin'])` nos handlers da empresa e `requireRole('admin')` em relatórios/auditoria.
- **Decisão de produto pendente:** confirmar formalmente se contas administrativas podem acumular papel de candidato. A proposta assume separação explícita dos três perfis. Se a regra de negócio divergir, revisar com o professor **antes do merge**.

## Testes offline efetivamente executados

- Arquivo `tests/Unit/Security/RbacCandidaturaNegativeTest.php`: 9 combinações exatas actor/role, 7 variações negativas de role, sessão ausente/sem role e verificação por Reflection dos guards de candidatura, empresa e admin (sem chamadas à aplicação, banco ou rede).
- GitHub Actions [PHPUnit Security Tests, run 40410376665](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40410376665): **SUCCESS; 140 tests, 410 assertions** (total da suíte). Gitleaks Secret Scanning, Repository Static Integrity e Semgrep SAST também **SUCCESS** no mesmo commit.
- Na preparação, um ajuste automático do guard gerou erroneamente `requireRole('usuario')()`, **identificado pelo teste** e corrigido no commit final. Esta falha era da **branch em preparação**, não do serviço EP125, que não foi modificado.
- Gitleaks sinalizou o literal sintético `GA07-FICTICIO-NAO-SECRETO` em commit anterior de outra branch; a allowlist no PR #209 fica restrita à regra `generic-api-key`, caminho exato do teste GA-07 e string literal. Não desativar o scanner nem marcar segredo real como resolvido sem análise.

## Matriz de intenção, ainda sujeita a aceite

| Fluxo | usuario | empresa | admin |
|---|---|---|---|
| Minhas candidaturas, criar e cancelar | ALLOW proposta | DENY proposta | DENY proposta |
| Candidaturas recebidas e status por empresa | DENY | ALLOW | ALLOW |
| Gerenciar oportunidades de empresa | DENY | ALLOW | ALLOW |
| Relatórios/auditoria administrativa | DENY | DENY | ALLOW |

**Twingate não substitui RBAC PHP.** A existência de acesso à porta 443 ou do Resource Twingate não confere papel `usuario`/empresa/admin; e `role=admin` PHP não implica grupo `TG-ADMIN` na rede.

## Evidências e testes ainda pendentes

1. Aprovação docente da separação estrita candidato/admin e revisão do risco de impacto.
2. Testes HTTP positivos/negativos após mudança autorizada: 200/401/403/419, sessão/expiração, MFA e fluxo anônimo público.
3. IDOR horizontal com dois candidatos fictícios e duas empresas fictícias; cenários de posse cruzada de inscrição/oportunidade, inclusive endpoints de atualização e cancelamento.
4. Validar status de oportunidade publicada x rascunho e comportamento público; não vazar objetos por endpoints alternativos.
5. Comparar Pentest A x B após adoção de Zero Trust, distinguindo rede de permissão de aplicação.
6. **PR permanece draft** e nenhuma VM, base de usuários, Wazuh, pfSense, suporte ou conta `lucy` foi alterada por este ensaio.

**Conclusão:** a CI prova conformidade do código proposto com a matriz estática e com a função de autorização sob cenários sintéticos; não comprova resposta HTTP da EP125 nem proteção BOLA.
