<?php
declare(strict_types=1);

require_once __DIR__ . '/../bootstrap/app.php';

use ConectaEduca\Controller\AuthController;

$controller = new AuthController();
$controller->logout();