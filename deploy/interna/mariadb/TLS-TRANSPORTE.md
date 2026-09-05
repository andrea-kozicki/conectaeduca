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
- adicionar `compose.tls.yml` para materializar CA/certificado/chave e fazer o
  MariaDB apresentar TLS;
- adicionar `compose.tls-enforce.yml` somente na fase final, depois de a
  aplicação já ter sido comprovada sob TLS;
- fornecer CA, certificado e chave por arquivos externos ao Git;
- o certificado do MariaDB deve possuir SAN `IP:192.168.6.50`.

Aplicação EP125:

- usar o overlay `deploy/dmz/compose.database-tls.yml`;
- fornecer somente a CA pública do MariaDB;
- `DB_SSL_VERIFY_SERVER_CERT=true`.

Nenhuma chave privada ou credencial deve ser versionada.

## Separação deliberada de fases

`compose.tls.yml` e `compose.tls-enforce.yml` possuem responsabilidades
diferentes.

### Fase A — servidor apresenta TLS, mas plaintext ainda é tolerado

Na EP126, aplicar:

- `compose.yml`;
- `compose.host.yml`;
- `compose.tls.yml`.

Nessa fase o MariaDB deve apresentar o certificado configurado e aceitar TLS,
mas `require_secure_transport` ainda deve permanecer `OFF`.

Isso permite preparar e validar a EP125 sem criar uma janela de indisponibilidade.

### Fase B — aplicação passa a exigir e verificar TLS

Na EP125, aplicar `deploy/dmz/compose.database-tls.yml` e fornecer somente a CA.

Antes de avançar, provar:

- conexão PDO aprovada;
- `Ssl_cipher` não vazio;
- versão TLS registrada;
- verificação do certificado do servidor ativa;
- aplicação funcional.

### Fase C — servidor rejeita plaintext

Somente depois da Fase B aprovada, adicionar na EP126:

- `compose.tls-enforce.yml`.

Esse overlay monta exclusivamente:

`require-secure-transport.cnf`

que define:

`require_secure_transport = ON`

Depois da promoção, provar:

- `require_secure_transport=ON`;
- conexão TLS da aplicação continua aprovada;
- tentativa controlada com `--skip-ssl` é rejeitada;
- healthcheck permanece saudável.

## Root

A imagem oficial MariaDB usa `%` como host padrão da conta root.
O Compose declara `MARIADB_ROOT_HOST=localhost` para novos volumes.

Essa variável não altera um datadir já inicializado. O runtime existente deve
ser reconciliado separadamente, após confirmar acesso administrativo local,
removendo somente `root@'%'` e preservando `root@localhost`.

A remoção de `root@'%'` não faz parte da ativação TLS e deve ocorrer somente
depois de o transporte seguro estar estabilizado.

## Gate de promoção

A sequência obrigatória é:

1. gerar PKI válida fora do Git;
2. emitir certificado do MariaDB com SAN `IP:192.168.6.50`;
3. EP126: ativar somente `compose.tls.yml`;
4. comprovar que o MariaDB apresenta TLS e ainda permanece operacional;
5. disponibilizar apenas a CA pública na EP125;
6. EP125: ativar `compose.database-tls.yml`;
7. comprovar PDO com cipher TLS e aplicação funcional;
8. EP126: adicionar `compose.tls-enforce.yml`;
9. comprovar que plaintext é rejeitado;
10. validar novamente o fluxo funcional completo;
11. somente depois reconciliar `root@'%'`.

Não inverter as fases 3, 6 e 8.
