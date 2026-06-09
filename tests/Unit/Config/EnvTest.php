<?php
declare(strict_types=1);

namespace Tests\Unit\Config;

use ConectaEduca\Config\Env;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Configuração de ambiente')]
final class EnvTest extends TestCase
{
    private array $testKeys = [
        'TEST_CONECTAEDUCA_ENV_VALUE',
        'TEST_CONECTAEDUCA_REQUIRED_VALUE',
        'TEST_CONECTAEDUCA_BOOL_TRUE',
        'TEST_CONECTAEDUCA_BOOL_FALSE',
        'TEST_CONECTAEDUCA_BOOL_DEFAULT',
        'TEST_CONECTAEDUCA_MISSING_REQUIRED',
    ];

    protected function setUp(): void
    {
        foreach ($this->testKeys as $key) {
            unset($_ENV[$key], $_SERVER[$key]);
            putenv($key);
        }
    }

    protected function tearDown(): void
    {
        foreach ($this->testKeys as $key) {
            unset($_ENV[$key], $_SERVER[$key]);
            putenv($key);
        }
    }

    #[TestDox('Lê valor definido em variável de ambiente')]
    public function testGetReturnsValueFromEnv(): void
    {
        $_ENV['TEST_CONECTAEDUCA_ENV_VALUE'] = 'valor_teste';

        $this->assertSame(
            'valor_teste',
            Env::get('TEST_CONECTAEDUCA_ENV_VALUE')
        );
    }

    #[TestDox('Retorna valor padrão quando a variável está ausente')]
    public function testGetReturnsDefaultWhenVariableIsMissing(): void
    {
        $this->assertSame(
            'padrao',
            Env::get('TEST_CONECTAEDUCA_ENV_VALUE', 'padrao')
        );
    }

    #[TestDox('Retorna valor obrigatório quando a variável existe')]
    public function testRequiredReturnsValueWhenPresent(): void
    {
        $_ENV['TEST_CONECTAEDUCA_REQUIRED_VALUE'] = 'obrigatorio';

        $this->assertSame(
            'obrigatorio',
            Env::required('TEST_CONECTAEDUCA_REQUIRED_VALUE')
        );
    }

    #[TestDox('Lança exceção quando variável obrigatória está ausente')]
    public function testRequiredThrowsExceptionWhenMissing(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('Variável de ambiente obrigatória ausente');

        Env::required('TEST_CONECTAEDUCA_MISSING_REQUIRED');
    }

    #[TestDox('Interpreta valores verdadeiros como booleano true')]
    public function testBoolReturnsTrueForTruthyValues(): void
    {
        $_ENV['TEST_CONECTAEDUCA_BOOL_TRUE'] = 'true';

        $this->assertTrue(Env::bool('TEST_CONECTAEDUCA_BOOL_TRUE'));
    }

    #[TestDox('Interpreta valores não verdadeiros como booleano false')]
    public function testBoolReturnsFalseForNonTruthyValues(): void
    {
        $_ENV['TEST_CONECTAEDUCA_BOOL_FALSE'] = 'false';

        $this->assertFalse(Env::bool('TEST_CONECTAEDUCA_BOOL_FALSE'));
    }

    #[TestDox('Usa valor padrão quando variável booleana está ausente')]
    public function testBoolReturnsDefaultWhenVariableIsMissing(): void
    {
        $this->assertTrue(Env::bool('TEST_CONECTAEDUCA_BOOL_DEFAULT', true));
        $this->assertFalse(Env::bool('TEST_CONECTAEDUCA_BOOL_DEFAULT', false));
    }

    #[TestDox('Retorna o diretório raiz do projeto')]
    public function testRootPathReturnsProjectRoot(): void
    {
        $root = Env::rootPath();

        $this->assertDirectoryExists($root);
        $this->assertFileExists(Env::rootPath('composer.json'));
    }

    #[TestDox('Monta caminho relativo a partir da raiz do projeto')]
    public function testRootPathAppendsRelativePath(): void
    {
        $path = Env::rootPath('src/Config/Env.php');

        $this->assertFileExists($path);
        $this->assertStringEndsWith('/src/Config/Env.php', $path);
    }
}