<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\EmpresaRepository;
use ConectaEduca\Repository\OportunidadeRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\InputValidator;
use RuntimeException;

final class OportunidadeService
{
    private OportunidadeRepository $oportunidades;
    private EmpresaRepository $empresas;

    public function __construct()
    {
        $pdo = Database::connect();

        $this->oportunidades = new OportunidadeRepository($pdo);
        $this->empresas = new EmpresaRepository($pdo);
    }

    public function listarPublicas(array $filtros = []): array
    {
        $area = InputValidator::optionalString($filtros['area'] ?? null, 120);
        $busca = InputValidator::searchTerm($filtros['busca'] ?? '', 100);

        $modalidade = InputValidator::optionalString($filtros['modalidade'] ?? null, 20);

        if ($modalidade !== null) {
            $modalidade = InputValidator::enum(
                $modalidade,
                ['presencial', 'remoto', 'hibrido'],
                'modalidade'
            );
        }

        $tipo = InputValidator::optionalString($filtros['tipo'] ?? null, 30);

        if ($tipo !== null) {
            $tipo = InputValidator::enum(
                $tipo,
                ['estagio', 'emprego', 'trainee', 'bolsa', 'voluntariado', 'outro'],
                'tipo'
            );
        }

        return $this->oportunidades->listarPublicas($area, $busca, $modalidade, $tipo);
    }

    public function buscarPorId(int $id): ?array
    {
        return $this->oportunidades->buscarPorId($id);
    }

    public function listarGerenciaveisParaEmpresaOuAdmin(array $user): array
    {
        if (($user['role'] ?? '') === 'admin') {
            return $this->oportunidades->listarGerenciaveisTodas();
        }

        $empresa = $this->empresaDoUsuario((int) ($user['id'] ?? 0));

        return $this->oportunidades->listarGerenciaveisPorEmpresa((int) $empresa['id']);
    }

    public function listarEmpresasParaFormulario(array $user): array
    {
        if (($user['role'] ?? '') === 'admin') {
            return $this->empresas->listar();
        }

        $empresa = $this->empresaDoUsuario((int) ($user['id'] ?? 0));

        return [$empresa];
    }

    public function criarGerenciavel(array $user, array $dados): int
    {
        $dadosNormalizados = $this->normalizarDadosFormulario($user, $dados, null);

        $id = $this->oportunidades->criarCompleta($dadosNormalizados);

        AuditLogger::log('oportunidade_criada', [
            'oportunidade_id' => $id,
            'usuario_id' => $user['id'] ?? null,
            'role' => $user['role'] ?? null,
            'empresa_id' => $dadosNormalizados['empresa_id'],
            'status' => $dadosNormalizados['status'],
        ]);

        return $id;
    }

    public function atualizarGerenciavel(array $user, array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $this->autorizarAcessoOportunidade($user, $id);

        $dadosNormalizados = $this->normalizarDadosFormulario($user, $dados, $id);

        $this->oportunidades->atualizarCompleta($id, $dadosNormalizados);

        AuditLogger::log('oportunidade_atualizada', [
            'oportunidade_id' => $id,
            'usuario_id' => $user['id'] ?? null,
            'role' => $user['role'] ?? null,
            'empresa_id' => $dadosNormalizados['empresa_id'],
            'status' => $dadosNormalizados['status'],
        ]);
    }

    public function alterarStatusGerenciavel(array $user, array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $status = $this->enum(
            $dados['status'] ?? '',
            ['rascunho', 'publicada', 'suspensa', 'encerrada'],
            'status'
        );

        $oportunidade = $this->autorizarAcessoOportunidade($user, $id);

        $this->oportunidades->alterarStatus($id, $status);

        AuditLogger::log('oportunidade_status_alterado', [
            'oportunidade_id' => $id,
            'usuario_id' => $user['id'] ?? null,
            'role' => $user['role'] ?? null,
            'empresa_id' => $oportunidade['empresa_id'] ?? null,
            'status_anterior' => $oportunidade['status'] ?? null,
            'status_novo' => $status,
        ]);
    }

    public function excluirGerenciavel(array $user, array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $oportunidade = $this->autorizarAcessoOportunidade($user, $id);

        if (($oportunidade['status'] ?? '') !== 'rascunho') {
            throw new RuntimeException('Apenas oportunidades em rascunho podem ser excluídas.');
        }

        $excluiu = $this->oportunidades->excluirSemInscricoes($id);

        if (!$excluiu) {
            throw new RuntimeException('Não é possível excluir oportunidade com inscrições vinculadas.');
        }

        AuditLogger::log('oportunidade_excluida', [
            'oportunidade_id' => $id,
            'usuario_id' => $user['id'] ?? null,
            'role' => $user['role'] ?? null,
            'empresa_id' => $oportunidade['empresa_id'] ?? null,
        ]);
    }

    public function criar(array $dados, ?array $user = null): int
    {
        if ($user === null) {
            throw new RuntimeException('Usuário autenticado é obrigatório para criar oportunidade.');
        }

        return $this->criarGerenciavel($user, $dados);
    }

