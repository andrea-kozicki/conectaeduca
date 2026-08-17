<?php
declare(strict_types=1);

use ConectaEduca\Config\Env;
use ConectaEduca\Security\ErrorHandler;
use ConectaEduca\Security\SecureSession;
use ConectaEduca\Security\SecurityHeaders;

require_once __DIR__ . '/../vendor/autoload.php';

Env::load();

$debug = Env::bool('APP_DEBUG', false);

ErrorHandler::register($debug);
SecurityHeaders::apply();
SecureSession::start();