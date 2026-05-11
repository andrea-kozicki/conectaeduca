<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use RuntimeException;

final class Secrets
{
    public static function get(string $key): string
    {
        return Env::required($key);
    }

    public static function optional(string $key, ?string $default = null): ?string
    {
        return Env::get($key, $default);
    }

    public static function filePath(string $envKey): string
    {
        $path = Env::required($envKey);

        if (!str_starts_with($path, '/')) {
            $path = Env::rootPath($path);
        }

        if (!is_readable($path)) {
            throw new RuntimeException("Arquivo secreto não encontrado ou sem permissão de leitura: {$envKey}");
        }

        return $path;
    }

    public static function fileContents(string $envKey): string
    {
        $path = self::filePath($envKey);
        $contents = file_get_contents($path);

        if ($contents === false || $contents === '') {
            throw new RuntimeException("Não foi possível ler o segredo informado em {$envKey}");
        }

        return $contents;
    }
}