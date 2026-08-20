#!/usr/bin/env fish

set ROOT (git rev-parse --show-toplevel 2>/dev/null)

if test $status -ne 0 -o -z "$ROOT"
    echo "ERRO: execute dentro do repositorio ConectaEduca." >&2
    exit 1
end

cd "$ROOT"

set IMAGE "openbao/openbao:2.6.1@sha256:5b2486ab0fb90bbc788cc345b0a08616dfb375873ee8be5df3a2fd4d378a67e0"
set COMPOSE "deploy/interna/openbao/compose.yml"
set VOLUME "conectaeduca-openbao-data"
set RUNTIME "deploy/interna/openbao/.runtime"

echo "== OpenBao: preparacao do runtime =="

mkdir -p "$RUNTIME"
or begin
    echo "ERRO: nao foi possivel criar $RUNTIME." >&2
    exit 1
end

chmod 700 "$RUNTIME"
or begin
    echo "ERRO: nao foi possivel proteger $RUNTIME com modo 700." >&2
    exit 1
end

echo "Runtime local protegido: $RUNTIME (modo 700)"

docker info >/dev/null 2>&1
or begin
    echo "ERRO: Docker nao esta acessivel." >&2
    exit 1
end

echo "Validando imagem OpenBao..."

docker pull --platform linux/amd64 "$IMAGE" >/dev/null
or begin
    echo "ERRO: nao foi possivel obter a imagem OpenBao." >&2
    exit 1
end

if docker volume inspect "$VOLUME" >/dev/null 2>&1
    echo "Existente: $VOLUME"
else
    docker volume create "$VOLUME" >/dev/null
    or exit 1

    echo "Criado: $VOLUME"
end

echo "Ajustando proprietario e permissao do volume Raft..."

docker run --rm \
    --user 0:0 \
    --entrypoint /bin/sh \
    -v "$VOLUME:/openbao/data" \
    "$IMAGE" \
    -ec "chown -R openbao:openbao /openbao/data; chmod 700 /openbao/data"

or begin
    echo "ERRO: falha ao preparar o volume Raft." >&2
    exit 1
end

echo "Validando Docker Compose..."

docker compose -f "$COMPOSE" config >/dev/null
or begin
    echo "ERRO: Docker Compose invalido." >&2
    exit 1
end

echo
echo "OpenBao preparado com sucesso."
echo "Nenhum init, unseal ou segredo foi criado."
echo
echo "Para subir:"
echo "  docker compose -f $COMPOSE up -d"
