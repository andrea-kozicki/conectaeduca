<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
$message = $message ?? null;
$email = $email ?? '';
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>ConectaEduca | Recuperar senha</title>
  <link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
  <header class="site-header">
    <div class="container navbar">
      <a class="brand" href="/index.php">
        <span class="brand-mark">CE</span>
        <span>ConectaEduca</span>
      </a>
      <nav class="nav-links">
        <a class="nav-link" href="/index.php">Início</a>
        <a class="nav-link" href="/cadastro_usuario.php">Cadastro</a>
      </nav>
    </div>
  </header>

  <main class="auth-wrap">
    <div class="container auth-grid">
      <section class="panel">
        <span class="eyebrow">Recuperação de acesso</span>
        <h1>Esqueceu sua senha?</h1>
        <p class="lead">
          Informe o e-mail da conta. Se ela puder ser recuperada,
          enviaremos um link temporário para criar uma nova senha.
        </p>
        <p>
          Por segurança, a resposta desta página não informa se um
          endereço está ou não cadastrado no ConectaEduca.
        </p>
      </section>

      <section class="auth-card">
        <h2>Solicitar recuperação</h2>

        <?php if (is_string($message) && $message !== ''): ?>
          <div class="notice">
            <?= htmlspecialchars($message, ENT_QUOTES | ENT_HTML5, 'UTF-8') ?>
          </div>
        <?php endif; ?>

        <?php if (is_string($error) && $error !== ''): ?>
          <div class="notice">
            <?= htmlspecialchars($error, ENT_QUOTES | ENT_HTML5, 'UTF-8') ?>
          </div>
        <?php endif; ?>

        <form action="/esqueci-senha.php" method="post">
          <?= Csrf::inputField() ?>

          <div class="form-grid">
            <div class="form-group full">
              <label for="email">E-mail</label>
              <input
                type="email"
                id="email"
                name="email"
                value="<?= htmlspecialchars((string) $email, ENT_QUOTES | ENT_HTML5, 'UTF-8') ?>"
                maxlength="190"
                autocomplete="email"
                required
                autofocus>
            </div>
          </div>

          <div class="hero-actions">
            <button class="button" type="submit">Enviar instruções</button>
            <a class="button-outline" href="/login.php">Voltar ao login</a>
          </div>
        </form>
      </section>
    </div>
  </main>
</body>
</html>
