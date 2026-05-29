<?php
declare(strict_types=1);

namespace Tests\Unit\Config;

use ConectaEduca\Config\Env;
use PHPUnit\Framework\TestCase;
use RuntimeException;

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

    public function testGetReturnsValueFromEnv(): void
    {
        $_ENV['TEST_CONECTAEDUCA_ENV_VALUE'] = 'valor_teste';

        $this->assertSame(
            'valor_teste',
            Env::get('TEST_CONECTAEDUCA_ENV_VALUE')
        );
    }

    public function testGetReturnsDefaultWhenVariableIsMissing(): void
    {
        $this->assertSame(
            'padrao',
            Env::get('TEST_CONECTAEDUCA_ENV_VALUE', 'padrao')
        );
    }

    public function testRequiredReturnsValueWhenPresent(): void
    {
        $_ENV['TEST_CONECTAEDUCA_REQUIRED_VALUE'] = 'obrigatorio';

        $this->assertSame(
            'obrigatorio',
            Env::required('TEST_CONECTAEDUCA_REQUIRED_VALUE')
        );
    }

    public function testRequiredThrowsExceptionWhenMissing(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('Variável de ambiente obrigatória ausente');

        Env::required('TEST_CONECTAEDUCA_MISSING_REQUIRED');
    }

    public function testBoolReturnsTrueForTruthyValues(): void
    {
        $_ENV['TEST_CONECTAEDUCA_BOOL_TRUE'] = 'true';

        $this->assertTrue(Env::bool('TEST_CONECTAEDUCA_BOOL_TRUE'));
    }

    public function testBoolReturnsFalseForNonTruthyValues(): void
    {
        $_ENV['TEST_CONECTAEDUCA_BOOL_FALSE'] = 'false';

        $this->assertFalse(Env::bool('TEST_CONECTAEDUCA_BOOL_FALSE'));
    }

    public function testBoolReturnsDefaultWhenVariableIsMissing(): void
    {
        $this->assertTrue(Env::bool('TEST_CONECTAEDUCA_BOOL_DEFAULT', true));
        $this->assertFalse(Env::bool('TEST_CONECTAEDUCA_BOOL_DEFAULT', false));
    }

    public function testRootPathReturnsProjectRoot(): void
    {
        $root = Env::rootPath();

        $this->assertDirectoryExists($root);
        $this->assertFileExists(Env::rootPath('composer.json'));
    }

    public function testRootPathAppendsRelativePath(): void
    {
        $path = Env::rootPath('src/Config/Env.php');

        $this->assertFileExists($path);
        $this->assertStringEndsWith('/src/Config/Env.php', $path);
    }
}