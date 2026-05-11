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
        <a class="nav-link" href="#publico">Público</a>
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
            <div class="stat-label">Fluxo do DFD</div>
            <div class="stat-number stat-text">Visitante consulta, usuário se cadastra, empresa gerencia e administrador supervisiona.</div>
            <p class="muted">A interface inicial foi organizada para refletir essa separação de papéis sem misturar os fluxos.</p>
          </div>
          <div class="stat-card">
            <div class="stat-label">Módulo da RA2</div>
            <div class="stat-number stat-text">Cadastro criptografado de usuário</div>
            <p class="muted">Os dados do formulário podem ser cifrados no navegador antes do envio ao endpoint PHP de processamento.</p>
          </div>
        </aside>
      </div>
    </section>

    <section class="section" id="como-funciona">
      <div class="container">
        <h2>Como o sistema se organiza</h2>
        <p class="lead">A home pública apresenta a proposta do projeto, enquanto o cadastro e o login ficam em telas separadas para facilitar a navegação e a futura integração com o backend.</p>
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
            <p class="muted">O cadastro foi desenhado como ponto de entrada do módulo de criptografia cliente-servidor.</p>
          </article>
        </div>
      </div>
    </section>

    <section class="section" id="publico">
      <div class="container">
        <div class="banner panel">
          <div>
            <h2>Paleta visual baseada na apresentação</h2>
            <p class="lead">Fundo claro com creme suave, verde-turquesa como cor principal e laranja/terracota como apoio visual, mantendo um aspecto acolhedor e institucional.</p>
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
    <div class="container">ConectaEduca · Protótipo inicial de interface em PHP</div>
  </footer>
</body>
</html>
