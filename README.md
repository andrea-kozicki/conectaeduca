# ConectaEduca - geração de chaves RSA com Makefile portável

Este projeto usa criptografia híbrida no fluxo de cadastro:

- o cliente criptografa os dados com uma chave AES temporária
- a chave AES é criptografada com a chave pública RSA do servidor
- o servidor usa a chave privada RSA para recuperar a chave AES
- o servidor processa o cadastro e devolve a resposta também criptografada

## Por que usar Makefile para as chaves

A geração das chaves **não fica no JavaScript** e nem no fluxo normal do PHP porque a chave privada deve permanecer no servidor.

O Makefile ajuda a:

- gerar o par de chaves no ambiente do servidor
- manter a chave privada fora do cliente
- evitar hardcoding de segredos no código
- documentar melhor a gestão de segredos para a atividade

## Estrutura esperada

```text
conectaeduca/
├── Makefile
├── api/
├── assets/
├── keys/
│   ├── private.pem
│   └── public.pem
├── public/
├── sql/
└── vendor/
```

## Alvos disponíveis

```bash
make help
```

Saídas principais:

- `make setup` -> gera as chaves se elas ainda não existirem
- `make check-keys` -> verifica se as chaves existem
- `make keys` -> gera ou regenera as chaves
- `make check` -> valida se a chave pública corresponde à privada
- `make fix-perms` -> aplica permissões seguras
- `make fix-owner OWNER=x GROUP=y` -> ajusta dono/grupo, se necessário
- `make clean` -> remove as chaves

## Uso mais comum

Na raiz do projeto:

```bash
make setup
```

Depois confira:

```bash
ls -l keys
```

Você deve ter:

- `keys/private.pem`
- `keys/public.pem`

## Ajuste de dono/grupo por ambiente

Este Makefile foi adaptado para ser mais portável. Ele **não assume** que toda máquina usa o mesmo usuário do servidor web.

### openSUSE
Geralmente:

```bash
make fix-owner OWNER=wwwrun GROUP=www
```

### Debian/Ubuntu
Geralmente:

```bash
make fix-owner OWNER=www-data GROUP=www-data
```

### Outro ambiente
Descubra o usuário do servidor web e ajuste conforme necessário.

## Permissões recomendadas

O alvo `make fix-perms` tenta aplicar:

- pasta `keys/` -> `750`
- `private.pem` -> `640`
- `public.pem` -> `644`

A ideia é:

- a chave privada não ficar exposta publicamente
- a chave pública poder ser lida pelo servidor para ser servida ao cliente

## Como isso se relaciona com a atividade

Na atividade da disciplina, isso ajuda a demonstrar:

- **gestão de segredos**
- separação entre **segredo** e **parâmetro público**
- evidência de que a chave privada não está hardcoded
- automação simples do provisionamento criptográfico

### O que é segredo
- `keys/private.pem`
- a chave AES temporária da requisição
- segredos do `.env`

### O que é público
- `keys/public.pem`
- IV
- algoritmo utilizado
- payload cifrado

## Teste rápido depois de gerar as chaves

Abra no navegador:

```text
http://conectaeduca.local/api/public_key.php
```

Se estiver tudo certo, o endpoint deve responder JSON com a chave pública.

Depois você pode testar o cadastro em:

```text
http://conectaeduca.local/cadastro_usuario.php
```

## Observação importante para repositório público

Para um repositório público, a melhor prática é:

- **não versionar** `private.pem`
- **não hardcodar** usuário como `www-data`, `wwwrun` ou `apache`
- permitir configuração por variáveis, por exemplo:

```bash
make fix-owner OWNER=wwwrun GROUP=www
```

ou

```bash
make fix-owner OWNER=www-data GROUP=www-data
```

## Sugestão de `.gitignore`

Garanta que exista algo assim:

```gitignore
keys/private.pem
keys/public.pem
.env
```

## Fluxo recomendado de setup em uma máquina nova

1. entrar na raiz do projeto
2. gerar as chaves
3. subir o banco
4. testar a API da chave pública
5. testar o cadastro criptografado

Exemplo:

```bash
cd /srv/www/htdocs/conectaeduca
make setup
sudo mariadb < sql/conectaeduca.sql
```

Depois:

```text
http://conectaeduca.local/api/public_key.php
http://conectaeduca.local/cadastro_usuario.php
```

## Limitações

Este Makefile é mais portável, mas ainda depende de ferramentas como:

- `openssl`
- shell compatível
- `cmp`
- `chmod`
- opcionalmente `chown`

Em ambientes sem essas ferramentas, será necessário instalar dependências ou adaptar os comandos.
