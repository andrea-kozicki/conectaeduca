<?php
declare(strict_types=1);

use ConectaEduca\Security\Authorization;

$isLoggedIn = class_exists(Authorization::class) && Authorization::check();
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
                <a class="button-outline" href="/logout.php">Sair</a>
            <?php else: ?>
                <a class="button-outline" href="/login.php?acao=cognito">Entrar</a>
                <a class="button" href="/cadastro_usuario.php">Criar conta</a>
            <?php endif; ?>
        </nav>
    </div>
</header>