<?php

declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Security\TrustedClientIp;
use PHPUnit\Framework\TestCase;

final class TrustedClientIpTest extends TestCase
{
    public function testClientesDistintosAtrasDoMesmoWafRecebemIdentificadoresDistintos(): void
    {
        $wafIp = '172.20.0.5';

        $primeiro = TrustedClientIp::resolve([
            'REMOTE_ADDR' => $wafIp,
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '198.51.100.10',
        ], [$wafIp]);

        $segundo = TrustedClientIp::resolve([
            'REMOTE_ADDR' => $wafIp,
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '198.51.100.11',
        ], [$wafIp]);

        self::assertSame('198.51.100.10', $primeiro);
        self::assertSame('198.51.100.11', $segundo);
        self::assertNotSame($primeiro, $segundo);
    }

    public function testHeaderForjadoEmAcessoDiretoNaoSobrescrevePeer(): void
    {
        self::assertSame('203.0.113.40', TrustedClientIp::resolve([
            'REMOTE_ADDR' => '203.0.113.40',
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '198.51.100.10',
        ], ['172.20.0.5']));
    }

    public function testXForwardedForNuncaEhFonteDeIdentidade(): void
    {
        self::assertSame('172.20.0.5', TrustedClientIp::resolve([
            'REMOTE_ADDR' => '172.20.0.5',
            'HTTP_X_FORWARDED_FOR' => '198.51.100.77',
        ], ['172.20.0.5']));
    }

    public function testFalhaDeResolucaoDoWafMantemPeerOriginal(): void
    {
        self::assertSame('172.20.0.5', TrustedClientIp::resolve([
            'REMOTE_ADDR' => '172.20.0.5',
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '198.51.100.10',
        ], []));
    }

    public function testListasOuCabecalhosInvalidosNaoSaoAceitos(): void
    {
        foreach ([
            '198.51.100.10, 203.0.113.20',
            '198.51.100.10:443',
            'not-an-ip',
            '',
        ] as $forjado) {
            self::assertSame('172.20.0.5', TrustedClientIp::resolve([
                'REMOTE_ADDR' => '172.20.0.5',
                'HTTP_X_CONECTAEDUCA_CLIENT_IP' => $forjado,
            ], ['172.20.0.5']));
        }
    }

    public function testSuportaIpv6ECanonicalizaOIdentificador(): void
    {
        self::assertSame('2001:db8::42', TrustedClientIp::resolve([
            'REMOTE_ADDR' => '172.20.0.5',
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '2001:0db8:0:0:0:0:0:0042',
        ], ['172.20.0.5']));
    }

    public function testPeerAusenteOuInvalidoNaoConfiaNoHeader(): void
    {
        self::assertSame('desconhecido', TrustedClientIp::resolve([
            'REMOTE_ADDR' => 'invalid peer',
            'HTTP_X_CONECTAEDUCA_CLIENT_IP' => '198.51.100.10',
        ], ['172.20.0.5']));
    }
}