    private function autorizarAcessoOportunidade(array $user, int $id): array
    {
        if (($user['role'] ?? '') === 'admin') {
            $oportunidade = $this->oportunidades->buscarPorId($id);

            if ($oportunidade === null) {
                throw new RuntimeException('Oportunidade não encontrada.');
            }

            return $oportunidade;
        }

        $empresa = $this->empresaDoUsuario((int) ($user['id'] ?? 0));

        $oportunidade = $this->oportunidades->buscarPorIdEEmpresa($id, (int) $empresa['id']);

        if ($oportunidade === null) {
            throw new RuntimeException('Oportunidade não encontrada ou não autorizada para esta empresa.');
        }

        return $oportunidade;
    }

    private function empresaDoUsuario(int $usuarioId): array
    {
        $empresa = $this->empresas->buscarPorUsuarioId($usuarioId);

        if ($empresa === null) {
            throw new RuntimeException('Nenhuma empresa está vinculada ao usuário autenticado.');
        }

        return $empresa;
    }

    private function normalizarDadosFormulario(array $user, array $dados, ?int $id): array
    {
        $empresaId = $this->resolverEmpresaId($user, $dados, $id);

        $titulo = $this->textoObrigatorio($dados['titulo'] ?? null, 'titulo', 3, 180);
        $descricao = $this->textoObrigatorio($dados['descricao'] ?? null, 'descricao', 10, 10000);

        $requisitos = $this->textoOpcional($dados['requisitos'] ?? null, 6000);
        $areaConhecimento = $this->textoOpcional($dados['area_conhecimento'] ?? null, 120);

        $modalidade = $this->enum(
            $dados['modalidade'] ?? 'presencial',
            ['presencial', 'remoto', 'hibrido'],
            'modalidade'
        );

        $tipo = $this->enum(
            $dados['tipo_oportunidade'] ?? 'estagio',
            ['estagio', 'emprego', 'trainee', 'bolsa', 'voluntariado', 'outro'],
            'tipo_oportunidade'
        );

        $cidade = $this->textoOpcional($dados['cidade'] ?? null, 120);

        $estado = $this->textoOpcional($dados['estado'] ?? null, 2);
        $estado = $estado !== null ? strtoupper($estado) : null;

        if ($estado !== null && !preg_match('/^[A-Z]{2}$/', $estado)) {
            throw new RuntimeException('Estado deve conter a sigla com 2 letras. Ex.: PR.');
        }

        $status = $this->enum(
            $dados['status'] ?? 'rascunho',
            ['rascunho', 'publicada', 'suspensa', 'encerrada'],
            'status'
        );

        $dataPublicacao = $status === 'publicada' ? date('Y-m-d H:i:s') : null;
        $dataEncerramento = $this->normalizarDataHora($dados['data_encerramento'] ?? null);

        if ($status === 'encerrada' && $dataEncerramento === null) {
            $dataEncerramento = date('Y-m-d H:i:s');
        }

        return [
            'empresa_id' => $empresaId,
            'titulo' => $titulo,
            'descricao' => $descricao,
            'requisitos' => $requisitos,
            'area_conhecimento' => $areaConhecimento,
            'modalidade' => $modalidade,
            'tipo_oportunidade' => $tipo,
            'cidade' => $cidade,
            'estado' => $estado,
            'status' => $status,
            'data_publicacao' => $dataPublicacao,
            'data_encerramento' => $dataEncerramento,
        ];
    }

    private function resolverEmpresaId(array $user, array $dados, ?int $id): int
    {
        if (($user['role'] ?? '') !== 'admin') {
            $empresa = $this->empresaDoUsuario((int) ($user['id'] ?? 0));

            return (int) $empresa['id'];
        }

        if ($id !== null) {
            $oportunidade = $this->oportunidades->buscarPorId($id);

            if ($oportunidade === null) {
                throw new RuntimeException('Oportunidade não encontrada.');
            }

            return (int) ($dados['empresa_id'] ?? $oportunidade['empresa_id']);
        }

        return InputValidator::id($dados['empresa_id'] ?? null, 'empresa_id');
    }

    private function textoObrigatorio(mixed $valor, string $campo, int $min, int $max): string
    {
        $texto = trim((string) $valor);

        if ($texto === '') {
            throw new RuntimeException("Campo {$campo} é obrigatório.");
        }

        $tamanho = mb_strlen($texto);

        if ($tamanho < $min) {
            throw new RuntimeException("Campo {$campo} deve ter pelo menos {$min} caracteres.");
        }

        if ($tamanho > $max) {
            throw new RuntimeException("Campo {$campo} deve ter no máximo {$max} caracteres.");
        }

        return $texto;
    }

    private function textoOpcional(mixed $valor, int $max): ?string
    {
        $texto = trim((string) $valor);

        if ($texto === '') {
            return null;
        }

        if (mb_strlen($texto) > $max) {
            throw new RuntimeException("Campo opcional deve ter no máximo {$max} caracteres.");
        }

        return $texto;
    }

    private function enum(mixed $valor, array $permitidos, string $campo): string
    {
        $texto = trim((string) $valor);

        if (!in_array($texto, $permitidos, true)) {
            throw new RuntimeException("Valor inválido para {$campo}.");
        }

        return $texto;
    }

    private function normalizarDataHora(mixed $valor): ?string
    {
        $texto = trim((string) $valor);

        if ($texto === '') {
            return null;
        }

        $texto = str_replace('T', ' ', $texto);

        if (!preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/', $texto)) {
            throw new RuntimeException('Data de encerramento inválida.');
        }

        return $texto . ':00';
    }
}