<?php
declare(strict_types=1);

require_once __DIR__ . "/../../api/bootstrap.php";

use ConectaEduca\Controller\AuditoriaController;

$controller = new AuditoriaController();
$controller->index();
