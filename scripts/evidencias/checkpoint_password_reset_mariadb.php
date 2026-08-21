<?php

declare(strict_types=1);

use ConectaEduca\Config\Database;
use ConectaEduca\Config\Env;
use ConectaEduca\Repository\PasswordResetRepository;
use ConectaEduca\Service\PasswordResetService;

require_once dirname(__DIR__, 2) . '/vendor/autoload.php';

final class PasswordResetMariaDbCheckpoint
{
    private int $ok = 0;
    private int $fail = 0;
    private ?int $fixtureUserId = null;
    private ?string $fixtureEmail = null;

    public function run(): int
    {
        $this->header();

        $environment = strtolower((string) Env::get('APP_ENV', 'development'));

        if ($environment === 'production') {
            $this->failure(
                'checkpoint recusado: APP_ENV=production'
            );

            return $this->finish();
        }

        $this->success('ambiente não-produtivo confirmado: ' . $environment);

        try {
            $pdo = Database::connect();
            $this->success('conexão PDO com o MariaDB estabelecida');

            $this->assertDatabaseIdentity($pdo);
            $this->createFixture($pdo);

            $repository = new PasswordResetRepository($pdo);
            $service = new PasswordResetService($repository);

            $this->exerciseTokenReplacement($pdo, $service);
            $this->exerciseTransactionalReset($pdo, $service);
        } catch (Throwable) {
            $this->failure(
                'checkpoint interrompido por erro interno'
            );
        } finally {
            $this->cleanupFixture();
        }

        return $this->finish();
    }

    private function assertDatabaseIdentity(PDO $pdo): void
    {
        $database = $pdo->query('SELECT DATABASE()')->fetchColumn();

        if ($database !== 'conectaeduca') {
            throw new RuntimeException(
                'banco inesperado; esperado conectaeduca'
            );
        }

        $this->success('banco alvo confirmado: conectaeduca');
    }

    private function createFixture(PDO $pdo): void
    {
        $suffix = bin2hex(random_bytes(8));
        $email = 'checkpoint-reset-' . $suffix . '@example.test';
        $initialPassword = $this->syntheticPassword();
        $passwordHash = password_hash(
            $initialPassword,
            PASSWORD_DEFAULT
        );

        if (!is_string($passwordHash) || $passwordHash === '') {
            throw new RuntimeException(
                'não foi possível criar o hash da senha sintética'
            );
        }

        $stmt = $pdo->prepare(
            "INSERT INTO usuarios
                (nome, email, role, senha_hash, conta_ativada)
             VALUES
                (:nome, :email, 'usuario', :senha_hash, 1)"
        );

        $stmt->execute([
            ':nome' => 'Checkpoint Recuperacao Senha',
            ':email' => $email,
            ':senha_hash' => $passwordHash,
        ]);

        $userId = (int) $pdo->lastInsertId();

        if ($userId < 1) {
            throw new RuntimeException(
                'usuário sintético não recebeu ID válido'
            );
        }

        $this->fixtureUserId = $userId;
        $this->fixtureEmail = $email;

        $this->success('usuário sintético criado para o checkpoint');
    }

