<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\EmpresaRepository;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\InputValidator;
use InvalidArgumentException;
use PDO;
use RuntimeException;
use Throwable;

final class UsuarioService
{
    private PDO $pdo;
    private UsuarioRepository $usuarios;
    private EmpresaRepository $empresas;
    

    public function __construct()
    {
        $this->pdo = Database::connect();
        $this->usuarios = new UsuarioRepository($this->pdo);
        $this->empresas = new EmpresaRepository($this->pdo);
    }

    public function criarLocal(array $dados): int
    {
        $nome = InputValidator::requiredString($dados['nome'] ?? '', 'nome', 150);
        $email = InputValidator::email($dados['email'] ?? '');

        // O cadastro público não deve permitir criação de administradores.
        $role = InputValidator::enum($dados['role'] ?? 'usuario', ['usuario', 'empresa'], 'role');

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
        $senhaHashUsuario = password_hash($senha, PASSWORD_DEFAULT);

        $empresaDados = null;

        if ($role === 'empresa') {
            $razaoSocial = InputValidator::requiredString($dados['razao_social'] ?? '', 'razao_social', 180);
            $cnpj = self::somenteNumeros($dados['cnpj'] ?? '');

            if ($cnpj === null || strlen($cnpj) !== 14) {
                throw new InvalidArgumentException('CNPJ deve conter 14 números.');
            }

            $nomeFantasia = trim((string) ($dados['nome_fantasia'] ?? ''));
            $areaAtuacao = trim((string) ($dados['area_atuacao'] ?? ''));
            $descricao = trim((string) ($dados['descricao_empresa'] ?? ''));
            $siteUrl = trim((string) ($dados['site_url'] ?? ''));

            if ($siteUrl !== '' && !filter_var($siteUrl, FILTER_VALIDATE_URL)) {
                throw new InvalidArgumentException('Site da empresa deve ser uma URL válida.');
            }

            $empresaDados = [
                'razao_social' => $razaoSocial,
                'nome_fantasia' => $nomeFantasia !== '' ? $nomeFantasia : null,
                'area_atuacao' => $areaAtuacao !== '' ? $areaAtuacao : null,
                'email' => $email,
                // A autenticação principal fica na conta de usuário;
                // este hash cumpre temporariamente o modelo legado da tabela empresas.
                'senha_hash' => password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT),
                'cnpj' => $cnpj,
                'telefone' => $telefone,
                'descricao' => $descricao !== '' ? $descricao : null,
                'site_url' => $siteUrl !== '' ? $siteUrl : null,
            ];
        }

    
        try {
            $this->pdo->beginTransaction();

            $usuarioId = $this->usuarios->criarLocal([
        
                'nome' => $nome,
                'email' => $email,
                'role' => $role,
                'senha_hash' => $senhaHashUsuario,
                'cpf' => $cpf,
                'telefone' => $telefone,
                'data_nascimento' => $dataNascimento,
            ]);

            if ($empresaDados !== null) {
                $this->empresas->criarVinculadaUsuario($usuarioId, $empresaDados);
            }

            $this->pdo->commit();

            return $usuarioId;
        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
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
