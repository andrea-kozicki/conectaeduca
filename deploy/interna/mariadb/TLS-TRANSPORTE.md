# TLS MariaDB entre EP125 e EP126

A aplicação na EP125 e o MariaDB na EP126 atravessam uma fronteira de rede.
A implantação final deve usar TLS com verificação do servidor e rejeitar
transporte inseguro.

## Estado observado antes deste hardening

- MariaDB 12.3.2: TLS disponível.
- `require_secure_transport=OFF`.
- conexão plaintext ainda aceita.
- PDO da aplicação conecta sem TLS por padrão.
- PDO suporta `MYSQL_ATTR_SSL_CA` e verificação do certificado.

## Contrato de implantação

Servidor EP126:

- usar `compose.yml`;
- usar `compose.host.yml`;
- adicionar `compose.tls.yml`;
- fornecer CA, certificado e chave por arquivos externos ao Git;
- o certificado do MariaDB deve possuir SAN `IP:192.168.6.50`.

Aplicação EP125:

- usar o overlay `deploy/dmz/compose.database-tls.yml`;
- fornecer somente a CA pública do MariaDB;
- `DB_SSL_VERIFY_SERVER_CERT=true`.

Nenhuma chave privada ou credencial deve ser versionada.

## Root

A imagem oficial MariaDB usa `%` como host padrão da conta root.
O Compose passa a declarar `MARIADB_ROOT_HOST=localhost` para novos volumes.

Essa variável não altera um datadir já inicializado. O runtime existente deve
ser reconciliado separadamente, após confirmar acesso administrativo local,
removendo somente `root@'%'` e preservando `root@localhost`.

## Gate de promoção

Não ativar `compose.tls.yml` no MariaDB até:

1. existir PKI válida fora do Git;
2. a CA estar disponível na EP125;
3. o certificado do servidor possuir SAN compatível com `192.168.6.50`;
4. o PDO da aplicação estar com o overlay TLS;
5. um teste controlado comprovar conexão PDO com cipher TLS;
6. somente então validar que plaintext passa a ser rejeitado.
