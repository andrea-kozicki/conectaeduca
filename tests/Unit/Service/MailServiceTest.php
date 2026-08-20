<?php
declare(strict_types=1);

namespace Tests\Unit\Service;

use ConectaEduca\Service\MailService;
use InvalidArgumentException;
use PHPMailer\PHPMailer\PHPMailer;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

final class FakePHPMailer extends PHPMailer
{
    public bool $sendCalled = false;
    public bool $sendResult = true;

    public function __construct()
    {
        parent::__construct(true);
    }

    public function send()
    {
        $this->sendCalled = true;

        return $this->sendResult;
    }
}

#[TestDox('Serviço de e-mail SMTP')]
final class MailServiceTest extends TestCase
{
    private array $envKeys = [
        'APP_ENV',
        'MAIL_HOST',
        'MAIL_PORT',
        'MAIL_SMTP_AUTH',
        'MAIL_USERNAME',
        'MAIL_PASSWORD',
        'MAIL_PASSWORD_FILE',
        'MAIL_ENCRYPTION',
        'MAIL_TIMEOUT',
        'MAIL_FROM_ADDRESS',
        'MAIL_FROM_NAME',
    ];

    protected function setUp(): void
    {
        $this->clearEnvironment();

        $_ENV['APP_ENV'] = 'test';
        $_ENV['MAIL_HOST'] = 'smtp.exemplo.test';
        $_ENV['MAIL_PORT'] = '587';
        $_ENV['MAIL_SMTP_AUTH'] = 'true';
        $_ENV['MAIL_USERNAME'] = 'smtp-user';
        $_ENV['MAIL_PASSWORD'] = 'segredo-de-teste';
        $_ENV['MAIL_ENCRYPTION'] = 'tls';
        $_ENV['MAIL_TIMEOUT'] = '10';
        $_ENV['MAIL_FROM_ADDRESS'] = 'nao-responda@exemplo.test';
        $_ENV['MAIL_FROM_NAME'] = 'ConectaEduca';
    }

    protected function tearDown(): void
    {
        $this->clearEnvironment();
    }

    #[TestDox('Configura STARTTLS e monta mensagem HTML sem acessar a rede')]
    public function testConfiguresStartTlsAndBuildsHtmlMessage(): void
    {
        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $service->sendHtml(
            'destino@exemplo.test',
            'Pessoa Teste',
            'Ative sua conta',
            '<p>Olá <strong>mundo</strong><br>Ative sua conta.</p>'
        );

        self::assertTrue($mailer->sendCalled);
        self::assertSame('smtp', $mailer->Mailer);
        self::assertSame('smtp.exemplo.test', $mailer->Host);
        self::assertSame(587, $mailer->Port);
        self::assertTrue($mailer->SMTPAuth);
        self::assertSame('smtp-user', $mailer->Username);
        self::assertSame('segredo-de-teste', $mailer->Password);
        self::assertSame(PHPMailer::ENCRYPTION_STARTTLS, $mailer->SMTPSecure);
        self::assertTrue($mailer->SMTPOptions['ssl']['verify_peer']);
        self::assertTrue($mailer->SMTPOptions['ssl']['verify_peer_name']);
        self::assertFalse($mailer->SMTPOptions['ssl']['allow_self_signed']);
        self::assertSame(PHPMailer::CHARSET_UTF8, $mailer->CharSet);
        self::assertSame(10, $mailer->Timeout);
        self::assertSame('nao-responda@exemplo.test', $mailer->From);
        self::assertSame('ConectaEduca', $mailer->FromName);
        self::assertSame('Ative sua conta', $mailer->Subject);
        self::assertSame('<p>Olá <strong>mundo</strong><br>Ative sua conta.</p>', $mailer->Body);
        self::assertStringContainsString('Ative sua conta.', $mailer->AltBody);
        self::assertSame(
            [['destino@exemplo.test', 'Pessoa Teste']],
            $mailer->getToAddresses()
        );
    }

    #[TestDox('Permite SMTP local sem autenticação e sem TLS explícito')]
    public function testAllowsLocalSmtpWithoutAuthentication(): void
    {
        $_ENV['MAIL_HOST'] = '127.0.0.1';
        $_ENV['MAIL_PORT'] = '1025';
        $_ENV['MAIL_SMTP_AUTH'] = 'false';
        $_ENV['MAIL_ENCRYPTION'] = 'none';
        unset($_ENV['MAIL_USERNAME'], $_ENV['MAIL_PASSWORD']);

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Mensagem local',
            '<p>Teste local.</p>',
            'Teste local.'
        );

