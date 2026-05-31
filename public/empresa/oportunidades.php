<?php
declare(strict_types=1);

require_once __DIR__ . '/../../api/bootstrap.php';

use ConectaEduca\Controller\OportunidadeController;

$controller = new OportunidadeController();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $controller->processarGestaoEmpresa();
    exit;
}

$controller->gerenciarEmpresa();