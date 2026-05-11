<?php
declare(strict_types=1);

require_once __DIR__ . '/../api/bootstrap.php';

use ConectaEduca\Controller\AuthController;
use ConectaEduca\Core\View;

$acao = $_GET['acao'] ?? '';

if ($acao === 'cognito') {
    $controller = new AuthController();
    $controller->login();
    exit;
}

View::render('auth/login');