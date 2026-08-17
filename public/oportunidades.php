<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\OportunidadeController;

$controller = new OportunidadeController();

if (isset($_GET['id']) && trim((string) $_GET['id']) !== '') {
    $controller->detalhe();
    exit;
}

$controller->listar();
