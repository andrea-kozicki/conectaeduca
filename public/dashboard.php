<?php
declare(strict_types=1);

require_once __DIR__ . '/../api/bootstrap.php';

use ConectaEduca\Controller\UsuarioController;

$controller = new UsuarioController();
$controller->dashboard();