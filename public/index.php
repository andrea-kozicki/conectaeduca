<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Config\Database;
use ConectaEduca\Core\View;
use ConectaEduca\Service\OportunidadeService;

$oportunidadesDestaque = [];

try {
    $service = new OportunidadeService(Database::connect());
    $oportunidadesDestaque = array_slice($service->listarPublicas(), 0, 3);
} catch (Throwable $e) {
    error_log('[HOME_OPORTUNIDADES_ERROR] ' . $e->getMessage());
    $oportunidadesDestaque = [];
}

View::render('home/index', [
    'oportunidadesDestaque' => $oportunidadesDestaque,
]);
