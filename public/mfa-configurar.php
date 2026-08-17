<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\MfaController;

$controller = new MfaController();

$method = strtoupper(
    $_SERVER['REQUEST_METHOD'] ?? 'GET'
);

if ($method === 'POST') {
    $controller->confirmarConfiguracao();
    exit;
}

$controller->mostrarConfiguracao();
