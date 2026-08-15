<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

interface RateLimitStore
{
    public function consume(
        string $acao,
        string $identificadorHash,
        int $limite,
        int $janelaSegundos
    ): bool;

    public function reset(
        string $acao,
        string $identificadorHash
    ): void;
}
