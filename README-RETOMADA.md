# Retomada pós-reboot do laboratório ConectaEduca

## Objetivo

Restaurar de forma idempotente o baseline local após reboot do host,
sem reprovisionar o OpenBao e sem solicitar novamente a App Password SMTP.

### Recuperação administrativa única

`scripts/recuperacao/recuperar_approle_smtp_pos_reboot.py`

Esse procedimento é excepcional. Ele:

- usa temporariamente o fluxo administrativo de generate-root;
- configura o AppRole de workload;
- mantém RoleID/SecretID fora do Git;
- prova privilégio mínimo;
- revoga o root temporário;
- restaura o hardening do OpenBao.

### Retomada normal

`scripts/bootstrap/retomar_lab_pos_reboot.py`

O launcher:

- garante Docker;
- inicia e faz unseal do OpenBao usando a custódia local do laboratório;
- rematerializa o SMTP por AppRole em `/dev/shm`;
- sobe e valida MariaDB, PHP-FPM, Nginx e WAF;
- retoma Ferret sem pull desnecessário;
- garante Mailpit pelo Compose versionado;
- valida o baseline operacional.

O atalho local:

`~/.local/bin/conectaeduca-retomar`

deve apontar para o launcher versionado acima.

### Gate pré-Bacula

Após a consolidação do Git:

`conectaeduca-retomar --pre-bacula`

exige árvore limpa e executa os checkpoints completos que precedem a
implementação do Bacula.

## Segurança

As shares Shamir estão reunidas localmente apenas por conveniência do
laboratório. Elas não entram no Git, handoff, Bacula ou relatórios.

A App Password SMTP permanece no OpenBao e é materializada somente em RAM.
Root token e unseal shares não fazem parte do backup.
