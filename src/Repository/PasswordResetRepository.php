<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

use DateTimeImmutable;
use PDO;
use RuntimeException;
use Throwable;

final class PasswordResetRepository implements PasswordResetStore
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function substituirToken(
        int $usuarioId,
        string $tokenHash,
        DateTimeImmutable $expiraEm
    ): void {
        if (
            $usuarioId < 1
            || !preg_match('/^[a-f0-9]{64}$/', $tokenHash)
        ) {
            throw new RuntimeException(
                'Não foi possível persistir o token de recuperação.'
            );
        }

        $this->pdo->beginTransaction();

        try {
            /*
             * Uma nova solicitação invalida qualquer token anterior ainda
             * utilizável, mas preserva o registro para rastreabilidade.
             */
            $stmt = $this->pdo->prepare(
                "UPDATE tokens_conta
                 SET usado_em = NOW()
                 WHERE usuario_id = :usuario_id
                   AND tipo_token = 'recuperacao_senha'
                   AND usado_em IS NULL"
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->execute();

            $stmt = $this->pdo->prepare(
                "INSERT INTO tokens_conta
                    (
                        usuario_id,
                        tipo_token,
                        token_hash,
                        expira_em,
                        usado_em,
                        criado_em
                    )
                 VALUES
                    (
                        :usuario_id,
                        'recuperacao_senha',
                        :token_hash,
                        :expira_em,
                        NULL,
                        NOW()
                    )"
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->bindValue(
                ':token_hash',
                $tokenHash
            );

            $stmt->bindValue(
                ':expira_em',
                $expiraEm->format('Y-m-d H:i:s')
            );

            $stmt->execute();

            $this->pdo->commit();
        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
    }

    public function buscarAtivoPorHash(
        string $tokenHash
    ): ?array {
        if (!preg_match('/^[a-f0-9]{64}$/', $tokenHash)) {
            return null;
        }

        $stmt = $this->pdo->prepare(
            "SELECT
                id,
                usuario_id
             FROM tokens_conta
             WHERE token_hash = :token_hash
               AND tipo_token = 'recuperacao_senha'
               AND usado_em IS NULL
               AND expira_em > NOW()
             LIMIT 1"
        );

        $stmt->bindValue(
            ':token_hash',
            $tokenHash
        );

        $stmt->execute();

        $registro = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!is_array($registro)) {
            return null;
        }

        return [
            'id' => (int) $registro['id'],
            'usuario_id' => (int) $registro['usuario_id'],
        ];
    }

    public function redefinirSenhaPorHash(
        string $tokenHash,
        string $senhaHash
    ): ?int {
        if (!preg_match('/^[a-f0-9]{64}$/', $tokenHash)) {
            return null;
        }

        if (strlen($senhaHash) < 60) {
            throw new RuntimeException(
                'Hash de senha inválido para redefinição.'
            );
        }

        $this->pdo->beginTransaction();

        try {
            /*
             * FOR UPDATE serializa o uso do mesmo token. A senha somente é
             * alterada se o token continuar válido dentro desta transação.
             */
            $stmt = $this->pdo->prepare(
                "SELECT
                    id,
                    usuario_id
                 FROM tokens_conta
                 WHERE token_hash = :token_hash
                   AND tipo_token = 'recuperacao_senha'
                   AND usado_em IS NULL
                   AND expira_em > NOW()
                 LIMIT 1
                 FOR UPDATE"
            );

            $stmt->bindValue(
                ':token_hash',
                $tokenHash
            );

            $stmt->execute();
            $registro = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!is_array($registro)) {
                $this->pdo->rollBack();
                return null;
            }

            $usuarioId = (int) $registro['usuario_id'];

            $stmt = $this->pdo->prepare(
                'UPDATE usuarios
                 SET senha_hash = :senha_hash
                 WHERE id = :usuario_id'
            );

            $stmt->bindValue(
                ':senha_hash',
                $senhaHash
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->execute();

            if ($stmt->rowCount() !== 1) {
                throw new RuntimeException(
                    'Não foi possível atualizar a senha do usuário.'
                );
            }

            /*
             * O token usado e qualquer outro token de recuperação ainda
             * pendente do mesmo usuário deixam de ser reutilizáveis.
             */
            $stmt = $this->pdo->prepare(
                "UPDATE tokens_conta
                 SET usado_em = NOW()
                 WHERE usuario_id = :usuario_id
                   AND tipo_token = 'recuperacao_senha'
                   AND usado_em IS NULL"
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->execute();

            $this->pdo->commit();

            return $usuarioId;
        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
    }
}
