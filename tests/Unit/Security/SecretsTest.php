<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\Secrets;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Resolução segura de segredos')]
final class SecretsTest extends TestCase
{
    /** @var list<string> */
    private array $envKeys = [
        'CE_SECRET_TEST',
        'CE_SECRET_TEST_FILE',
        'CE_OPTIONAL_TEST',
        'CE_OPTIONAL_TEST_FILE',
        'CE_PATH_TEST',
    ];

    /** @var list<string> */
    private array $temporaryFiles = [];

    protected function setUp(): void
    {
        $this->clearEnvironment();
    }

    protected function tearDown(): void
    {
        foreach ($this->temporaryFiles as $file) {
            @unlink($file);
        }

        $this->clearEnvironment();
    }

    #[TestDox('Valor direto tem precedência sobre KEY_FILE')]
    public function testDirectValueTakesPrecedenceOverFile(): void
    {
        $file = $this->tempSecret("valor-do-arquivo\n");
        $_ENV['CE_SECRET_TEST'] = 'valor-direto';
        $_ENV['CE_SECRET_TEST_FILE'] = $file;

        self::assertSame('valor-direto', Secrets::get('CE_SECRET_TEST'));
    }

    #[TestDox('Lê segredo por KEY_FILE quando valor direto não existe')]
    public function testReadsSecretFromFileFallback(): void
    {
        $file = $this->tempSecret("segredo-de-arquivo\n");
        $_ENV['CE_SECRET_TEST_FILE'] = $file;

        self::assertSame('segredo-de-arquivo', Secrets::get('CE_SECRET_TEST'));
    }

    #[TestDox('Remove apenas CR e LF finais de segredo montado em arquivo')]
    public function testRemovesOnlyTrailingLineBreaks(): void
    {
        $file = $this->tempSecret(" segredo com espaços \r\n");
        $_ENV['CE_SECRET_TEST_FILE'] = $file;

        self::assertSame(' segredo com espaços ', Secrets::get('CE_SECRET_TEST'));
    }

    #[TestDox('Segredo opcional retorna fallback quando não configurado')]
    public function testOptionalSecretUsesDefault(): void
    {
        self::assertSame('fallback', Secrets::optional('CE_OPTIONAL_TEST', 'fallback'));
    }

    #[TestDox('Rejeita segredo obrigatório sem valor direto ou arquivo')]
    public function testRequiredSecretRejectsMissingConfiguration(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('CE_SECRET_TEST');

        Secrets::get('CE_SECRET_TEST');
    }

    #[TestDox('Rejeita arquivo de segredo inexistente')]
    public function testRejectsMissingSecretFile(): void
    {
        $_ENV['CE_SECRET_TEST_FILE'] = sys_get_temp_dir() . '/conectaeduca-nao-existe-' . bin2hex(random_bytes(5));

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('CE_SECRET_TEST_FILE');

        Secrets::get('CE_SECRET_TEST');
    }

    #[TestDox('Resolve caminho de arquivo secreto informado por variável')]
    public function testFilePathReturnsReadableConfiguredFile(): void
    {
        $file = $this->tempSecret('material');
        $_ENV['CE_PATH_TEST'] = $file;

        self::assertSame($file, Secrets::filePath('CE_PATH_TEST'));
    }

    private function tempSecret(string $contents): string
    {
        $file = tempnam(sys_get_temp_dir(), 'ce-secret-');

        if ($file === false) {
            self::fail('Não foi possível criar arquivo temporário para o teste.');
        }

        file_put_contents($file, $contents);
        $this->temporaryFiles[] = $file;

        return $file;
    }

    private function clearEnvironment(): void
    {
        foreach ($this->envKeys as $key) {
            unset($_ENV[$key], $_SERVER[$key]);
            putenv($key);
        }
    }
}