    private function exerciseTokenReplacement(
        PDO $pdo,
        PasswordResetService $service
    ): void {
        $userId = $this->requireFixtureUserId();

        $first = $service->emitirParaUsuario($userId);
        $firstToken = $first['token'];
        $firstHash = hash('sha256', $firstToken);

        $this->assert(
            strlen($firstToken) === 43,
            'token puro possui formato Base64URL de 43 caracteres'
        );

        $row = $this->tokenRow($pdo, $firstHash);

        $this->assert(
            is_array($row),
            'primeiro token foi persistido pelo hash'
        );

        $this->assert(
            $row !== null && $row['token_hash'] === $firstHash,
            'banco contém SHA-256 do token emitido'
        );

        $this->assert(
            !$this->databaseContainsLiteralToken($pdo, $firstToken),
            'token puro não aparece em tokens_conta'
        );

        $second = $service->emitirParaUsuario($userId);
        $secondToken = $second['token'];
        $secondHash = hash('sha256', $secondToken);

        $firstAfterReplacement = $this->tokenRow($pdo, $firstHash);
        $secondRow = $this->tokenRow($pdo, $secondHash);

        $this->assert(
            $firstAfterReplacement !== null
                && $firstAfterReplacement['usado_em'] !== null,
            'nova emissão invalida o token anterior'
        );

        $this->assert(
            $secondRow !== null && $secondRow['usado_em'] === null,
            'token mais recente permanece ativo'
        );

        $this->assert(
            $service->usuarioDoTokenValido($firstToken) === null,
            'token substituído não é aceito pelo service'
        );

        $this->assert(
            $service->usuarioDoTokenValido($secondToken) === $userId,
            'token mais recente é reconhecido sem ser consumido'
        );

        $this->assert(
            $this->tokenRow($pdo, $secondHash)['usado_em'] === null,
            'consulta GET-style não consome o token válido'
        );
    }

    private function exerciseTransactionalReset(
        PDO $pdo,
        PasswordResetService $service
    ): void {
        $userId = $this->requireFixtureUserId();

        /*
         * O token puro não pode ser reconstruído a partir do hash. Emitimos
         * um novo token e mantemos apenas este valor em memória para exercer
         * o fluxo real até o consumo.
         */
        $issued = $service->emitirParaUsuario($userId);
        $token = $issued['token'];
        $tokenHash = hash('sha256', $token);

        $newPassword = $this->syntheticPassword();

        $resetUserId = $service->redefinirSenha(
            $token,
            $newPassword,
            $newPassword
        );

        $this->assert(
            $resetUserId === $userId,
            'redefinição transacional retorna o usuário esperado'
        );

        $stmt = $pdo->prepare(
            'SELECT senha_hash FROM usuarios WHERE id = :id LIMIT 1'
        );
        $stmt->execute([':id' => $userId]);
        $storedPasswordHash = $stmt->fetchColumn();

        $this->assert(
            is_string($storedPasswordHash)
                && password_verify($newPassword, $storedPasswordHash),
            'nova senha foi persistida como password_hash válido'
        );

        $this->assert(
            $storedPasswordHash !== $newPassword,
            'senha nova não foi persistida em texto puro'
        );

        $tokenAfterReset = $this->tokenRow($pdo, $tokenHash);

        $this->assert(
            $tokenAfterReset !== null
                && $tokenAfterReset['usado_em'] !== null,
            'token utilizado foi marcado como consumido'
        );

        $activeCount = $pdo->prepare(
            "SELECT COUNT(*)
             FROM tokens_conta
             WHERE usuario_id = :usuario_id
               AND tipo_token = 'recuperacao_senha'
               AND usado_em IS NULL"
        );
        $activeCount->execute([':usuario_id' => $userId]);

        $this->assert(
            (int) $activeCount->fetchColumn() === 0,
            'nenhum token de recuperação do usuário permanece ativo'
        );

        $replayPassword = $this->syntheticPassword();
        $replay = $service->redefinirSenha(
            $token,
            $replayPassword,
            $replayPassword
        );

        $this->assert(
            $replay === null,
            'replay do token consumido é rejeitado'
        );

        $stmt->execute([':id' => $userId]);
        $hashAfterReplay = $stmt->fetchColumn();

        $this->assert(
            is_string($hashAfterReplay)
                && password_verify($newPassword, $hashAfterReplay),
            'tentativa de replay não altera a senha já definida'
        );
    }

