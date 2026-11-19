# PA-04 — política e AppRole OpenBao, somente modelo offline

**Recorte 18/11/2026.** A [PR #228](https://github.com/andrea-kozicki/conectaeduca/pull/228) contém o script `ops/pa04/ce_pa04_acl01.py`, que **escreve políticas, mounts e AppRole** usando credencial administrativa no OpenBao da EP126. Por isso o código executável **não é integrado nem acionado** nesta preparação.

Este pacote conserva **apenas valores declarativos de escopo e menor privilégio** em `docs/release/pa04-openbao-candidate/approle-policy.candidate.json`, formato deliberadamente marcado `NOT_DEPLOYABLE_DOC_ONLY`. Origem do contrato: blob Git da #228 `923d264313c103da14e2ae3ca9c989c1a00c3414`.

## Contrato preparado

- KV v2 reservado: `ce-app/`; auth mount separado `ce-approle/`; ACL exata `ce-app/data/runtime/app` e capacidade **somente `read`**, sem `list`, `create`, `update`, `delete` ou `sudo`.
- AppRole: SecretID obrigatório, 1 uso, TTL 10m; política padrão desabilitada; token de serviço com TTL 15m, máximo 1h e uma política vinculada.
- O modelo não contém `RoleID`, `SecretID`, senha, token administrativo, valor de segredo nem comando de ativação; não contém endpoint de rede.
- Oito regressões Python offline verificam contrato, escopo e negativas para ampliação de privilégios, reaproveitamento de SecretID, TTL, exposição de credenciais e uso operacional indevido.

## Gating antes da VM

1. Verificar se `ce-app/`, `ce-approle/`, política e role já existem **sem ler seus segredos**; não criar um novo mount se houver conflito ou dependência de dados preexistentes.
2. Confirmar a identidade de processo real que necessitará do caminho. **A existência de uma política não prova integração da aplicação** nem ausência de acessos excessivos de outras identidades.
3. Verificar custódia de token e SecretID em canal autorizado; não solicitar nem colar credenciais, unseal shares ou logs sensíveis no chat/GitHub/Trello.
4. Aprovar rollback caso políticas, methods ou roles sejam criados parcialmente; validar permissão administrativa de forma limitada sem executar o script histórico.
5. Para eventual acesso entre VMs, exigir transporte seguro, identidade e confiança TLS; o script antigo usa HTTP localhost e não serve como solução de integração inter-VM.
6. Autorizar e executar testes positivos **e negativos** de capacidades com credenciais sintéticas antes de atribuir PASS ao PA-04. Nenhum desses testes de runtime ocorreu nesta PR.

**Proibido interpretar esta PR como OpenBao configurado.** O estado da EP126 permanece PENDING_VM. O script mutante #228 fica DRAFT, não há criação de AppRole, alteração de política, solicitação de token ou mudança no cofre.
