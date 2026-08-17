<?php
declare(strict_types=1);

require_once __DIR__ . '/../../bootstrap/app.php';

use ConectaEduca\Controller\OportunidadeController;
use ConectaEduca\Core\Response;

$controller = new OportunidadeController();

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (in_array($method, ['GET', 'HEAD'], true)) {
    if (isset($_GET['id'])) {
        $controller->detalhe();
        exit;
    }

    $controller->listar();
    exit;
}

if ($method === 'POST') {
    $controller->criar();
    exit;
}

Response::json([
    'ok' => false,
    'message' => 'Método não permitido.',
], 405);