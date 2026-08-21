# Stack local persistente

Este perfil mantém o ConectaEduca conteinerizado em execução para testes manuais
pelo navegador, sem destruir o volume MariaDB ao final.

## Endpoint

- Aplicação/WAF HTTPS: `https://conectaeduca.local:18444/`
- WAF HTTP local: `http://conectaeduca.local:18081/`
- OpenBao: `http://127.0.0.1:18200` (somente laboratório atual)
- MariaDB: publicado apenas no gateway da bridge Docker, porta `13306`

PHP-FPM e Nginx não são publicados no host quando os overlays WAF são usados.

## Secrets persistentes do laboratório

O launcher cria material local em:

`deploy/lab/stack-local/.runtime/`

Esse diretório é ignorado pelo Git e deve permanecer com modo `0700`.

Os arquivos secretos usam um grupo de sistema dedicado sem membros humanos e
modo `0640`. O GID é injetado como grupo suplementar apenas nos containers que
precisam ler o secret montado.

O App Password SMTP continua separado: ele é materializado pelo OpenBao em
`/dev/shm/conectaeduca-smtp-password` e usa seu próprio grupo dedicado.

## MariaDB

O volume `conectaeduca-mariadb-local_mariadb_data` é persistente. O comando de
parada não usa `down -v`.

Se o volume existir e os secrets locais do banco tiverem desaparecido, o
launcher se recusa a gerar novas senhas, pois isso quebraria a autenticação do
volume existente.

## TLS

O launcher tenta reutilizar o par de certificado local existente em
`/etc/apache2/ssl/conectaeduca/`. Se ele não existir ou não tiver SAN para
`conectaeduca.local`, cria um certificado autoassinado de laboratório.

## Prova funcional de recuperação

Depois que o stack estiver online:

1. execute `fish scripts/bootstrap/preparar_usuario_reset_e2e.fish`;
2. informe um e-mail da caixa Google de testes (aliases `+tag` são úteis);
3. abra `https://conectaeduca.local:18444/login.php`;
4. use “Esqueceu sua senha?”;
5. abra o e-mail recebido;
6. redefina a senha;
7. faça login com a nova senha;
8. tente reutilizar o mesmo link para confirmar bloqueio de replay.
