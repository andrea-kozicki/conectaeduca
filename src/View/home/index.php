<?php
/** @var array<int, array<string, mixed>> $oportunidadesDestaque */
$oportunidadesDestaque = $oportunidadesDestaque ?? [];

function e_home(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ConectaEduca | Início</title>
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
        <a class="nav-link" href="#como-funciona">Como funciona</a>
        <a class="nav-link" href="#oportunidades-publicas">Oportunidades</a>
        <a class="button-outline" href="login.php">Entrar</a>
        <a class="button" href="cadastro_usuario.php">Criar conta</a>
      </nav>
    </div>
  </header>

  <main>
    <section class="hero">
      <div class="container hero-grid">
        <div class="hero-card">
          <span class="eyebrow">Centralização de oportunidades educacionais</span>
          <h1>ConectaEduca reúne cursos, bolsas, oficinas e capacitações em um único ambiente.</h1>
          <p class="lead">O sistema foi pensado para reduzir barreiras de acesso à informação, apoiando estudantes, pessoas em transição de carreira e perfis com menos acesso a redes de oportunidade.</p>
          <div class="hero-actions">
            <a class="button" href="cadastro_usuario.php">Criar conta de usuário</a>
            <a class="button-secondary" href="login.php">Já tenho conta</a>
          </div>
          <div class="badge-row">
            <span class="badge">Cursos</span>
            <span class="badge">Bolsas</span>
            <span class="badge">Oficinas</span>
            <span class="badge">Eventos</span>
          </div>
        </div>

        <aside class="hero-aside">
          <div class="stat-card">
            <div class="stat-label">Fluxo de uso</div>
            <div class="stat-number stat-text">Visitantes consultam oportunidades públicas; usuários se inscrevem; empresas gerenciam vagas; administradores acompanham o sistema.</div>
            <p class="muted">A interface separa os fluxos de visitante, usuário, empresa e administrador, com controle de acesso aplicado no backend.</p>
          </div>
          <div class="stat-card">
            <div class="stat-label">Segurança integrada</div>
            <div class="stat-number stat-text">Login com Cognito, MFA, perfis e criptografia</div>
            <p class="muted">Fluxos sensíveis usam validação de entrada, CSRF, autenticação pelo Amazon Cognito, MFA e criptografia híbrida quando aplicável.</p>
          </div>
        </aside>
      </div>
    </section>

    <section class="section" id="como-funciona">
      <div class="container">
        <h2>Como o sistema se organiza</h2>
        <p class="lead">A home pública apresenta a proposta do projeto e dá acesso às oportunidades disponíveis. O cadastro e o login ficam em fluxos separados, com autenticação via Amazon Cognito e controle de acesso por perfil.</p>
        <div class="cards">
          <article class="info-card">
            <div class="info-icon">1</div>
            <h3>Visitante</h3>
            <p class="muted">Consulta oportunidades e entende a proposta do sistema antes de criar conta.</p>
          </article>
          <article class="info-card">
            <div class="info-icon">2</div>
            <h3>Usuário</h3>
            <p class="muted">Cria conta, salva favoritos, acompanha inscrições e acessa oportunidades de estudo.</p>
          </article>
          <article class="info-card">
            <div class="info-icon">3</div>
            <h3>Segurança</h3>
            <p class="muted">A autenticação usa Amazon Cognito com MFA, controle de perfis no backend e criptografia em fluxos sensíveis.</p>
          </article>
        </div>
      </div>
    </section>

  
  <section class="section" id="oportunidades-publicas">
    <div class="container">
      <div class="section-heading">
        <span class="eyebrow">Oportunidades públicas</span>
        <h2>Oportunidades em destaque para visitantes</h2>
        <p class="lead">Estas oportunidades publicadas podem ser consultadas sem login. Para se inscrever, é necessário criar uma conta.</p>
      </div>

      <?php if (!empty($oportunidadesDestaque)): ?>
        <div class="cards">
          <?php foreach ($oportunidadesDestaque as $oportunidade): ?>
            <?php $oportunidadeId = (int) ($oportunidade['id'] ?? 0); ?>
            <article class="info-card">
              <div class="info-icon">CE</div>
              <h3><?= e_home($oportunidade['titulo'] ?? 'Oportunidade educacional') ?></h3>
              <p class="muted">
                <?= e_home(mb_strimwidth((string) ($oportunidade['descricao'] ?? 'Oportunidade publicada no ConectaEduca.'), 0, 180, '...')) ?>
              </p>
              <div class="badge-row">
                <?php if (!empty($oportunidade['tipo_oportunidade'])): ?>
                  <span class="badge"><?= e_home($oportunidade['tipo_oportunidade']) ?></span>
                <?php endif; ?>
                <?php if (!empty($oportunidade['modalidade'])): ?>
                  <span class="badge"><?= e_home($oportunidade['modalidade']) ?></span>
                <?php endif; ?>
                <?php if (!empty($oportunidade['empresa_nome'])): ?>
                  <span class="badge"><?= e_home($oportunidade['empresa_nome']) ?></span>
                <?php endif; ?>
              </div>

              <?php if ($oportunidadeId > 0): ?>
                <div class="inline-actions">
                  <a class="button-outline" href="/oportunidades.php?id=<?= e_home($oportunidadeId) ?>">
                    Ver detalhes
                  </a>
                </div>
              <?php endif; ?>
            </article>
          <?php endforeach; ?>
        </div>
      <?php else: ?>
        <div class="panel">
          <p class="lead">Ainda não há oportunidades publicadas para exibição pública.</p>
          <p class="muted">Cadastre uma empresa, publique oportunidades e esta seção será preenchida automaticamente.</p>
        </div>
      <?php endif; ?>

      <div class="inline-actions">
        <a class="button" href="cadastro_usuario.php">Criar conta para se inscrever</a>
        <a class="button-outline" href="login.php">Já tenho conta</a>
      </div>
    </div>
  </section>

  <section class="section" id="publico">
      <div class="container">
        <div class="banner panel">
          <div>
            <h2>Para visitantes e participantes</h2>
            <p class="lead">Visitantes podem conhecer o projeto e visualizar oportunidades públicas antes de criar uma conta. Usuários cadastrados podem salvar favoritos, acompanhar inscrições e acessar o dashboard autenticado.</p>
          </div>
          <div class="inline-actions">
            <a class="button" href="cadastro_usuario.php">Abrir cadastro</a>
            <a class="button-outline" href="login.php">Abrir login</a>
          </div>
        </div>
      </div>
    </section>
  </main>

  <footer class="page-footer">
    <div class="container">ConectaEduca · Projeto acadêmico com Cognito, MFA, CSRF, criptografia híbrida e requisitos OWASP ASVS.</div>
  </footer>
</body>
</html>
