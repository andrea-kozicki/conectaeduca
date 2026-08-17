<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\FavoritoController;
use ConectaEduca\Core\Response;

$controller = new FavoritoController();

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (in_array($method, ['GET', 'HEAD'], true)) {
    $controller->listar();
    exit;
}

if ($method === 'POST') {
    $controller->processar();
    exit;
}

Response::json([
    'ok' => false,
    'message' => 'Método não permitido.',
], 405);