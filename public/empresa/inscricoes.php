<?php
declare(strict_types=1);

require_once __DIR__ . '/../../api/bootstrap.php';

use ConectaEduca\Controller\InscricaoController;

$controller = new InscricaoController();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $controller->atualizarStatusEmpresa();
    exit;
}

$controller->recebidasEmpresa();