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

  <main class="auth-wrap cadastro-page">
    <div class="container cadastro-shell">
      <section class="panel cadastro-hero">
        <div class="cadastro-hero-grid">
          <div>
            <span class="eyebrow">Cadastro</span>
            <h1>Crie sua conta no ConectaEduca.</h1>
            <p class="lead">
              Escolha como deseja usar a plataforma. O formulário será ajustado conforme o tipo de conta,
              evitando campos desnecessários e mantendo o vínculo correto entre perfil e permissões.
            </p>
          </div>

          <div class="cadastro-security-list" aria-label="Recursos de segurança do cadastro">
            <div>
              <strong>CSRF</strong>
              <span>Proteção contra envio não autorizado.</span>
            </div>
            <div>
              <strong>Criptografia híbrida</strong>
              <span>Dados protegidos antes do envio ao servidor.</span>
            </div>
            <div>
              <strong>Controle de acesso</strong>
              <span>Cadastro público limitado a usuária ou empresa.</span>
            </div>
          </div>
        </div>
      </section>

      <section class="auth-card cadastro-form-card">
        <div class="cadastro-card-header">
          <h2>Escolha o tipo de conta</h2>
          <p class="muted">Depois da escolha, preencha somente os dados necessários para esse papel.</p>

          <div class="cadastro-options" role="group" aria-label="Tipo de cadastro">
            <button class="cadastro-choice-card button" type="button" data-role-option="usuario" aria-pressed="true">
              <span class="choice-kicker">Usuária/candidata</span>
              <strong>Acompanhar oportunidades</strong>
              <span>Para favoritar vagas, acompanhar inscrições e receber notificações futuras.</span>
            </button>

            <button class="cadastro-choice-card button-outline" type="button" data-role-option="empresa" aria-pressed="false">
              <span class="choice-kicker">Empresa/organização</span>
              <strong>Publicar oportunidades</strong>
              <span>Para cadastrar uma organização, publicar oportunidades e gerenciar inscrições.</span>
            </button>
          </div>

          <p id="textoTipoCadastro" class="cadastro-selected-note">
            Cadastro de usuária/candidata: informe seus dados pessoais para acompanhar oportunidades.
          </p>
        </div>

        <div id="mensagem-retorno" class="feedback feedback-hidden" aria-live="polite"></div>

        <form id="cadastroForm" method="post" action="/api/processa_cadastro_usuario.php" data-encrypted-form="true" novalidate>
          <?= Csrf::inputField() ?>
          <input id="role" name="role" type="hidden" value="usuario">

          <section class="form-section">
            <div class="form-section-header">
              <span class="form-step">1</span>
              <div>
                <h3>Dados da pessoa responsável</h3>
                <p>Esses dados identificam quem acessará a conta.</p>
              </div>
            </div>

            <div class="form-grid">
              <div class="form-group full">
                <label for="nome">Nome completo</label>
                <input id="nome" name="nome" type="text" maxlength="150" placeholder="Seu nome completo" required>
              </div>

              <div class="form-group full">
                <label for="email">E-mail</label>
                <input id="email" name="email" type="email" maxlength="180" placeholder="voce@email.com" required>
                <p class="help-text">Este e-mail será usado para identificar a conta local e o vínculo com o Cognito.</p>
              </div>

              <div class="form-group">
                <label for="cpf">CPF</label>
                <input id="cpf" name="cpf" type="text" maxlength="14" inputmode="numeric" placeholder="Ex.: 12345678901" required>
              </div>

              <div class="form-group">
                <label for="telefone">Telefone</label>
                <input id="telefone" name="telefone" type="tel" maxlength="20" placeholder="(00) 00000-0000" required>
              </div>

              <div class="form-group">
                <label for="data_nascimento">Data de nascimento</label>
                <input id="data_nascimento" name="data_nascimento" type="date" required>
              </div>
            </div>
          </section>

          <section id="camposEmpresa" class="form-section form-section-empresa" hidden>
            <div class="form-section-header">
              <span class="form-step">2</span>
              <div>
                <h3>Dados da empresa</h3>
                <p>A empresa será criada já vinculada à pessoa responsável por esta conta.</p>
              </div>
            </div>

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
                <input id="cnpj" name="cnpj" type="text" maxlength="18" inputmode="numeric" placeholder="Ex.: 12345678000199">
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
          </section>

          <section class="form-section">
            <div class="form-section-header">
              <span class="form-step">3</span>
              <div>
                <h3>Segurança da conta</h3>
                <p>Crie uma senha com pelo menos 8 caracteres.</p>
              </div>
            </div>

            <div class="form-grid">
              <div class="form-group">
                <label for="senha">Senha</label>
                <input id="senha" name="senha" type="password" minlength="8" placeholder="Crie uma senha segura" required>
              </div>

              <div class="form-group">
                <label for="confirmarSenha">Confirmar senha</label>
                <input id="confirmarSenha" name="confirmarSenha" type="password" minlength="8" placeholder="Repita a senha" required>
              </div>
            </div>
          </section>

          <div class="cadastro-form-footer">
            <p class="security-note compact-note">
              Ao prosseguir, os dados preenchidos serão protegidos por criptografia híbrida antes do envio ao servidor.
            </p>

            <div class="hero-actions cadastro-actions">
              <button class="button" type="submit">Criar conta</button>
              <a class="button-outline" href="/login.php">Já tenho conta</a>
            </div>
          </div>
        </form>

        <p class="auth-footer cadastro-tech-note">
          Integração: <code>/api/processa_cadastro_usuario.php</code> e <code>/api/public_key.php</code>.
        </p>
      </section>
    </div>
  </main>

  <script src="/assets/js/csrf.js"></script>
  <script src="/assets/js/crypto-utils.js"></script>
  <script src="/assets/js/cadastro_usuario.js?v=20260606-empresa"></script>
</body>
</html>
