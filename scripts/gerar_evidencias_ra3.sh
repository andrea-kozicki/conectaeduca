#!/usr/bin/env bash
set -uo pipefail

cd /srv/www/htdocs/conectaeduca || exit 1

RUN_ID="$(date +%Y%m%d_%H%M%S)"
EVDIR="docs/evidencias/ra3_${RUN_ID}"
PRINTDIR="${EVDIR}/prints"

mkdir -p "$EVDIR" "$PRINTDIR"

REPO_URL="$(git remote get-url origin 2>/dev/null || echo '')"

if [[ "$REPO_URL" == git@github.com:* ]]; then
  REPO_URL="https://github.com/${REPO_URL#git@github.com:}"
fi

REPO_URL="${REPO_URL%.git}"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'commit-nao-identificado')"
GH="${REPO_URL}/blob/${COMMIT}"

PRINT_COUNTER=1
PRINT_MODE="${PRINT_MODE:-full}" # full ou gui

linha() {
  printf '%*s\n' 72 '' | tr ' ' '='
}

titulo() {
  clear
  linha
  echo "$1"
  linha
  echo
}

screenshot() {
  local nome="$1"
  local arquivo
  arquivo="$(printf "%s/%02d_%s.png" "$PRINTDIR" "$PRINT_COUNTER" "$nome")"

  echo
  linha
  echo "PRINT: $arquivo"
  echo "Deixe o terminal visível."
  echo "Pressione ENTER para capturar com Flameshot."
  linha
  read -r _

  sleep 0.7

  if command -v flameshot >/dev/null 2>&1; then
    if [[ "$PRINT_MODE" == "gui" ]]; then
      flameshot gui -p "$arquivo" || true
    else
      flameshot full -p "$arquivo" || true
    fi
  else
    echo "Flameshot não encontrado."
    echo "Tire o print manualmente e salve como:"
    echo "$arquivo"
  fi

  if [[ -f "$arquivo" ]]; then
    echo "OK: print salvo em $arquivo"
  else
    echo "ATENÇÃO: print não foi criado automaticamente."
  fi

  PRINT_COUNTER=$((PRINT_COUNTER + 1))
}

run_cmd() {
  local nome="$1"
  local arquivo="$2"
  local print_nome="$3"
  shift 3

  titulo "$nome"

  {
    echo "===== $nome ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Diretório: $(pwd)"
    echo "Commit: $COMMIT"
    echo "Repositório: $REPO_URL"
    echo
    echo "Comando executado:"
    printf '%q ' "$@"
    echo
    echo
    echo "===== Saída ====="
    echo
  } > "$arquivo"

  "$@" 2>&1 | tee -a "$arquivo"
  local status="${PIPESTATUS[0]}"

  {
    echo
    echo "===== Exit code ====="
    echo "$status"
  } >> "$arquivo"

  echo
  echo "Exit code: $status"
  screenshot "$print_nome"
}

run_bash() {
  local nome="$1"
  local arquivo="$2"
  local print_nome="$3"
  local comando="$4"

  titulo "$nome"

  {
    echo "===== $nome ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Diretório: $(pwd)"
    echo "Commit: $COMMIT"
    echo "Repositório: $REPO_URL"
    echo
    echo "Comando executado:"
    echo "$comando"
    echo
    echo "===== Saída ====="
    echo
  } > "$arquivo"

  bash -lc "$comando" 2>&1 | tee -a "$arquivo"
  local status="${PIPESTATUS[0]}"

  {
    echo
    echo "===== Exit code ====="
    echo "$status"
  } >> "$arquivo"

  echo
  echo "Exit code: $status"
  screenshot "$print_nome"
}

