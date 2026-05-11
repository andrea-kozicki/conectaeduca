<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Controller\RelatorioController;
use ConectaEduca\Core\Response;

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($method !== 'GET') {
    Response::json([
        'ok' => false,
        'message' => 'Método não permitido.',
    ], 405);
}

$controller = new RelatorioController();
$controller->json();