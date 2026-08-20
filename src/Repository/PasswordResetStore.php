<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

use DateTimeImmutable;

interface PasswordResetStore
{
    public function substituirToken(
        int $usuarioId,
        string $tokenHash,
        DateTimeImmutable $expiraEm
    ): void;

    /**
     * @return array{id:int,usuario_id:int}|null
     */
    public function buscarAtivoPorHash(
        string $tokenHash
    ): ?array;

    /**
     * Troca a senha e consome todos os tokens de recuperação do usuário
     * dentro da mesma transação do armazenamento.
     *
     * @return int|null ID do usuário somente quando a redefinição ocorreu.
     */
    public function redefinirSenhaPorHash(
        string $tokenHash,
        string $senhaHash
    ): ?int;
}
