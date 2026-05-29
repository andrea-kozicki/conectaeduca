<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use RuntimeException;

final class UsuarioService
{
    private UsuarioRepository $usuarios;

    public function __construct()
    {
        $this->usuarios = new UsuarioRepository(Database::connect());
    }

    public function criarLocal(array $dados): int
    {
        $nome = InputValidator::requiredString($dados['nome'] ?? '', 'nome', 150);
        $email = InputValidator::email($dados['email'] ?? '');
        $role = InputValidator::enum($dados['role'] ?? 'usuario', ['usuario', 'empresa', 'admin'], 'role');

        $senha = (string) ($dados['senha'] ?? '');
        $confirmarSenha = (string) ($dados['confirmarSenha'] ?? '');

        if (strlen($senha) < 8) {
            throw new InvalidArgumentException('A senha deve ter pelo menos 8 caracteres.');
        }

        if ($senha !== $confirmarSenha) {
            throw new InvalidArgumentException('A confirmação de senha não confere.');
        }

        $cpf = self::somenteNumeros($dados['cpf'] ?? '');

        if ($cpf !== null && strlen($cpf) !== 11) {
            throw new InvalidArgumentException('CPF deve conter 11 números.');
        }

        $telefone = trim((string) ($dados['telefone'] ?? ''));

        if ($telefone === '') {
            $telefone = null;
        }

        $dataNascimento = self::normalizarDataNascimento($dados['data_nascimento'] ?? null);

        return $this->usuarios->criarLocal([
            'nome' => $nome,
            'email' => $email,
            'role' => $role,
            'senha_hash' => password_hash($senha, PASSWORD_DEFAULT),
            'cpf' => $cpf,
            'telefone' => $telefone,
            'data_nascimento' => $dataNascimento,
        ]);
    }

    public function buscarPorId(int $id): ?array
    {
        return $this->usuarios->buscarPorId($id);
    }

    public function atualizarPerfil(int $id, array $dados): array
    {
        $nome = InputValidator::requiredString($dados['nome'] ?? '', 'nome', 150);

        $cpf = self::somenteNumeros($dados['cpf'] ?? '');

        if ($cpf !== null && strlen($cpf) !== 11) {
            throw new InvalidArgumentException('CPF deve conter 11 números.');
        }

        $telefone = trim((string) ($dados['telefone'] ?? ''));

        if ($telefone === '') {
            $telefone = null;
        }

        if ($telefone !== null && strlen($telefone) < 8) {
            throw new InvalidArgumentException('Telefone deve conter pelo menos 8 caracteres.');
        }

        if ($telefone !== null && strlen($telefone) > 20) {
            throw new InvalidArgumentException('Telefone deve ter no máximo 20 caracteres.');
        }

        $dataNascimento = self::normalizarDataNascimento($dados['data_nascimento'] ?? null);

        $usuario = $this->usuarios->atualizarPerfil($id, [
            'nome' => $nome,
            'cpf' => $cpf,
            'telefone' => $telefone,
            'data_nascimento' => $dataNascimento,
        ]);

        if ($usuario === null) {
            throw new RuntimeException('Usuário não encontrado para atualização.');
        }

        return $usuario;
    }

    private static function somenteNumeros(mixed $value): ?string
    {
        $digits = preg_replace('/\D+/', '', (string) $value);

        if ($digits === '') {
            return null;
        }

        return $digits;
    }

    private static function normalizarDataNascimento(mixed $value): ?string
    {
        $data = trim((string) $value);

        if ($data === '') {
            return null;
        }

        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $data)) {
            throw new InvalidArgumentException('Data de nascimento deve estar no formato AAAA-MM-DD.');
        }

        [$ano, $mes, $dia] = array_map('intval', explode('-', $data));

        if (!checkdate($mes, $dia, $ano)) {
            throw new InvalidArgumentException('Data de nascimento inválida.');
        }

        return $data;
    }
}