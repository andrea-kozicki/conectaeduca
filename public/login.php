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
      <a class="brand" href="index.php">
        <span class="brand-mark">CE</span>
        <span>ConectaEduca</span>
      </a>
      <nav class="nav-links">
        <a class="nav-link" href="index.php">Início</a>
        <a class="nav-link" href="cadastro_usuario.php">Cadastro</a>
      </nav>
    </div>
  </header>

  <main class="auth-wrap">
    <div class="container auth-grid">
      <section class="panel">
        <span class="eyebrow">Acesso ao sistema</span>
        <h1>Entre para visualizar oportunidades, favoritos e inscrições.</h1>
        <p class="lead">A tela já considera os perfis do DFD. Você pode manter um endpoint único de autenticação e, depois, encaminhar cada perfil para seu painel específico.</p>

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
        <p class="muted">Preencha suas credenciais para acessar o ConectaEduca.</p>

        <form action="/api/autenticar.php" method="post">
          <div class="form-grid">
            <div class="form-group full">
              <label for="tipo_conta">Tipo de conta</label>
              <select id="tipo_conta" name="tipo_conta">
                <option value="usuario">Usuário</option>
                <option value="empresa">Empresa</option>
                <option value="administrador">Administrador</option>
              </select>
            </div>

            <div class="form-group full">
              <label for="email">E-mail</label>
              <input id="email" name="email" type="email" placeholder="voce@email.com" required>
            </div>

            <div class="form-group full">
              <label for="senha">Senha</label>
              <input id="senha" name="senha" type="password" placeholder="Digite sua senha" required>
            </div>
          </div>

          <div class="inline-actions login-links">
            <a class="small-link" href="#">Esqueci minha senha</a>
            <a class="small-link" href="#">Entrar com 2FA</a>
          </div>

          <div class="hero-actions">
            <button class="button" type="submit">Entrar</button>
            <a class="button-outline" href="cadastro_usuario.php">Criar conta</a>
          </div>
        </form>

        <p class="auth-footer">Integração sugerida: o endpoint autentica, identifica o perfil e, se necessário, redireciona para a etapa de 2FA.</p>
      </section>
    </div>
  </main>
</body>
</html>