gerar_manifesto_inicial() {
  cat > "$EVDIR/00_manifesto_execucao.txt" <<EOF
===== Manifesto de Evidências RA3 =====

Projeto: ConectaEduca
Data/hora: $(date -Is)
Diretório: $(pwd)
Repositório: $REPO_URL
Commit analisado: $COMMIT
Pasta de evidências: $EVDIR
Pasta de prints: $PRINTDIR

Observação:
As evidências foram geradas para apoiar a defesa do Trabalho Final RA3,
incluindo IAM/Cognito/JWT, autorização, OWASP, criptografia híbrida,
testes, GitHub e aplicação funcional.

Links úteis:
Repositório:
$REPO_URL

Commit:
$GH

EOF
}

evidencia_codigo_iam() {
  local arquivo="$EVDIR/iam-cognito-jwt-com-codigo.txt"

  titulo "Evidência IAM / Cognito / JWT com trechos de código"

  {
    echo "===== Evidência IAM / Cognito / JWT ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Commit analisado: $COMMIT"
    echo "Repositório: $REPO_URL"
    echo
    echo "Arquivos principais:"
    echo "$GH/src/Service/AuthService.php"
    echo "$GH/src/Security/CognitoOAuthClient.php"
    echo "$GH/src/Security/CognitoJwtVerifier.php"
    echo "$GH/src/Security/Authorization.php"
    echo "$GH/src/Security/SecureSession.php"
    echo
    echo "===== AuthService — troca code por tokens e valida id_token ====="
    echo "$GH/src/Service/AuthService.php#L20-L47"
    echo
    nl -ba src/Service/AuthService.php | sed -n '20,47p'
    echo
    echo "===== CognitoJwtVerifier — estrutura, algoritmo e assinatura ====="
    echo "$GH/src/Security/CognitoJwtVerifier.php#L16-L48"
    echo
    nl -ba src/Security/CognitoJwtVerifier.php | sed -n '16,48p'
    echo
    echo "===== CognitoJwtVerifier — issuer, token_use, audience e client_id ====="
    echo "$GH/src/Security/CognitoJwtVerifier.php#L60-L96"
    echo
    nl -ba src/Security/CognitoJwtVerifier.php | sed -n '60,96p'
    echo
    echo "===== CognitoJwtVerifier — JWKS ====="
    echo "$GH/src/Security/CognitoJwtVerifier.php#L111-L152"
    echo
    nl -ba src/Security/CognitoJwtVerifier.php | sed -n '111,152p'
    echo
    echo "===== Authorization — requireAuth, requireRole, requireAnyRole ====="
    echo "$GH/src/Security/Authorization.php#L20-L72"
    echo
    nl -ba src/Security/Authorization.php | sed -n '20,72p'
    echo
    echo "===== SecureSession — cookie seguro e regeneração ====="
    echo "$GH/src/Security/SecureSession.php#L14-L34"
    echo
    nl -ba src/Security/SecureSession.php | sed -n '14,34p'
  } | tee "$arquivo"

  screenshot "iam_cognito_jwt_codigo"
}

evidencia_codigo_crypto() {
  local arquivo="$EVDIR/criptografia-hibrida-com-codigo.txt"

  titulo "Evidência de criptografia híbrida com trechos de código"

  {
    echo "===== Evidência Criptografia Híbrida ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Commit analisado: $COMMIT"
    echo "Repositório: $REPO_URL"
    echo
    echo "Arquivos principais:"
    echo "$GH/api/public_key.php"
    echo "$GH/assets/js/crypto-utils.js"
    echo "$GH/assets/js/encrypted-form.js"
    echo "$GH/src/Core/SecureFormRequest.php"
    echo "$GH/src/Security/CryptoHybrid.php"
    echo
    echo "===== api/public_key.php ====="
    echo "$GH/api/public_key.php"
    echo
    nl -ba api/public_key.php | sed -n '1,140p'
    echo
    echo "===== crypto-utils.js — AES-GCM + RSA-OAEP ====="
    echo "$GH/assets/js/crypto-utils.js"
    echo
    nl -ba assets/js/crypto-utils.js | sed -n '1,220p'
    echo
    echo "===== SecureFormRequest — detecção e abertura do envelope ====="
    echo "$GH/src/Core/SecureFormRequest.php"
    echo
    nl -ba src/Core/SecureFormRequest.php | sed -n '1,140p'
    echo
    echo "===== CryptoHybrid — núcleo backend ====="
    echo "$GH/src/Security/CryptoHybrid.php"
    echo
    nl -ba src/Security/CryptoHybrid.php | sed -n '1,260p'
  } | tee "$arquivo"

  screenshot "criptografia_hibrida_codigo"
}

