<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Controller\InscricaoController;
use ConectaEduca\Core\Response;

$controller = new InscricaoController();

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$action = $_GET['action'] ?? $_POST['action'] ?? '';

if ($method === 'GET') {
    $controller->minhas();
    exit;
}

if ($method === 'POST' && $action === 'cancelar') {
    $controller->cancelar();
    exit;
}

if ($method === 'POST' && $action === 'atualizar_status') {
    $controller->atualizarStatus();
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