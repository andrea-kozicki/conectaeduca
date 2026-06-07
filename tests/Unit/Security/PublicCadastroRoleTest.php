<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Service\UsuarioService;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;
use ReflectionClass;

final class PublicCadastroRoleTest extends TestCase
{
    private function serviceSemConstrutor(): UsuarioService
    {
        $reflection = new ReflectionClass(UsuarioService::class);

        /** @var UsuarioService $service */
        $service = $reflection->newInstanceWithoutConstructor();

        return $service;
    }

    public function testCadastroPublicoNaoPermiteCriarAdmin(): void
    {
        $this->expectException(InvalidArgumentException::class);

        $this->serviceSemConstrutor()->criarLocal([
            'role' => 'admin',
            'nome' => 'Tentativa Admin',
            'email' => 'tentativa.admin@example.com',
            'cpf' => '12345678901',
            'telefone' => '41999990000',
            'data_nascimento' => '1990-01-01',
            'senha' => 'SenhaTeste123!',
            'confirmarSenha' => 'SenhaTeste123!',
        ]);
    }

    public function testCadastroPublicoNaoPermiteRoleArbitraria(): void
    {
        $this->expectException(InvalidArgumentException::class);

        $this->serviceSemConstrutor()->criarLocal([
            'role' => 'root',
            'nome' => 'Tentativa Root',
            'email' => 'tentativa.root@example.com',
            'cpf' => '12345678902',
            'telefone' => '41999990000',
            'data_nascimento' => '1990-01-01',
            'senha' => 'SenhaTeste123!',
            'confirmarSenha' => 'SenhaTeste123!',
        ]);
    }
}