<?php
declare(strict_types=1);

use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\OutputEncoder as e;

$currentUser = class_exists(Authorization::class) ? Authorization::user() : null;
$isLoggedIn = $currentUser !== null;
$currentRole = $currentUser['role'] ?? null;

$roleLabels = [
    'usuario' => 'Usuário',
    'empresa' => 'Empresa',
    'admin' => 'Admin',
];

$displayName = '';

if ($isLoggedIn) {
    $displayName = trim((string) ($currentUser['nome'] ?? ''));

    if ($displayName === '') {
        $displayName = trim((string) ($currentUser['email'] ?? 'Usuária'));
    }
}

$displayRole = $roleLabels[$currentRole] ?? (string) $currentRole;
?>
<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ConectaEduca</title>
    <link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
<header class="site-header">
    <div class="container navbar">
        <a class="brand" href="/index.php" aria-label="ConectaEduca - página inicial">
            <span class="brand-mark">CE</span>
            <span>ConectaEduca</span>
        </a>

        <nav class="nav-links" aria-label="Navegação principal">
            <a class="nav-link" href="/index.php">Início</a>
            <a class="nav-link" href="/api/oportunidades.php">Oportunidades</a>

            <?php if ($isLoggedIn): ?>
                <a class="nav-link" href="/dashboard.php">Dashboard</a>
                <a class="nav-link" href="/perfil.php">Perfil</a>
                <a class="nav-link" href="/api/inscricoes.php">Minhas inscrições</a>

                <?php if ($currentRole !== 'empresa'): ?>
                    <a class="nav-link" href="/favoritos.php">Favoritos</a>
                <?php endif; ?>

                <?php if (in_array($currentRole, ['empresa', 'admin'], true)): ?>
                    <a class="nav-link" href="/empresa/oportunidades.php">Gerenciar oportunidades</a>
                    <a class="nav-link" href="/empresa/inscricoes.php">Inscrições recebidas</a>
                <?php endif; ?>

                <?php if ($currentRole === 'admin'): ?>
                    <a class="nav-link" href="/admin/relatorio.php">Relatórios</a>
                <?php endif; ?>

                <span
                    class="session-chip"
                    title="<?= e::attr((string) ($currentUser['email'] ?? '')) ?>"
                >
                    <span class="session-chip-name">
                        <?= e::html($displayName) ?>
                    </span>
                    <span class="session-chip-role">
                        <?= e::html($displayRole) ?>
                    </span>
                </span>

                <a class="button-outline" href="/logout.php">Sair</a>
            <?php else: ?>
                <span class="session-chip session-chip-guest">
                    Não autenticada
                </span>

                <a class="button-outline" href="/login.php?acao=cognito">Entrar</a>
                <a class="button" href="/cadastro_usuario.php">Criar conta</a>
            <?php endif; ?>
        </nav>
    </div>
</header>