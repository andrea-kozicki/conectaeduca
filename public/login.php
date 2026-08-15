<?php

declare(strict_types=1);

require_once __DIR__ . '/../api/bootstrap.php';

use ConectaEduca\Controller\AuthController;

$controller = new AuthController();

$method = strtoupper(
    $_SERVER['REQUEST_METHOD'] ?? 'GET'
);

if ($method === 'POST') {
    $controller->autenticar();
    exit;
}

$controller->mostrarLogin();