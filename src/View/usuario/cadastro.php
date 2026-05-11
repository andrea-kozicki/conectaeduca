<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

$csrfToken = Csrf::token();
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ConectaEduca | Cadastro de Usuário</title>
  <meta name="csrf-token" content="<?= e::attr($csrfToken) ?>">
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
        <a class="nav-link" href="/login.php">Login</a>
      </nav>
    </div>
  </header>

  <main class="auth-wrap">
    <div class="container auth-grid">
      <section class="panel">
        <span class="eyebrow">Cadastro de usuário</span>
        <h1>Crie sua conta para acompanhar oportunidades educacionais.</h1>
        <p class="lead">
          Esta tela foi preparada para o fluxo da RA2. O formulário envia os dados ao endpoint de cadastro
          usando token CSRF e criptografia híbrida no navegador antes do processamento pelo servidor.
        </p>

        <div class="badge-row">
          <span class="badge">Nome</span>
          <span class="badge">E-mail</span>
          <span class="badge">CPF</span>
          <span class="badge">Telefone</span>
          <span class="badge">Senha</span>
        </div>

        <div class="notice" style="margin-top:1.2rem;">
          No fluxo proposto, o dado original é reunido em JSON, criptografado com AES no cliente
          e a chave AES é protegida com RSA usando a chave pública do servidor.
        </div>
      </section>

      <section class="auth-card">
        <h2>Cadastro</h2>
        <p class="muted">Preencha seus dados para acessar inscrições, favoritos e futuras notificações.</p>

        <div id="mensagem-retorno" class="feedback feedback-hidden" aria-live="polite"></div>

        <form id="cadastroForm" method="post" action="/api/processa_cadastro_usuario.php" novalidate>
          <?= Csrf::inputField() ?>

          <div class="form-grid">
            <div class="form-group full">
              <label for="nome">Nome completo</label>
              <input id="nome" name="nome" type="text" maxlength="120" placeholder="Seu nome completo" required>
            </div>

            <div class="form-group full">
              <label for="email">E-mail</label>
              <input id="email" name="email" type="email" maxlength="180" placeholder="voce@email.com" required>
            </div>

            <div class="form-group">
              <label for="cpf">CPF</label>
              <input id="cpf" name="cpf" type="text" maxlength="14" placeholder="Somente números" required>
            </div>

            <div class="form-group">
              <label for="telefone">Telefone</label>
              <input id="telefone" name="telefone" type="tel" maxlength="20" placeholder="(00) 00000-0000" required>
            </div>

            <div class="form-group">
              <label for="data_nascimento">Data de nascimento</label>
              <input id="data_nascimento" name="data_nascimento" type="date" required>
            </div>

            <div class="form-group">
              <label for="cep">CEP</label>
              <input id="cep" name="cep" type="text" maxlength="9" placeholder="00000-000" required>
            </div>

            <div class="form-group full">
              <label for="rua">Rua</label>
              <input id="rua" name="rua" type="text" maxlength="180" placeholder="Rua, avenida ou alameda" required>
            </div>

            <div class="form-group">
              <label for="numero">Número</label>
              <input id="numero" name="numero" type="text" maxlength="20" placeholder="Número" required>
            </div>

            <div class="form-group">
              <label for="cidade">Cidade</label>
              <input id="cidade" name="cidade" type="text" maxlength="120" placeholder="Cidade" required>
            </div>

            <div class="form-group">
              <label for="estado">Estado</label>
              <input id="estado" name="estado" type="text" maxlength="2" placeholder="UF" required>
            </div>

            <div class="form-group">
              <label for="senha">Senha</label>
              <input id="senha" name="senha" type="password" minlength="8" placeholder="Crie uma senha segura" required>
            </div>

            <div class="form-group">
              <label for="confirmarSenha">Confirmar senha</label>
              <input id="confirmarSenha" name="confirmarSenha" type="password" minlength="8" placeholder="Repita a senha" required>
            </div>
          </div>

          <p class="help-text">
            Ao prosseguir, seus dados de cadastro serão protegidos antes do envio ao servidor.
          </p>

          <div class="hero-actions">
            <button class="button" type="submit">Criar conta</button>
            <a class="button-outline" href="/login.php">Já tenho conta</a>
          </div>
        </form>

        <p class="auth-footer">
          Integração esperada:
          <code>/api/processa_cadastro_usuario.php</code> e <code>/api/public_key.php</code>.
        </p>
      </section>
    </div>
  </main>

  <script src="/assets/js/csrf.js"></script>
  <script src="/assets/js/crypto-utils.js"></script>
  <script src="/assets/js/cadastro_usuario.js"></script>
</body>
</html>