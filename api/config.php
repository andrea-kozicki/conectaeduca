<?php
declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use Dotenv\Dotenv;

(static function (): void {
    $envDir = __DIR__ . '/../';
    if (is_file($envDir . '.env')) {
        Dotenv::createImmutable($envDir)->safeLoad();
    }
})();

function envValue(string $key, ?string $default = null): ?string
{
    $value = $_ENV[$key] ?? getenv($key);
    if ($value === false || $value === null || $value === '') {
        return $default;
    }
    return (string) $value;
}

function getDatabaseConnection(): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $dbName   = envValue('DB_NAME');
    $dbUser   = envValue('DB_USER');
    $dbPass   = envValue('DB_PASS', '');
    $dbSocket = envValue('DB_SOCKET');
    $dbHost   = envValue('DB_HOST', '127.0.0.1');
    $dbPort   = envValue('DB_PORT', '3306');

    if (!$dbName || !$dbUser) {
        error_log('Configuração do banco incompleta: DB_NAME ou DB_USER ausente.');
        throw new RuntimeException('Configuração do banco incompleta.');
    }

    $dsn = $dbSocket
        ? sprintf('mysql:dbname=%s;unix_socket=%s;charset=utf8mb4', $dbName, $dbSocket)
        : sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $dbHost, $dbPort, $dbName);

    try {
        $pdo = new PDO($dsn, $dbUser, $dbPass, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (PDOException $e) {
        error_log('Erro de conexão com o banco: ' . $e->getMessage());
        throw new RuntimeException('Falha de conexão com o banco.');
    }

    return $pdo;
}
