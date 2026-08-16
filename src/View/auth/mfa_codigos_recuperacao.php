<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
$codigos = $codigos ?? [];
?>
<!DOCTYPE html>
<html lang="pt-BR">

<head>
  <meta charset="UTF-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1.0">

  <title>
    ConectaEduca | Códigos de recuperação
  </title>

  <link
    rel="stylesheet"
    href="/assets/css/style.css">

  <style>
    .recovery-codes-list {
      display: grid;
      gap: 0.65rem;
      margin: 1rem 0 1.25rem;
    }

    .recovery-code-item {
      margin: 0 !important;
    }

    .recovery-code-item code {
      display: block;
      width: 100%;
      box-sizing: border-box;
      padding: 0.8rem 1rem;
      border-radius: 0.75rem;
      background: #eef8f7;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco,
        Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: clamp(0.95rem, 2.5vw, 1.1rem) !important;
      font-weight: 700;
      line-height: 1.35;
      letter-spacing: 0.06em;
      text-align: center;
      color: inherit;
      overflow-wrap: anywhere;
    }

    .recovery-confirmation {
      display: inline-flex !important;
      align-items: center !important;
      gap: 0.65rem;
      cursor: pointer;
    }

    .recovery-confirmation input[type="checkbox"] {
      appearance: auto !important;
      -webkit-appearance: checkbox !important;
      width: 1rem !important;
      height: 1rem !important;
      min-width: 1rem !important;
      min-height: 1rem !important;
      max-width: 1rem !important;
      max-height: 1rem !important;
      padding: 0 !important;
      margin: 0 !important;
      flex: 0 0 1rem !important;
      box-sizing: border-box !important;
    }

    .recovery-confirmation span {
      display: inline;
    }
  </style>
</head>

<body>

  <main class="auth-wrap">
    <div class="container auth-grid">

      <section class="panel">
        <span class="eyebrow">
          Recuperação do MFA
        </span>

        <h1>
          Guarde seus códigos de recuperação
        </h1>

        <p class="lead">
          Estes códigos permitem recuperar o acesso caso você
          perca o aplicativo autenticador.
        </p>

        <p>
          Cada código pode ser utilizado apenas uma vez.
          Guarde-os em um local seguro e não os compartilhe.
        </p>
      </section>

      <section class="auth-card">

        <h2>Códigos de recuperação</h2>

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

        <div class="notice">
          Esta é a etapa de apresentação dos códigos.
          Depois de confirmar que os salvou, eles não serão
          exibidos novamente neste fluxo.
        </div>

        <div class="recovery-codes-list">
          <?php foreach ($codigos as $codigo): ?>
            <div class="recovery-code-item">
              <code><?= htmlspecialchars(
                (string) $codigo,
                ENT_QUOTES | ENT_HTML5,
                'UTF-8'
              ) ?></code>
            </div>
          <?php endforeach; ?>
        </div>

        <form
          action="/mfa-codigos-recuperacao.php"
          method="post">

          <?= Csrf::inputField() ?>

          <div class="form-group full">
            <label class="recovery-confirmation">
              <input
                type="checkbox"
                name="confirmado"
                value="1"
                required>
              <span>
                Já salvei os códigos em um local seguro.
              </span>
            </label>
          </div>

          <div class="hero-actions">
            <button
              class="button"
              type="submit">
              Concluir configuração
            </button>
          </div>

        </form>

      </section>

    </div>
  </main>

</body>
</html>
