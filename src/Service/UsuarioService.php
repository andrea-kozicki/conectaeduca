<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\InputValidator;

final class UsuarioService
{
    private UsuarioRepository $usuarios;

    public function __construct()
    {
        $this->usuarios = new UsuarioRepository(Database::connect());
    }

    public function criarLocal(array $dados): int
    {
        $nome = InputValidator::requiredString($dados['nome'] ?? '', 'nome', 120);
        $email = InputValidator::email($dados['email'] ?? '');
        $role = InputValidator::enum($dados['role'] ?? 'usuario', ['usuario', 'empresa', 'admin'], 'role');

        return $this->usuarios->criarLocal($nome, $email, $role);
    }

    public function buscarPorId(int $id): ?array
    {
        return $this->usuarios->buscarPorId($id);
    }
}