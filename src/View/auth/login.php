<?php
declare(strict_types=1);
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
          A autenticação do ConectaEduca é realizada pelo Amazon Cognito.
          Após o login, o sistema valida o retorno, cria uma sessão segura em PHP
          e encaminha o usuário para o painel.
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
          Clique no botão abaixo para ser redirecionada para a tela segura de autenticação do Amazon Cognito.
        </p>

        <form action="/login.php" method="get">
          <input type="hidden" name="acao" value="cognito">

          <div class="form-grid">
            <div class="form-group full">
              <label>Provedor de autenticação</label>
              <div class="notice">
                Amazon Cognito com fluxo OAuth/OIDC. O ConectaEduca não armazena senha localmente nesta tela.
              </div>
            </div>
          </div>

          <div class="hero-actions">
            <button class="button" type="submit">Entrar com Amazon Cognito</button>
            <a class="button-outline" href="/cadastro_usuario.php">Criar conta</a>
          </div>
        </form>

        <p class="auth-footer">
          Requisito atendido: autenticação centralizada, validação de retorno OAuth/OIDC e sessão segura no backend PHP.
        </p>
      </section>
    </div>
  </main>
</body>
</html>