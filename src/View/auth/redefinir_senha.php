<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
$invalid = $invalid ?? false;
$token = is_string($token ?? null) ? trim($token) : '';
$serverHasToken = preg_match('/^[A-Za-z0-9_-]{43}$/', $token) === 1;
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>ConectaEduca | Redefinir senha</title>
  <link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
  <main class="auth-wrap">
    <div class="container auth-grid">
      <section class="panel">
        <span class="eyebrow">Nova senha</span>
        <h1>Redefina sua senha com segurança.</h1>
        <p class="lead">
          O link de recuperação é temporário e pode ser usado apenas uma vez.
        </p>
        <p>
          Este link foi criado exclusivamente para sua conta e será
          invalidado depois que a redefinição for concluída.
        </p>
      </section>

      <section class="auth-card">
        <h2>Criar nova senha</h2>

        <?php if (is_string($error) && $error !== ''): ?>
          <div class="notice">
            <?= htmlspecialchars($error, ENT_QUOTES | ENT_HTML5, 'UTF-8') ?>
          </div>
        <?php endif; ?>

        <?php if ($invalid): ?>
          <p class="muted">
            Solicite um novo link em
            <a href="/esqueci-senha.php">Esqueci minha senha</a>.
          </p>
        <?php else: ?>
          <div id="reset-token-status" class="notice" <?= $serverHasToken ? 'hidden' : '' ?>>
            Preparando o formulário de recuperação...
          </div>

          <form
            id="password-reset-form"
            action="/redefinir-senha.php"
            method="post"
            <?= $serverHasToken ? '' : 'hidden' ?>>

            <?= Csrf::inputField() ?>

            <input
              type="hidden"
              id="reset_token"
              name="token"
              value="<?= htmlspecialchars($token, ENT_QUOTES | ENT_HTML5, 'UTF-8') ?>">

            <div class="form-grid">
              <div class="form-group full">
                <label for="senha">Nova senha</label>
                <input
                  type="password"
                  id="senha"
                  name="senha"
                  minlength="8"
                  autocomplete="new-password"
                  required>
              </div>

              <div class="form-group full">
                <label for="confirmar_senha">Confirmar nova senha</label>
                <input
                  type="password"
                  id="confirmar_senha"
                  name="confirmar_senha"
                  minlength="8"
                  autocomplete="new-password"
                  required>
              </div>
            </div>

            <div class="hero-actions">
              <button class="button" type="submit">Redefinir senha</button>
              <a class="button-outline" href="/login.php">Voltar ao login</a>
            </div>
          </form>

          <noscript>
            <div class="notice">
              Para continuar com segurança, ative JavaScript e abra novamente
              o link de recuperação recebido por e-mail.
            </div>
          </noscript>
        <?php endif; ?>
      </section>
    </div>
  </main>

  <?php if (!$invalid && !$serverHasToken): ?>
    <script src="/assets/js/password-reset.js" defer></script>
  <?php endif; ?>
</body>
</html>
