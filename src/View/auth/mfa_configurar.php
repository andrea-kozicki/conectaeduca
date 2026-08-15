<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
$qrDataUri = $qrDataUri ?? '';
$segredo = $segredo ?? '';
?>
<!DOCTYPE html>
<html lang="pt-BR">

<head>
  <meta charset="UTF-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1.0">

  <title>
    ConectaEduca | Configurar autenticação
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
          MFA obrigatório
        </span>

        <h1>
          Proteja sua conta
        </h1>

        <p class="lead">
          O ConectaEduca exige autenticação em duas
          etapas para todas as contas.
        </p>

        <p>
          Escaneie o QR Code utilizando um aplicativo
          autenticador compatível com TOTP.
        </p>

      </section>

      <section class="auth-card">

        <h2>Configurar autenticador</h2>

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

        <?php if (
          is_string($qrDataUri)
          && $qrDataUri !== ''
        ): ?>

          <div class="mfa-qr">
            <img
              src="<?= htmlspecialchars(
                $qrDataUri,
                ENT_QUOTES | ENT_HTML5,
                'UTF-8'
              ) ?>"
              alt="QR Code para configuração do MFA">
          </div>

        <?php endif; ?>

        <p class="muted">
          Caso não consiga escanear o QR Code,
          informe manualmente esta chave no
          aplicativo autenticador:
        </p>

        <p>
          <code>
            <?= htmlspecialchars(
              (string) $segredo,
              ENT_QUOTES | ENT_HTML5,
              'UTF-8'
            ) ?>
          </code>
        </p>

        <form
          action="/mfa-configurar.php"
          method="post">

          <?= Csrf::inputField() ?>

          <div class="form-grid">

            <div class="form-group full">
              <label for="codigo">
                Código gerado pelo aplicativo
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
                required>
            </div>

          </div>

          <div class="hero-actions">
            <button
              class="button"
              type="submit">
              Ativar MFA
            </button>
          </div>

        </form>

      </section>

    </div>

  </main>

</body>
</html>