evidencia_jwt_invalido() {
  local arquivo="$EVDIR/jwt-invalido-rejeitado.txt"

  titulo "JWT inválido rejeitado"

  {
    echo "===== Evidência de rejeição de JWT inválido ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Commit analisado: $COMMIT"
    echo "Arquivo de origem:"
    echo "$GH/src/Security/CognitoJwtVerifier.php"
    echo
    echo "Trechos relevantes:"
    echo "$GH/src/Security/CognitoJwtVerifier.php#L16-L31"
    echo "$GH/src/Security/CognitoJwtVerifier.php#L45-L48"
    echo
    echo "===== Código — validação estrutural ====="
    nl -ba src/Security/CognitoJwtVerifier.php | sed -n '16,31p'
    echo
    echo "===== Código — validação de assinatura ====="
    nl -ba src/Security/CognitoJwtVerifier.php | sed -n '45,48p'
    echo
    echo "===== Resultado do teste executado ====="
    php -r '
    require "api/bootstrap.php";

    use ConectaEduca\Security\CognitoJwtVerifier;

    try {
        CognitoJwtVerifier::verify("token.invalido.aqui");
        echo "ERRO: token inválido foi aceito\n";
        exit(1);
    } catch (Throwable $e) {
        echo "OK: token inválido rejeitado\n";
        echo "Motivo: " . $e->getMessage() . "\n";
    }
    '
  } | tee "$arquivo"

  screenshot "jwt_invalido_rejeitado"
}

evidencia_public_key() {
  local arquivo="$EVDIR/public-key-endpoint.txt"

  titulo "Endpoint de chave pública"

  {
    echo "===== Evidência endpoint de chave pública ====="
    echo
    echo "URL: https://conectaeduca.local/api/public_key.php"
    echo
    echo "Observação: chave pública pode ser exposta; chave privada não deve aparecer."
    echo
    curl -k -sS https://conectaeduca.local/api/public_key.php | php -r '
    $raw = stream_get_contents(STDIN);
    $json = json_decode($raw, true);

    if (!is_array($json)) {
        echo $raw . PHP_EOL;
        exit(0);
    }

    echo "ok: " . var_export($json["ok"] ?? null, true) . PHP_EOL;
    echo "algorithm: " . ($json["algorithm"] ?? "") . PHP_EOL;
    echo "hash: " . ($json["hash"] ?? "") . PHP_EOL;
    echo "public_key_pem_inicio: " . substr($json["public_key_pem"] ?? "", 0, 80) . "..." . PHP_EOL;
    '
  } | tee "$arquivo"

  screenshot "public_key_endpoint"
}

evidencia_banco_criptografia() {
  local arquivo="$EVDIR/banco-mensagens-cifradas.txt"

  titulo "Banco com mensagens cifradas"

  echo "Esta evidência tenta consultar a tabela mensagens_contato."
  echo "Se pedir senha sudo, digite normalmente."
  echo "Pressione ENTER para continuar ou CTRL+C para pular."
  read -r _

  {
    echo "===== Evidência de dado cifrado no banco ====="
    echo
    echo "Data/hora: $(date -Is)"
    echo "Commit analisado: $COMMIT"
    echo
    echo "Comando:"
    echo "sudo mariadb conectaeduca -e SELECT ..."
    echo
    echo "===== Resultado ====="
    sudo mariadb conectaeduca -e "
    SELECT
      id,
      usuario_id,
      assunto,
      categoria,
      status,
      algoritmo,
      LEFT(encrypted_key, 80) AS encrypted_key_resumo,
      iv,
      tag,
      LEFT(ciphertext, 120) AS ciphertext_resumo,
      criado_em
    FROM mensagens_contato
    ORDER BY id DESC
    LIMIT 5;
    "
  } 2>&1 | tee "$arquivo"

  screenshot "banco_mensagens_cifradas"
}

