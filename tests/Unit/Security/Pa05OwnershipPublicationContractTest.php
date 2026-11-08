<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Controller\InscricaoController;
use ConectaEduca\Repository\InscricaoRepository;
use ConectaEduca\Service\InscricaoService;
use PHPUnit\Framework\TestCase;
use ReflectionMethod;

/** PA-05: contratos pontuais de SQL por propriedade e publicação; sem BD ou VM. */
final class Pa05OwnershipPublicationContractTest extends TestCase
{
    private static function body(string $class, string $method): string
    {
        $reflection = new ReflectionMethod($class, $method);
        $lines = file($reflection->getFileName(), FILE_IGNORE_NEW_LINES);
        self::assertIsArray($lines);

        return implode("\n", array_slice(
            $lines,
            $reflection->getStartLine() - 1,
            $reflection->getEndLine() - $reflection->getStartLine() + 1
        ));
    }

    public function testInscricaoUsaInsertSelectComStatusPublicadaNoMesmoSql(): void
    {
        $sql = self::body(InscricaoRepository::class, 'criar');

        self::assertStringContainsString('INSERT INTO inscricoes', $sql);
        self::assertStringContainsString('SELECT :usuario_id, o.id, :status, NOW()', $sql);
        self::assertStringContainsString('FROM oportunidades o', $sql);
        self::assertStringContainsString('WHERE o.id = :oportunidade_id', $sql);
        self::assertStringContainsString('AND o.status = :status_publicada', $sql);
        self::assertStringContainsString("bindValue(':status_publicada', 'publicada')", $sql);
        self::assertStringContainsString('if ($stmt->rowCount() !== 1)', $sql);
    }

    public function testCriacaoNaoAdicionaRestricaoIndevidaDePapel(): void
    {
        $body = self::body(InscricaoController::class, 'criar');

        self::assertStringContainsString('Authorization::requireAuth()', $body);
        self::assertStringNotContainsString("requireRole('usuario')", $body);
        self::assertStringContainsString('catch (DomainException $e)', $body);
        self::assertStringContainsString('], 404)', $body);
    }

    public function testUpdateEmpresaRevalidaEmpresaEStatusNoMesmoSql(): void
    {
        $sql = self::body(InscricaoRepository::class, 'atualizarStatusComObservacaoAutorizado');

        self::assertStringContainsString('INNER JOIN oportunidades o ON o.id = i.oportunidade_id', $sql);
        self::assertStringContainsString('WHERE i.id = :id', $sql);
        self::assertStringContainsString('AND o.empresa_id = :empresa_id', $sql);
        self::assertStringContainsString('AND i.status <> :status_cancelada', $sql);
        self::assertStringContainsString('if ($empresaId !== null)', $sql);
        self::assertStringContainsString('return $stmt->rowCount() > 0', $sql);
    }

    public function testServicoNaoAuditaOperacaoSeUpdateEscopadoFalha(): void
    {
        $service = self::body(InscricaoService::class, 'atualizarStatusPorEmpresaOuAdmin');

        self::assertStringContainsString('atualizarStatusComObservacaoAutorizado(', $service);
        self::assertStringContainsString('$empresaId', $service);
        self::assertStringContainsString('if (!$atualizou)', $service);
        self::assertStringContainsString("AuditLogger::log('inscricao_status_atualizado_por_empresa'", $service);
    }
}
