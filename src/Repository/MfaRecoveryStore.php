<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

interface MfaRecoveryStore
{
    /**
     * @param list<string> $hashes
     */
    public function substituirCodigos(
        int $usuarioId,
        array $hashes
    ): void;

    /**
     * @return list<array{id:int,codigo_hash:string}>
     */
    public function buscarAtivos(
        int $usuarioId
    ): array;

    public function marcarComoUsado(
        int $usuarioId,
        int $codigoId
    ): bool;

    public function quantidadeAtivos(
        int $usuarioId
    ): int;
}
