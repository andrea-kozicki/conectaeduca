# GA-07 — teste isolado de rotação de log fictício, sem EP125

**Fonte de outubro:** [PR #203](https://github.com/andrea-kozicki/conectaeduca/pull/203). Esta extração inclui somente o template **não configurável sem autorização** e seus testes de logrotate em diretório temporário. Não incorpora configuração de agentes Wazuh, regras, instalador em `/etc/logrotate.d`, scripts com `sudo` ou mudança de retenção.

## Propriedades

- O arquivo `.conf.in` contém marcadores `@GA07_*@` **deliberadamente não resolvidos**. Ele **não** é uma configuração apta a ativação direta e não deverá ser copiado ao `/etc/logrotate.d`.
- Os testes verificam política não preenchida, permissões 0600, ausência de `copytruncate`, ausência de scripts `postrotate/prerotate` e nenhuma duração de retenção presumida.
- No runner GitHub Actions descartável, `logrotate` recebe um arquivo e uma configuração **fictícios em `TemporaryDirectory`**, realiza duas rotações sintéticas e confere conteúdo, inode de arquivo novo e permissão, sem acesso a `/var/log/conectaeduca`, Wazuh ou Docker.

## Limitações e gates de VM

A aprovação do teste **não comprova** rotação real, DAC/UID da conta do PHP, retomada do Wazuh após trocar inode, integridade da retenção institucional ou proteção de dados de usuários. Esses critérios permanecem no gate `CE-EP125-AUDIT-RETENTION` do [roteiro pré-VM](../operacao/CE-PREVM-GATES-20261118.md).

Para eventual configuração de produção, obter política aprovada, inventário de logrotate existentes e autorização; verificar backup, coleta após rotação e privacidade antes de gerar arquivo ativável. Não executar instaladores das PRs #203/#225 agora.
