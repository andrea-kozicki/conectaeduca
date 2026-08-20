<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\PasswordResetController;

$controller = new PasswordResetController();

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($method === 'POST') {
    $controller->redefinir();
    exit;
}

$controller->mostrarRedefinicao();
