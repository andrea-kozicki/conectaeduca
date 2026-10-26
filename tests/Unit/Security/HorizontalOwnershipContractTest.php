<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Controller\InscricaoController;
use ConectaEduca\Repository\EmpresaRepository;
use ConectaEduca\Repository\InscricaoRepository;
use ConectaEduca\Repository\OportunidadeRepository;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Service\InscricaoService;
use ConectaEduca\Service\OportunidadeService;
use PHPUnit\Framework\TestCase;
use ReflectionMethod;

/**
 * PA-05 / Pentest B: contrato OFFLINE de propriedade entre contas do MESMO papel.
 *
 * Estes sao testes estruturais de guardas, propagacao de IDs e clausulas SQL.
 * NAO comprovam que MariaDB, endpoints HTTP ou sessao real bloqueiam BOLA.
 * Nao alteram a politica de negocio dos papeis da aplicacao.
 */
final class HorizontalOwnershipContractTest extends TestCase
{
    private static function methodText(string $class, string $method): string
    {
        $reflection = new ReflectionMethod($class, $method);
        $filename = $reflection->getFileName();
        self::assertIsString($filename);
        $lines = file($filename, FILE_IGNORE_NEW_LINES);
        self::assertIsArray($lines);
        return implode("\n", array_slice($lines, $reflection->getStartLine() - 1,
            $reflection->getEndLine() - $reflection->getStartLine() + 1));
    }

    public function testCandidaturasPreservamAutenticacaoSemNovaRegraDePapel(): void
    {
        foreach (['minhas', 'criar', 'cancelar'] as $method) {
            $body = self::methodText(InscricaoController::class, $method);
            self::assertStringContainsString('Authorization::requireAuth()', $body,
                'O controle de papel nao pode ser alterado por este ensaio: ' . $method);
            self::assertStringNotContainsString("requireRole('usuario')", $body);
        }
    }

    public function testDuasSessoesMesmoPapelNaoSaoMesmaIdentidade(): void
    {
        $_SESSION['user'] = ['id' => 101, 'role' => 'usuario'];
        self::assertTrue(Authorization::hasRole('usuario'));
        $idA = Authorization::user()['id'];
        $_SESSION['user'] = ['id' => 202, 'role' => 'usuario'];
        self::assertTrue(Authorization::hasRole('usuario'));
        self::assertNotSame($idA, Authorization::user()['id']);
        $_SESSION = [];
    }

    public function testListagemDasInscricoesUsaIdDaSessao(): void
    {
        $ctrl = self::methodText(InscricaoController::class, 'minhas');
        $service = self::methodText(InscricaoService::class, 'listarPorUsuario');
        self::assertStringContainsString("(int) \$user['id']", $ctrl);
        self::assertStringContainsString('listarPorUsuario($usuarioId)', $service);
    }

    public function testSqlListagemDeCandidatoFiltraUsuarioId(): void
    {
        $body = self::methodText(InscricaoRepository::class, 'listarPorUsuario');
        self::assertStringContainsString('WHERE i.usuario_id = :usuario_id', $body);
        self::assertStringContainsString("bindValue(':usuario_id', \$usuarioId", $body);
    }

    public function testSqlBuscaDeCandidaturaExigeIdEUsuarioId(): void
    {
        $body = self::methodText(InscricaoRepository::class, 'buscarPorIdEUsuario');
        self::assertStringContainsString('WHERE i.id = :id', $body);
        self::assertStringContainsString('AND i.usuario_id = :usuario_id', $body);
        self::assertStringContainsString("bindValue(':usuario_id', \$usuarioId", $body);
        self::assertStringContainsString("bindValue(':id', \$id", $body);
    }

    public function testCancelamentoDeCandidatoExigePropriedadeNaConsulta(): void
    {
        $body = self::methodText(InscricaoService::class, 'cancelarPorUsuario');
        self::assertStringContainsString('buscarPorIdEUsuario($id, $usuarioId)', $body);
        self::assertStringContainsString('if ($inscricao === null)', $body);
        self::assertStringContainsString('cancelarPorUsuario($id, $usuarioId)', $body);
    }

    public function testSqlCancelamentoRevalidaPropriedadeNoUpdate(): void
    {
        $body = self::methodText(InscricaoRepository::class, 'cancelarPorUsuario');
        self::assertStringContainsString('WHERE id = :id', $body);
        self::assertStringContainsString('AND usuario_id = :usuario_id', $body);
        self::assertStringContainsString("bindValue(':usuario_id', \$usuarioId", $body);
        self::assertStringContainsString('status IN (:status_enviada, :status_em_analise)', $body);
    }

    public function testEmpresaDaSessaoEhConsultadaPorUsuarioId(): void
    {
        $body = self::methodText(EmpresaRepository::class, 'buscarPorUsuarioId');
        self::assertStringContainsString('WHERE usuario_id = :usuario_id', $body);
        self::assertStringContainsString("bindValue(':usuario_id', \$usuarioId", $body);
    }

    public function testEmpresaNaoListaCandidaturasDeOutraEmpresaNoSql(): void
    {
        $body = self::methodText(InscricaoRepository::class, 'listarRecebidasPorEmpresa');
        self::assertStringContainsString('WHERE o.empresa_id = :empresa_id', $body);
        self::assertStringContainsString("bindValue(':empresa_id', \$empresaId", $body);
    }

    public function testBuscaDeInscricaoEmpresaCruzaIdComEmpresaId(): void
    {
        $body = self::methodText(InscricaoRepository::class, 'buscarPorIdEEmpresa');
        self::assertStringContainsString('WHERE i.id = :id', $body);
        self::assertStringContainsString('AND o.empresa_id = :empresa_id', $body);
        self::assertStringContainsString("bindValue(':empresa_id', \$empresaId", $body);
    }

    public function testAlteracaoDeInscricaoEmpresaPassaPelaBuscaEscopada(): void
    {
        $body = self::methodText(InscricaoService::class, 'atualizarStatusPorEmpresaOuAdmin');
        self::assertStringContainsString("(\$user['role'] ?? '') === 'admin'", $body);
        self::assertStringContainsString('buscarPorUsuarioId((int) $user[\'id\'])', $body);
        self::assertStringContainsString('buscarPorIdEEmpresa($id, $empresaId)', $body);
        self::assertStringContainsString('if ($inscricao === null)', $body);
    }

    public function testOportunidadesDeEmpresaEscopamIdEAEntidade(): void
    {
        $body = self::methodText(OportunidadeService::class, 'autorizarAcessoOportunidade');
        self::assertStringContainsString("(\$user['role'] ?? '') === 'admin'", $body);
        self::assertStringContainsString('buscarPorIdEEmpresa($id, (int) $empresa[\'id\'])', $body);
        $sql = self::methodText(OportunidadeRepository::class, 'buscarPorIdEEmpresa');
        self::assertStringContainsString('AND empresa_id = :empresa_id', $sql);
    }

    public function testGestaoEmpresaContinuaComGuardaVerticalOriginal(): void
    {
        foreach (['recebidasEmpresa', 'atualizarStatusEmpresa', 'atualizarStatus'] as $method) {
            $body = self::methodText(InscricaoController::class, $method);
            self::assertStringContainsString("Authorization::requireAnyRole(['empresa', 'admin'])", $body);
        }
    }
}