gerar_manifesto_final() {
  {
    echo
    echo "===== Arquivos gerados ====="
    find "$EVDIR" -type f | sort
    echo
    echo "===== SHA256 das evidências ====="
    find "$EVDIR" -type f ! -name '*.png' -print0 | sort -z | xargs -0 sha256sum 2>/dev/null || true
  } >> "$EVDIR/00_manifesto_execucao.txt"
}

gerar_manifesto_inicial

run_cmd "Versões do ambiente" "$EVDIR/ambiente-versoes.txt" "ambiente_versoes" bash -lc 'php -v && echo && composer --version && echo && vendor/bin/phpunit --version && echo && git --version'

run_cmd "Composer validate" "$EVDIR/composer-validate-final.txt" "composer_validate" composer validate

run_cmd "Composer audit" "$EVDIR/composer-audit-final.txt" "composer_audit" composer audit

run_bash "PHP lint final" "$EVDIR/php-lint-final.txt" "php_lint" 'find src public api tests -name "*.php" -print0 | xargs -0 -n1 php -l'

run_cmd "PHPUnit TestDox" "$EVDIR/phpunit-testdox-final.txt" "phpunit_testdox" vendor/bin/phpunit --testdox

run_cmd "Git status" "$EVDIR/git-status-final.txt" "git_status" git status --short

run_cmd "Git log recente" "$EVDIR/git-log-recente.txt" "git_log" git log --oneline --decorate -20

run_bash "Segredos rastreados no Git" "$EVDIR/segredos-rastreados-git.txt" "segredos_rastreados" 'git ls-files | grep -E "(^\.env$|^storage/keys/|^storage/logs/|^vendor/)" || echo "OK: .env, storage/keys, storage/logs e vendor não aparecem rastreados pelo Git."'

run_bash "Arquivos de backup restantes" "$EVDIR/backups-restantes.txt" "backups_restantes" 'find . \( -name "*.bak" -o -name "*.bak_*" \) -print | sort || true'

run_cmd "Bloqueio dashboard sem login" "$EVDIR/bloqueio-dashboard-sem-login.txt" "bloqueio_dashboard_sem_login" curl -k -i https://conectaeduca.local/dashboard.php

run_cmd "Bloqueio admin sem login" "$EVDIR/bloqueio-admin-sem-login.txt" "bloqueio_admin_sem_login" curl -k -i https://conectaeduca.local/admin/mensagens_contato.php

evidencia_codigo_iam
evidencia_jwt_invalido
evidencia_codigo_crypto
evidencia_public_key

run_cmd "Logs de auditoria recentes" "$EVDIR/audit-log-recente.txt" "audit_log" tail -n 100 storage/logs/audit.log

echo
linha
echo "Deseja gerar também evidência do banco com mensagens cifradas?"
echo "Isso usa: sudo mariadb conectaeduca -e SELECT ..."
echo "Digite s para sim, qualquer outra tecla para pular:"
linha
read -r RESP_BANCO

if [[ "$RESP_BANCO" == "s" || "$RESP_BANCO" == "S" ]]; then
  evidencia_banco_criptografia
else
  echo "Evidência de banco pulada." | tee "$EVDIR/banco-mensagens-cifradas-PULADO.txt"
fi

gerar_manifesto_final

titulo "Finalizado"

echo "Evidências geradas em:"
echo "$EVDIR"
echo
echo "Prints gerados em:"
echo "$PRINTDIR"
echo
echo "Manifesto:"
echo "$EVDIR/00_manifesto_execucao.txt"
echo
echo "Próximo passo sugerido:"
echo "git status --short"
echo "git add scripts/gerar_evidencias_ra3.sh $EVDIR"
echo "git commit -m \"Adiciona evidências finais automatizadas da RA3\""
echo "git push origin main"
echo
