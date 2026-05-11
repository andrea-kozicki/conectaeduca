<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class CognitoConfigTest extends TestCase
{
    public function testConfiguracaoCognitoPendente(): void
    {
        self::markTestSkipped(
            'Teste de integração pendente: depende da configuração real do Amazon Cognito no .env.'
        );
    }
}