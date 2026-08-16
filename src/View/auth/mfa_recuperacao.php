<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
?>
<!DOCTYPE html>
<html lang="pt-BR">

<head>
  <meta charset="UTF-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1.0">

  <title>
    ConectaEduca | Recuperar acesso ao MFA
  </title>

  <link
    rel="stylesheet"
    href="/assets/css/style.css">
</head>

<body>

  <main class="auth-wrap">
    <div class="container auth-grid">

      <section class="panel">
        <span class="eyebrow">
          Recuperação do MFA
        </span>

        <h1>
          Sem acesso ao autenticador?
        </h1>

        <p class="lead">
          Informe um dos códigos de recuperação que você
          guardou ao configurar a autenticação em duas etapas.
        </p>

        <p>
          Depois de validar o código, o autenticador antigo
          será substituído e você deverá cadastrar um novo.
        </p>
      </section>

      <section class="auth-card">

        <h2>Código de recuperação</h2>

        <?php if (
          is_string($error)
          && $error !== ''
        ): ?>
          <div class="notice">
            <?= htmlspecialchars(
              $error,
              ENT_QUOTES | ENT_HTML5,
              'UTF-8'
            ) ?>
          </div>
        <?php endif; ?>

        <form
          action="/mfa-recuperacao.php"
          method="post">

          <?= Csrf::inputField() ?>

          <div class="form-grid">
            <div class="form-group full">
              <label for="codigo_recuperacao">
                Código de recuperação
              </label>

              <input
                type="text"
                id="codigo_recuperacao"
                name="codigo_recuperacao"
                autocomplete="one-time-code"
                spellcheck="false"
                autocapitalize="characters"
                maxlength="24"
                placeholder="AAAA-BBBB-CCCC-DDDD-EEEE"
                required
                autofocus>
            </div>
          </div>

          <div class="hero-actions">
            <button
              class="button"
              type="submit">
              Recuperar MFA
            </button>
          </div>

        </form>

        <p class="muted">
          Ainda tem acesso ao aplicativo autenticador?
          <a href="/mfa.php">Voltar para o código TOTP</a>.
        </p>

      </section>

    </div>
  </main>

</body>
</html>
