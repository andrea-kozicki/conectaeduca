<?php
declare(strict_types=1);

namespace ConectaEduca\Model;

final class Inscricao
{
    public function __construct(
        public readonly ?int $id,
        public readonly int $usuarioId,
        public readonly int $oportunidadeId,
        public readonly string $status
    ) {}
}