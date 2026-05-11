<?php
declare(strict_types=1);

namespace ConectaEduca\Model;

final class Empresa
{
    public function __construct(
        public readonly ?int $id,
        public readonly string $nome,
        public readonly string $email,
        public readonly ?string $areaAtuacao = null
    ) {}
}