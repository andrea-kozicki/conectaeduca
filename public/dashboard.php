<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\UsuarioController;

$controller = new UsuarioController();
$controller->dashboard();