    /**
     * @return array{token_hash:string,usado_em:?string}|null
     */
    private function tokenRow(PDO $pdo, string $tokenHash): ?array
    {
        $stmt = $pdo->prepare(
            "SELECT token_hash, usado_em
             FROM tokens_conta
             WHERE token_hash = :token_hash
               AND tipo_token = 'recuperacao_senha'
             LIMIT 1"
        );
        $stmt->execute([':token_hash' => $tokenHash]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!is_array($row)) {
            return null;
        }

        return [
            'token_hash' => (string) $row['token_hash'],
            'usado_em' => $row['usado_em'] === null
                ? null
                : (string) $row['usado_em'],
        ];
    }

    private function databaseContainsLiteralToken(
        PDO $pdo,
        string $token
    ): bool {
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM tokens_conta WHERE token_hash = :literal'
        );
        $stmt->execute([':literal' => $token]);

        return (int) $stmt->fetchColumn() > 0;
    }

    private function requireFixtureUserId(): int
    {
        if ($this->fixtureUserId === null || $this->fixtureUserId < 1) {
            throw new RuntimeException(
                'fixture de usuário ainda não foi criada'
            );
        }

        return $this->fixtureUserId;
    }

    private function cleanupFixture(): void
    {
        if ($this->fixtureUserId === null || $this->fixtureEmail === null) {
            return;
        }

        try {
            $pdo = Database::connect();
            $stmt = $pdo->prepare(
                'DELETE FROM usuarios WHERE id = :id AND email = :email'
            );
            $stmt->execute([
                ':id' => $this->fixtureUserId,
                ':email' => $this->fixtureEmail,
            ]);

            if ($stmt->rowCount() !== 1) {
                $this->failure(
                    'fixture não pôde ser removida de forma confirmada'
                );
                return;
            }

            $checkUser = $pdo->prepare(
                'SELECT COUNT(*) FROM usuarios WHERE id = :id'
            );
            $checkUser->execute([':id' => $this->fixtureUserId]);

            $checkTokens = $pdo->prepare(
                'SELECT COUNT(*) FROM tokens_conta WHERE usuario_id = :id'
            );
            $checkTokens->execute([':id' => $this->fixtureUserId]);

            if (
                (int) $checkUser->fetchColumn() === 0
                && (int) $checkTokens->fetchColumn() === 0
            ) {
                $this->success(
                    'fixture removida e ON DELETE CASCADE confirmado'
                );
            } else {
                $this->failure(
                    'resíduo da fixture detectado após limpeza'
                );
            }
        } catch (Throwable) {
            $this->failure(
                'falha interna durante a limpeza da fixture'
            );
        }
    }


    private function syntheticPassword(): string
    {
        return 'T!' . bin2hex(random_bytes(18)) . 'aA7';
    }

    private function assert(bool $condition, string $message): void
    {
        if ($condition) {
            $this->success($message);
            return;
        }

        throw new RuntimeException($message);
    }

    private function success(string $message): void
    {
        ++$this->ok;
        echo "OK          {$message}\n";
    }

    private function failure(string $message): void
    {
        ++$this->fail;
        echo "FALHA       {$message}\n";
    }

    private function header(): void
    {
        echo "======================================================================\n";
        echo " CONECTAEDUCA - CHECKPOINT RECUPERACAO DE SENHA / MARIADB REAL\n";
        echo " Fixture sintética; nenhum usuário real é utilizado\n";
        echo "======================================================================\n\n";
    }

    private function finish(): int
    {
        echo "\n======================================================================\n";
        echo " RESULTADO\n";
        echo "======================================================================\n";
        echo "Aprovacoes: {$this->ok}\n";
        echo "Falhas:     {$this->fail}\n\n";

        if ($this->fail > 0) {
            echo "CHECKPOINT PASSWORD RESET / MARIADB: REPROVADO.\n";
            return 1;
        }

        echo "CHECKPOINT PASSWORD RESET / MARIADB: APROVADO.\n";
        return 0;
    }
}

$checkpoint = new PasswordResetMariaDbCheckpoint();
exit($checkpoint->run());
