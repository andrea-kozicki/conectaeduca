<?php
declare(strict_types=1);

namespace ConectaEduca\Model;

final class Oportunidade
{
    public function __construct(
        public readonly ?int $id,
        public readonly int $empresaId,
        public readonly string $titulo,
        public readonly string $descricao,
        public readonly string $area,
        public readonly string $status
    ) {}
}