# Mailpit de laboratório — imagem validada

Uso exclusivo de **desenvolvimento/teste** para capturar e-mails SMTP do ConectaEduca. Este componente **não pertence ao baseline de implantação final** das VMs.

## Imagem fixada

- Imagem: `axllent/mailpit:v1.30.6`
- Digest OCI: `sha256:7f33095f80e901f6ad08028f06ca284aa58fe84942be5496008d041d3b9f4d4d`
- Plataforma alvo: `linux/amd64`
- Portas internas padrão: SMTP `1025`, UI/API `8025`

## Controles do laboratório

- SMTP publicado somente em `127.0.0.1:11025`.
- UI/API publicada somente em `127.0.0.1:18025`.
- Sem autenticação e sem TLS **somente** porque o serviço fica restrito ao loopback local e é usado exclusivamente em desenvolvimento/teste.
- Container executa como UID/GID `10001:10001`.
- Root filesystem somente leitura.
- Todas as Linux capabilities removidas.
- `no-new-privileges` habilitado.
- Banco SQLite e `/tmp` são `tmpfs`; mensagens desaparecem quando o container é recriado.
- Limite de memória e swap: 256 MiB.
- Limite de PIDs: 128.
- Verificação automática de versão desabilitada para evitar contato desnecessário com serviço externo.
- Limite de 50 mensagens no laboratório.

## Nota de segurança sobre a versão

Na validação de 2026-08-20, a página oficial de tags Docker ainda publicava `v1.30.6` como artefato estável/`latest` disponível, embora o módulo-fonte já tivesse uma versão posterior publicada. O laboratório fixa o artefato Docker efetivamente verificável, em vez de usar `latest`.

Existe um bug público conhecido em `v1.30.6` envolvendo `DELETE /api/v1/messages` com IDs duplicados. O checkpoint do ConectaEduca **não usa endpoints DELETE**. Como o armazenamento é efêmero em `tmpfs`, a limpeza é feita recriando o container. O serviço também permanece restrito a loopback e limitado em memória/PIDs.

## Regra de implantação

Mailpit serve como capturador SMTP para evidências locais. Ele **não deve** ser levado para a VM final como servidor de e-mail de produção e não substitui um relay SMTP real com TLS/autenticação.
