<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;
use RuntimeException;
use Throwable;

final class MfaRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function buscarPorUsuarioId(
        int $usuarioId
    ): ?array {
        $stmt = $this->pdo->prepare(
            'SELECT
                id,
                usuario_id,
                segredo_totp_envelope,
                qr_confirmado,
                ativo,
                ultimo_passo_totp,
                criado_em,
                atualizado_em
             FROM segredos_mfa
             WHERE usuario_id = :usuario_id
             LIMIT 1'
        );

        $stmt->bindValue(
            ':usuario_id',
            $usuarioId,
            PDO::PARAM_INT
        );

        $stmt->execute();

        $registro = $stmt->fetch(PDO::FETCH_ASSOC);

        return $registro ?: null;
    }

    public function salvarConfiguracaoPendente(
        int $usuarioId,
        string $envelope
    ): void {
        $stmt = $this->pdo->prepare(
            'INSERT INTO segredos_mfa
                (
                    usuario_id,
                    segredo_totp_envelope,
                    qr_confirmado,
                    ativo,
                    ultimo_passo_totp
                )
             VALUES
                (
                    :usuario_id,
                    :envelope,
                    0,
                    0,
                    NULL
                )
             ON DUPLICATE KEY UPDATE
                segredo_totp_envelope =
                    VALUES(segredo_totp_envelope),
                qr_confirmado = 0,
                ativo = 0,
                ultimo_passo_totp = NULL'
        );

        $stmt->execute([
            ':usuario_id' => $usuarioId,
            ':envelope' => $envelope,
        ]);
    }

    public function ativarConfiguracao(
        int $usuarioId,
        int $passoTotp
    ): void {
        $this->pdo->beginTransaction();

        try {
            $stmt = $this->pdo->prepare(
                'UPDATE segredos_mfa
                 SET
                    qr_confirmado = 1,
                    ativo = 1,
                    ultimo_passo_totp = :passo
                 WHERE usuario_id = :usuario_id'
            );

            $stmt->execute([
                ':passo' => $passoTotp,
                ':usuario_id' => $usuarioId,
            ]);

            if ($stmt->rowCount() !== 1) {
                throw new RuntimeException(
                    'Configuração MFA não encontrada.'
                );
            }

            $stmt = $this->pdo->prepare(
                'UPDATE usuarios
                 SET mfa_ativo = 1
                 WHERE id = :usuario_id'
            );

            $stmt->bindValue(
                ':usuario_id',
                $usuarioId,
                PDO::PARAM_INT
            );

            $stmt->execute();

            /*
             * Em uma recuperação de MFA, mfa_ativo pode já estar em 1.
             * Nesse caso o MySQL pode retornar rowCount() = 0 mesmo
             * que o usuário exista. Confirmamos a existência antes de
             * tratar o caso como erro.
             */
            if ($stmt->rowCount() !== 1) {
                $check = $this->pdo->prepare(
                    'SELECT 1
                     FROM usuarios
                     WHERE id = :usuario_id
                     LIMIT 1'
                );

                $check->bindValue(
                    ':usuario_id',
                    $usuarioId,
                    PDO::PARAM_INT
                );

                $check->execute();

                if ($check->fetchColumn() === false) {
                    throw new RuntimeException(
                        'Usuário do MFA não encontrado.'
                    );
                }
            }

            $this->pdo->commit();

        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
    }

    public function registrarPassoSeNovo(
        int $usuarioId,
        int $passoTotp
    ): bool {
        $stmt = $this->pdo->prepare(
            'UPDATE segredos_mfa
             SET ultimo_passo_totp = :passo_novo
             WHERE usuario_id = :usuario_id
               AND ativo = 1
               AND qr_confirmado = 1
               AND (
                    ultimo_passo_totp IS NULL
                    OR ultimo_passo_totp < :passo_comparacao
               )'
        );

        $stmt->execute([
            ':passo_novo' => $passoTotp,
            ':passo_comparacao' => $passoTotp,
            ':usuario_id' => $usuarioId,
        ]);

        return $stmt->rowCount() === 1;
    }
}