        self::assertTrue($mailer->sendCalled);
        self::assertFalse($mailer->SMTPAuth);
        self::assertSame('', $mailer->Username);
        self::assertSame('', $mailer->Password);
        self::assertSame('', $mailer->SMTPSecure);
        self::assertFalse($mailer->SMTPAutoTLS);
        self::assertSame(1025, $mailer->Port);
    }

    #[TestDox('Configura SMTPS com validação estrita do certificado do servidor')]
    public function testConfiguresSmtpsWithStrictPeerVerification(): void
    {
        $_ENV['MAIL_PORT'] = '465';
        $_ENV['MAIL_ENCRYPTION'] = 'smtps';

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Mensagem SMTPS',
            '<p>Teste.</p>'
        );

        self::assertSame(PHPMailer::ENCRYPTION_SMTPS, $mailer->SMTPSecure);
        self::assertTrue($mailer->SMTPAutoTLS);
        self::assertTrue($mailer->SMTPOptions['ssl']['verify_peer']);
        self::assertTrue($mailer->SMTPOptions['ssl']['verify_peer_name']);
        self::assertFalse($mailer->SMTPOptions['ssl']['allow_self_signed']);
    }

    #[TestDox('Rejeita destinatário inválido antes do envio')]
    public function testRejectsInvalidRecipient(): void
    {
        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('destino inválido');

        $service->sendHtml(
            "invalido\r\nBcc: atacante@exemplo.test",
            '',
            'Assunto',
            '<p>Mensagem</p>'
        );
    }

    #[TestDox('Rejeita quebra de linha no assunto')]
    public function testRejectsHeaderInjectionInSubject(): void
    {
        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Assunto de e-mail inválido');

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            "Assunto\r\nBcc: atacante@exemplo.test",
            '<p>Mensagem</p>'
        );
    }

    #[TestDox('Exige credenciais quando SMTPAuth está habilitado')]
    public function testRequiresCredentialsWhenSmtpAuthIsEnabled(): void
    {
        $_ENV['MAIL_PASSWORD'] = '';
        $_SERVER['MAIL_PASSWORD'] = '';
        putenv('MAIL_PASSWORD=');

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('MAIL_PASSWORD');

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Assunto',
            '<p>Mensagem</p>'
        );
    }

    #[TestDox('Falha de transporte retorna erro genérico sem expor credenciais')]
    public function testTransportFailureDoesNotExposeCredentials(): void
    {
        $mailer = new FakePHPMailer();
        $mailer->sendResult = false;
        $logs = [];

        $service = new MailService(
            static fn (): PHPMailer => $mailer,
            static function (string $message) use (&$logs): void {
                $logs[] = $message;
            }
        );

        try {
            $service->sendHtml(
                'destino@exemplo.test',
                '',
                'Assunto',
                '<p>Mensagem</p>'
            );
            self::fail('Era esperada RuntimeException.');
        } catch (RuntimeException $e) {
            self::assertSame('Não foi possível enviar o e-mail.', $e->getMessage());
            self::assertStringNotContainsString('segredo-de-teste', $e->getMessage());
            self::assertStringNotContainsString('smtp-user', $e->getMessage());

            self::assertSame(['[MAIL_ERROR] Falha no envio SMTP.'], $logs);

            $log = implode("\n", $logs);
            self::assertStringNotContainsString('segredo-de-teste', $log);
            self::assertStringNotContainsString('smtp-user', $log);
        }
    }

    #[TestDox('Rejeita configuração de criptografia desconhecida')]
    public function testRejectsUnknownEncryptionMode(): void
    {
        $_ENV['MAIL_ENCRYPTION'] = 'inseguro-qualquer';

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('MAIL_ENCRYPTION');

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Assunto',
            '<p>Mensagem</p>'
        );
    }


    #[TestDox('Rejeita SMTP sem TLS quando autenticação está habilitada')]
    public function testRejectsPlainSmtpWhenAuthenticationIsEnabled(): void
    {
        $_ENV['MAIL_ENCRYPTION'] = 'none';
        $_ENV['MAIL_SMTP_AUTH'] = 'true';

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('MAIL_ENCRYPTION=none');

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Assunto',
            '<p>Mensagem</p>'
        );
    }

    #[TestDox('Rejeita SMTP sem TLS fora de desenvolvimento ou teste')]
    public function testRejectsPlainSmtpOutsideDevelopmentOrTest(): void
    {
        $_ENV['APP_ENV'] = 'production';
        $_ENV['MAIL_ENCRYPTION'] = 'none';
        $_ENV['MAIL_SMTP_AUTH'] = 'false';

        $mailer = new FakePHPMailer();
        $service = new MailService(static fn (): PHPMailer => $mailer);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('MAIL_ENCRYPTION=none');

        $service->sendHtml(
            'destino@exemplo.test',
            '',
            'Assunto',
            '<p>Mensagem</p>'
        );
    }

    private function clearEnvironment(): void
    {
        foreach ($this->envKeys as $key) {
            unset($_ENV[$key], $_SERVER[$key]);
            putenv($key);
        }
    }
}
