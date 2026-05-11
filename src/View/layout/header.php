<?php
declare(strict_types=1);

use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

$user = Authorization::user();
$csrfToken = Csrf::token();
?>
<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <title>ConectaEduca</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="<?= e::attr($csrfToken) ?>">
    <link rel="stylesheet" href="/assets/css/style.css">
</head>
<body>
<header>
    <h1>ConectaEduca</h1>

    <nav>
        <a href="/index.php">Início</a>
        <a href="/api/oportunidades.php">Oportunidades</a>

        <?php if ($user): ?>
            <a href="/dashboard.php">Dashboard</a>
            <a href="/api/inscricoes.php">Minhas inscrições</a>

            <?php if (($user['role'] ?? '') === 'admin'): ?>
                <a href="/admin/relatorio.php">Relatórios</a>
            <?php endif; ?>

            <a href="/logout.php">Sair</a>
        <?php else: ?>
            <a href="/cadastro_usuario.php">Cadastro</a>
            <a href="/login.php">Entrar com Cognito</a>
        <?php endif; ?>
    </nav>
</header>

<main>