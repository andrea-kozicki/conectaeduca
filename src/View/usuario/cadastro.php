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
  <title>ConectaEduca | Cadastro</title>
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
        <span class="eyebrow">Cadastro</span>
        <h1>Escolha o tipo de conta para acessar o ConectaEduca.</h1>
        <p class="lead">
          A tela separa o cadastro de usuária/candidata e o cadastro de empresa para coletar apenas os dados
          compatíveis com cada papel da aplicação.
        </p>

        <div class="badge-row">
          <span class="badge">Usuária</span>
          <span class="badge">Empresa</span>
          <span class="badge">CSRF</span>
          <span class="badge">Criptografia híbrida</span>
          <span class="badge">Controle de acesso</span>
        </div>

        <div class="notice" style="margin-top:1.2rem;">
          O cadastro público permite apenas os papéis <strong>usuário</strong> e <strong>empresa</strong>.
          Contas administrativas não são criadas por autocadastro.
        </div>
      </section>

      <section class="auth-card">
        <h2>Cadastro</h2>
        <p class="muted">Primeiro escolha o tipo de conta. Depois preencha o formulário correspondente.</p>

        <div class="hero-actions" style="margin-bottom:1rem;">
          <button class="button" type="button" data-role-option="usuario" aria-pressed="true">
            Sou usuária/candidata
          </button>
          <button class="button-outline" type="button" data-role-option="empresa" aria-pressed="false">
            Sou empresa/organização
          </button>
        </div>

        <p id="textoTipoCadastro" class="help-text">
          Cadastro de usuária/candidata: informe seus dados pessoais para acompanhar oportunidades.
        </p>

        <div id="mensagem-retorno" class="feedback feedback-hidden" aria-live="polite"></div>

        <form id="cadastroForm" method="post" action="/api/processa_cadastro_usuario.php" data-encrypted-form="true" novalidate>
          <?= Csrf::inputField() ?>
          <input id="role" name="role" type="hidden" value="usuario">

          <div class="form-grid">
            <div class="form-group full">
              <label for="nome">Nome completo</label>
              <input id="nome" name="nome" type="text" maxlength="150" placeholder="Nome da pessoa responsável" required>
            </div>

            <div class="form-group full">
              <label for="email">E-mail</label>
              <input id="email" name="email" type="email" maxlength="180" placeholder="voce@email.com" required>
              <p class="help-text">Este e-mail será usado para identificar a conta local e o vínculo com o Cognito.</p>
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

            <div id="camposEmpresa" class="form-group full" hidden>
              <div class="notice">
                <strong>Dados da empresa</strong>
                <p class="help-text">
                  A empresa será criada já vinculada à pessoa responsável por esta conta.
                </p>

                <div class="form-grid">
                  <div class="form-group full">
                    <label for="razao_social">Razão social</label>
                    <input id="razao_social" name="razao_social" type="text" maxlength="180" placeholder="Razão social da empresa">
                  </div>

                  <div class="form-group full">
                    <label for="nome_fantasia">Nome fantasia</label>
                    <input id="nome_fantasia" name="nome_fantasia" type="text" maxlength="180" placeholder="Nome público da empresa">
                  </div>

                  <div class="form-group">
                    <label for="cnpj">CNPJ</label>
                    <input id="cnpj" name="cnpj" type="text" maxlength="18" placeholder="Somente números">
                  </div>

                  <div class="form-group">
                    <label for="area_atuacao">Área de atuação</label>
                    <input id="area_atuacao" name="area_atuacao" type="text" maxlength="120" placeholder="Educação, tecnologia, inclusão...">
                  </div>

                  <div class="form-group full">
                    <label for="descricao_empresa">Descrição</label>
                    <textarea
                      id="descricao_empresa"
                      name="descricao_empresa"
                      maxlength="1000"
                      placeholder="Descreva brevemente a empresa ou organização"
                    ></textarea>
                  </div>

                  <div class="form-group full">
                    <label for="site_url">Site</label>
                    <input id="site_url" name="site_url" type="url" maxlength="255" placeholder="https://exemplo.com.br">
                  </div>
                </div>
              </div>
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
            Ao prosseguir, os dados preenchidos serão protegidos por criptografia híbrida antes do envio
            ao servidor.
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