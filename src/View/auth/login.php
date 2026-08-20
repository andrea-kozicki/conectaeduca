<?php

declare(strict_types=1);

use ConectaEduca\Security\Csrf;

$error = $error ?? null;
$email = $email ?? '';
$logoutSuccess = $logoutSuccess ?? false;
$passwordResetSuccess = $passwordResetSuccess ?? false;
?>
<!DOCTYPE html>
<html lang="pt-BR">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ConectaEduca | Login</title>
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
        <span class="eyebrow">Acesso ao sistema</span>
        <h1>Entre para visualizar oportunidades, favoritos e inscrições.</h1>
        <p class="lead">
          O acesso ao ConectaEduca utiliza autenticação local
          com credenciais protegidas por hash e sessão segura
          no servidor.
        </p>

        <div class="cards cards-single">
          <article class="info-card">
            <h3>Usuário</h3>
            <p class="muted">Consulta oportunidades, salva favoritos e acompanha inscrições.</p>
          </article>
          <article class="info-card">
            <h3>Empresa</h3>
            <p class="muted">Gerencia oportunidades e acompanha inscrições recebidas.</p>
          </article>
          <article class="info-card">
            <h3>Administrador</h3>
            <p class="muted">Supervisiona a base de usuários, oportunidades, inscrições e auditoria.</p>
          </article>
        </div>
      </section>

      <section class="auth-card">
        <h2>Login</h2>
        <p class="muted">
          Informe seu e-mail e sua senha para acessar o sistema.
        </p>

        <?php if ($logoutSuccess): ?>
          <div class="notice">
            Sessão encerrada com sucesso.
          </div>
        <?php endif; ?>

        <?php if ($passwordResetSuccess): ?>
          <div class="notice">
            Senha redefinida com sucesso. Você já pode entrar com a nova senha.
          </div>
        <?php endif; ?>

        <?php if (
          is_string($error) &&
          $error !== ''
        ): ?>
          <div class="notice">
            <?= htmlspecialchars(
              $error,
              ENT_QUOTES | ENT_HTML5,
              'UTF-8'
            ) ?>
          </div>
        <?php endif; ?>

        <form action="/login.php" method="post">

          <?= Csrf::inputField() ?>

          <div class="form-grid">

            <div class="form-group full">
              <label for="email">E-mail</label>

              <input
                type="email"
                id="email"
                name="email"
                value="<?= htmlspecialchars(
                          (string) $email,
                          ENT_QUOTES | ENT_HTML5,
                          'UTF-8'
                        ) ?>"
                maxlength="190"
                autocomplete="username"
                required>
            </div>

            <div class="form-group full">
              <label for="senha">Senha</label>

              <input
                type="password"
                id="senha"
                name="senha"
                autocomplete="current-password"
                required>

              <p class="muted">
                <a href="/esqueci-senha.php">Esqueceu sua senha?</a>
              </p>
            </div>

          </div>

          <div class="hero-actions">
            <button
              class="button"
              type="submit">
              Entrar
            </button>

            <a
              class="button-outline"
              href="/cadastro_usuario.php">
              Criar conta
            </a>
          </div>

        </form>

      </section>
    </div>
  </main>
</body>

</html>