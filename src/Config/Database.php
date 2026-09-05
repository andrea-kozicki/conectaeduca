<?php
declare(strict_types=1);

namespace ConectaEduca\Config;

use ConectaEduca\Security\Secrets;
use PDO;
use PDOException;
use RuntimeException;

final class Database
{
    private static ?PDO $connection = null;

    public static function connect(): PDO
    {
        if (self::$connection instanceof PDO) {
            return self::$connection;
        }

        Env::load();

        $host = Env::get('DB_HOST', '127.0.0.1');
        $port = Env::get('DB_PORT', '3306');
        $name = Env::required('DB_NAME');
        $user = Env::required('DB_USER');
        $pass = Secrets::optional('DB_PASS', '') ?? '';
        $charset = Env::get('DB_CHARSET', 'utf8mb4');

        $dsn = "mysql:host={$host};port={$port};dbname={$name};charset={$charset}";

        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ];

        $sslCa = Env::get('DB_SSL_CA');
        if ($sslCa !== null) {
            if (!is_readable($sslCa)) {
                throw new RuntimeException('CA TLS do banco de dados não está legível.');
            }

            $options[PDO::MYSQL_ATTR_SSL_CA] = $sslCa;
            $options[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] =
                Env::bool('DB_SSL_VERIFY_SERVER_CERT', true);
        }

        try {
            self::$connection = new PDO($dsn, $user, $pass, $options);

            return self::$connection;
        } catch (PDOException $e) {
            error_log('[DATABASE_ERROR] ' . $e->getMessage());

            throw new RuntimeException('Erro ao conectar ao banco de dados.');
        }
    }
}
