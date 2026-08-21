# OpenBao operacional para SMTP do ConectaEduca

## Escopo desta fase

Esta fase transforma o OpenBao do estado pré-inicialização para um estado operacional
mínimo no laboratório local.

Controles:

- Shamir com 3 shares e threshold 2;
- root token inicial usado somente durante o bootstrap e revogado ao final;
- KV v2 em `secret/`;
- segredo SMTP em `secret/data/conectaeduca/smtp`;
- policy `conectaeduca-smtp-read` com apenas `read`;
- AppRole com `bind_secret_id=true`;
- SecretID de uso único e TTL curto;
- token AppRole usado somente para materialização e revogado;
- segredo materializado em `/dev/shm`, nunca no Git;
- auditoria OpenBao em stdout, pronta para coleta posterior pelo Wazuh.

## Custódia

O bootstrap cria temporariamente:

`~/.local/share/conectaeduca/openbao-custodia-lab/`

com três shares Shamir. Esta cópia agregada é somente para permitir a transição
segura no laboratório. Depois de confirmar a recuperação, distribua as shares por
custódias distintas/offline e remova a cópia agregada do notebook.

Nunca coloque shares, root token, AppRole SecretID ou senha SMTP em Git,
relatórios, screenshots ou conversas.

## Limite arquitetural atual

O listener OpenBao ainda usa HTTP internamente porque, no laboratório atual, a
publicação da API está restrita a `127.0.0.1:18200`.

Isso NÃO autoriza HTTP entre VMs.

Antes de a DMZ consumir OpenBao através da rede entre VMs, deve ser implementado:

1. TLS no listener OpenBao;
2. certificado/CA confiável;
3. regra pfSense mínima DMZ -> OpenBao;
4. OpenBao Agent/Proxy ou outro mecanismo de workload identity;
5. entrega de SecretID por canal de bootstrap confiável, preferencialmente com
   response wrapping.

## SMTP Google

O runtime gerado usa:

- `smtp.gmail.com`
- porta `587`
- STARTTLS
- autenticação SMTP
- usuário = endereço completo da Conta Google
- senha = App Password do Google, nunca a senha normal da conta.

A configuração não secreta fica em:

`deploy/dmz/.runtime/smtp-google.env`

O App Password materializado fica em RAM:

`/dev/shm/conectaeduca-smtp-password`

Após reboot, a materialização desaparece por projeto.
