<?php
declare(strict_types=1);

namespace ConectaEduca\Core;

use RuntimeException;

final class View
{
    public static function render(string $view, array $data = []): void
    {
        $viewPath = dirname(__DIR__) . '/View/' . ltrim($view, '/') . '.php';

        if (!is_readable($viewPath)) {
            throw new RuntimeException("View não encontrada: {$view}");
        }

        extract($data, EXTR_SKIP);

        require $viewPath;
    }
}