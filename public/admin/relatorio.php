<?php
declare(strict_types=1);

require_once __DIR__ . '/../../bootstrap/app.php';

use ConectaEduca\Controller\RelatorioController;

$controller = new RelatorioController();
$controller->index();