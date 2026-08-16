<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;
use RuntimeException;
use Throwable;

final class MfaRecoveryRepository implements MfaRecoveryStore
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function substituirCodigos(
        int $usuarioId,
        array $hashes
    ): void {
        if ($usuarioId < 1 || $hashes === []) {
            throw new RuntimeException(
                'Não foi possível persistir os códigos de recuperação.'
            );
        }

        $this->pdo->beginTransaction();

        try {
            $stmt = $this->pdo->prepare(
                'DELETE FROM codigos_recuperacao_mfa
                 WHERE usuario_id = :usuario_id'
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->execute();

            $stmt = $this->pdo->prepare(
                'INSERT INTO codigos_recuperacao_mfa
                    (
                        usuario_id,
                        codigo_hash,
                        usado_em,
                        criado_em
                    )
                 VALUES
                    (
                        :usuario_id,
                        :codigo_hash,
                        NULL,
                        NOW()
                    )'
            );

            foreach ($hashes as $hash) {
                if (!is_string($hash) || strlen($hash) < 60) {
                    throw new RuntimeException(
                        'Hash de código de recuperação inválido.'
                    );
                }

                $stmt->bindValue(
                    ':usuario_id',
                    $usuarioId,
                    PDO::PARAM_INT
                );

                $stmt->bindValue(
                    ':codigo_hash',
                    $hash
                );

                $stmt->execute();
            }

            $this->pdo->commit();

        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
    }

    public function buscarAtivos(
        int $usuarioId
    ): array {
        $stmt = $this->pdo->prepare(
            'SELECT
                id,
                codigo_hash
             FROM codigos_recuperacao_mfa
             WHERE usuario_id = :usuario_id
               AND usado_em IS NULL
             ORDER BY id ASC'
        );

        $stmt->bindValue(
            ':usuario_id',
            $usuarioId,
            PDO::PARAM_INT
        );

        $stmt->execute();

        $registros = $stmt->fetchAll(PDO::FETCH_ASSOC);

        return array_map(
            static fn (array $registro): array => [
                'id' => (int) $registro['id'],
                'codigo_hash' => (string) $registro['codigo_hash'],
            ],
            $registros
        );
    }

    public function marcarComoUsado(
        int $usuarioId,
        int $codigoId
    ): bool {
        $stmt = $this->pdo->prepare(
            'UPDATE codigos_recuperacao_mfa
             SET usado_em = NOW()
             WHERE id = :id
               AND usuario_id = :usuario_id
               AND usado_em IS NULL'
        );

        $stmt->bindValue(
            ':id',
            $codigoId,
            PDO::PARAM_INT
        );

        $stmt->bindValue(
            ':usuario_id',
            $usuarioId,
            PDO::PARAM_INT
        );

        $stmt->execute();

        return $stmt->rowCount() === 1;
    }

    public function quantidadeAtivos(
        int $usuarioId
    ): int {
        $stmt = $this->pdo->prepare(
            'SELECT COUNT(*)
             FROM codigos_recuperacao_mfa
             WHERE usuario_id = :usuario_id
               AND usado_em IS NULL'
        );

        $stmt->bindValue(
            ':usuario_id',
            $usuarioId,
            PDO::PARAM_INT
        );

        $stmt->execute();

        return (int) $stmt->fetchColumn();
    }
}
