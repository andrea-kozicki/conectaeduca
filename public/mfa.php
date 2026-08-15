<?php

declare(strict_types=1);

require_once __DIR__ . '/../api/bootstrap.php';

use ConectaEduca\Controller\MfaController;

$controller = new MfaController();

$method = strtoupper(
    $_SERVER['REQUEST_METHOD'] ?? 'GET'
);

if ($method === 'POST') {
    $controller->validarDesafio();
    exit;
}

$controller->mostrarDesafio();
