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
    ConectaEduca | Verificação em duas etapas
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
          Segurança da conta
        </span>

        <h1>
          Verificação em duas etapas
        </h1>

        <p class="lead">
          Abra seu aplicativo autenticador e informe
          o código temporário de seis dígitos.
        </p>
      </section>

      <section class="auth-card">

        <h2>Código de autenticação</h2>

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
          action="/mfa.php"
          method="post">

          <?= Csrf::inputField() ?>

          <div class="form-grid">

            <div class="form-group full">
              <label for="codigo">
                Código de 6 dígitos
              </label>

              <input
                type="text"
                id="codigo"
                name="codigo"
                inputmode="numeric"
                autocomplete="one-time-code"
                pattern="[0-9]{6}"
                minlength="6"
                maxlength="6"
                required
                autofocus>
            </div>

          </div>

          <div class="hero-actions">
            <button
              class="button"
              type="submit">
              Verificar
            </button>
          </div>

        </form>

      </section>

    </div>
  </main>

</body>
</html>
