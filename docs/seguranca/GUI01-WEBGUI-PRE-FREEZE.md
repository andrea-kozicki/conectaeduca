# GUI-01 — WebGUI pré-freeze

Estado em 21/09/2026: REPO-01 concluído; esta mudança apenas versiona o desenho,
as políticas e os gates. Nenhum APPLY de runtime é executado pelo Git.

## OpenBao
- UI já existente em `127.0.0.1:18200`.
- auth humano: `userpass/`.
- usuário padrão acadêmico: `teste`.
- senha: padrão acadêmico de 5 caracteres fornecido pelo professor, informada somente por prompt oculto e nunca versionada.\n- policies: `default` + `conectaeduca-human-view`, sem privilégios administrativos.
- TTL 30 min; max TTL 2 h.
- lockout: 5 tentativas / 15 min / reset 15 min.
- leitura de metadados KV permitida.
- leitura de `secret/data/*` não permitida.
- AppRole continua exclusivo para workloads.
- APPLY exige token administrativo temporário em prompt oculto.
- o script não gera nem persiste root.

## Bacularis
- objetivo: dashboard/observação com conta de demonstração `teste`.
- não duplicar o Bacula existente.
- não usar Docker socket/privileged/host network.
- Console ACL dedicada de observação para `teste`.
- Catalog role somente SELECT.
- configuração Bacula sem escrita.
- UI loopback-only.
- escolha final da integração após preflight live da EP126.

## Ordem
1. concluir REPO-01;
2. versionar e revisar GUI-01;
3. executar HOST-01 por `ff-only`, uma VM por vez;
4. aplicar OpenBao/Bacularis na EP126;
5. gate visual Ferret;
6. inventário final;
7. FREEZE-01.

## Gates de segurança

- os modos `check`/precheck são somente leitura e geram relatório + SHA-256;
- token administrativo e senha humana entram apenas por prompt oculto;
- nenhum segredo, token, share ou credencial pode entrar no Git ou na evidência;
- o OpenBao permanece em `127.0.0.1:18200`;
- o Bacularis futuro permanece em `127.0.0.1:9097` e sem função de execução,
  restauração, cancelamento, exclusão ou administração de software;
- rollback do OpenBao remove o usuário e a policy dedicados, preservando o
  auth mount `userpass/` para não afetar outros usuários.
