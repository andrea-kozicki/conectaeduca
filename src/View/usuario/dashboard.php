<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Área autenticada</span>
            <h1>Dashboard</h1>
            <p class="lead">
                Você está autenticada no ConectaEduca. Aqui ficam seus dados principais e atalhos do sistema.
            </p>
        </section>

        <section class="panel">
            <div class="dashboard-grid">
                <div class="profile-card">
                    <strong>ID</strong>
                    <span><?= e::html((string) ($user['id'] ?? '')) ?></span>
                </div>

                <div class="profile-card">
                    <strong>Perfil</strong>
                    <span><?= e::html($user['role'] ?? '') ?></span>
                </div>

                <div class="profile-card">
                    <strong>Nome</strong>
                    <span><?= e::html($user['nome'] ?? '') ?></span>
                </div>

                <div class="profile-card">
                    <strong>E-mail</strong>
                    <span><?= e::html($user['email'] ?? '') ?></span>
                </div>
            </div>

            <div class="security-note">
                <strong>Autenticação segura:</strong>
                esta sessão foi criada após autenticação pelo Amazon Cognito com MFA.
            </div>

            <div class="inline-actions">
                <a class="button" href="/api/inscricoes.php">Ver minhas inscrições</a>
                <a class="button-secondary" href="/api/oportunidades.php">Ver oportunidades</a>
                <a class="button-outline" href="/perfil.php">Editar perfil</a>
            </div>
        </section>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';