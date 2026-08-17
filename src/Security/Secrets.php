<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use RuntimeException;

final class Secrets
{
    /**
     * Retorna um segredo obrigatório.
     *
     * Ordem de resolução:
     * 1. VARIAVEL diretamente no ambiente;
     * 2. VARIAVEL_FILE apontando para um arquivo montado em runtime.
     *
     * Isso permite desenvolvimento local com .env e deployment com secrets
     * montados, por exemplo em /run/secrets, sem duplicar código de aplicação.
     */
    public static function get(string $key): string
    {
        $value = Env::get($key);

        if ($value !== null && $value !== '') {
            return $value;
        }

        $fileKey = $key . '_FILE';
        $file = Env::get($fileKey);

        if ($file === null || trim($file) === '') {
            throw new RuntimeException(
                "Segredo obrigatório ausente: configure {$key} ou {$fileKey}"
            );
        }

        return self::readSecretValueFromPath($file, $fileKey);
    }

    public static function optional(string $key, ?string $default = null): ?string
    {
        $value = Env::get($key);

        if ($value !== null && $value !== '') {
            return $value;
        }

        $fileKey = $key . '_FILE';
        $file = Env::get($fileKey);

        if ($file === null || trim($file) === '') {
            return $default;
        }

        return self::readSecretValueFromPath($file, $fileKey);
    }

    /**
     * Resolve o caminho apontado por uma variável de ambiente.
     * Caminhos relativos são resolvidos a partir da raiz do projeto.
     */
    public static function filePath(string $envKey): string
    {
        return self::resolvePath(Env::required($envKey), $envKey);
    }

    /**
     * Lê um arquivo cuja localização é informada por uma variável de ambiente.
     * Útil para material criptográfico como chaves PEM.
     */
    public static function fileContents(string $envKey): string
    {
        $path = self::filePath($envKey);
        $contents = file_get_contents($path);

        if ($contents === false || $contents === '') {
            throw new RuntimeException("Não foi possível ler o segredo informado em {$envKey}");
        }

        return $contents;
    }

    private static function readSecretValueFromPath(string $path, string $envKey): string
    {
        $resolved = self::resolvePath($path, $envKey);
        $contents = file_get_contents($resolved);

        if ($contents === false) {
            throw new RuntimeException("Não foi possível ler o segredo informado em {$envKey}");
        }

        // Docker/Compose secrets e arquivos criados por echo normalmente terminam
        // com uma quebra de linha. Removemos somente CR/LF finais, preservando
        // outros caracteres que podem fazer parte legitimamente do segredo.
        $contents = rtrim($contents, "\r\n");

        if ($contents === '') {
            throw new RuntimeException("O segredo informado em {$envKey} está vazio");
        }

        return $contents;
    }

    private static function resolvePath(string $path, string $envKey): string
    {
        $path = trim($path);

        if ($path === '') {
            throw new RuntimeException("Caminho de segredo vazio em {$envKey}");
        }

        if (!self::isAbsolutePath($path)) {
            $path = Env::rootPath($path);
        }

        if (!is_file($path) || !is_readable($path)) {
            throw new RuntimeException(
                "Arquivo secreto não encontrado ou sem permissão de leitura: {$envKey}"
            );
        }

        return $path;
    }

    private static function isAbsolutePath(string $path): bool
    {
        if (str_starts_with($path, '/')) {
            return true;
        }

        // Compatibilidade com caminhos absolutos do Windows usados em WSL/Git Bash.
        return preg_match('/^[A-Za-z]:[\\\\\/]/', $path) === 1;
    }
}
