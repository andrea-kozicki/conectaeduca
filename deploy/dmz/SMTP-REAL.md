# SMTP real do ConectaEduca

Este overlay prepara a aplicação PHP da DMZ para usar um relay SMTP autenticado com TLS.
Ele não contém credenciais e não substitui o Mailpit, que continua sendo laboratório.

## Contrato de configuração

O host de implantação fornece:

- `CONECTAEDUCA_SMTP_HOST`
- `CONECTAEDUCA_SMTP_PORT` (padrão 587)
- `CONECTAEDUCA_SMTP_USERNAME`
- `CONECTAEDUCA_SMTP_PASSWORD_FILE` — arquivo fora do Git, modo restritivo
- `CONECTAEDUCA_SMTP_ENCRYPTION` (`tls`/`starttls` ou `smtps`/`ssl`)
- `CONECTAEDUCA_SMTP_FROM_ADDRESS`
- `CONECTAEDUCA_SMTP_FROM_NAME` (opcional)

O container recebe somente o caminho `/run/secrets/conectaeduca_smtp_password`; o valor não entra no Compose nem no repositório.

## OpenBao

O contrato é compatível com OpenBao, mas não presume que o cofre já esteja inicializado. Quando o OpenBao entrar na fase operacional, um agente/template ou bootstrap autenticado poderá materializar o segredo em um arquivo efêmero no host da DMZ. Esse arquivo será apontado por `CONECTAEDUCA_SMTP_PASSWORD_FILE`.

Não utilizar root token do OpenBao no container da aplicação e não versionar tokens AppRole, senhas SMTP ou arquivos materializados.

## O que significa "SMTP aprovado"

O checkpoint automatizado prova:

1. segredo consumido por arquivo;
2. autenticação SMTP habilitada;
3. TLS/SMTPS com validação de certificado/hostname;
4. o relay aceitou a mensagem para entrega;
5. execução partindo do container PHP da DMZ.

A entregabilidade final ainda exige confirmar a chegada em uma caixa real (e verificar spam). Para domínio próprio, SPF, DKIM e DMARC são controles externos ao PHPMailer e devem ser verificados no provedor/DNS.
