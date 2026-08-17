<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\FaleConoscoController;
use ConectaEduca\Core\Response;

$controller = new FaleConoscoController();

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (in_array($method, ['GET', 'HEAD'], true)) {
    $controller->formulario();
    exit;
}

if ($method === 'POST') {
    $controller->enviar();
    exit;
}

Response::json([
    'ok' => false,
    'message' => 'Método não permitido.',
], 405);