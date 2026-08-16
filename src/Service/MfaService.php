<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use BaconQrCode\Renderer\Image\SvgImageBackEnd;
use BaconQrCode\Renderer\ImageRenderer;
use BaconQrCode\Renderer\RendererStyle\RendererStyle;
use BaconQrCode\Writer;
use ConectaEduca\Config\Database;
use ConectaEduca\Repository\MfaRepository;
use ConectaEduca\Security\CryptoHybrid;
use DomainException;
use JsonException;
use PragmaRX\Google2FA\Google2FA;
use RuntimeException;

final class MfaService
{
    private const ISSUER = 'ConectaEduca';
    private const SECRET_LENGTH = 32;

    private MfaRepository $mfa;
    private Google2FA $google2fa;

    public function __construct()
    {
        $this->mfa = new MfaRepository(
            Database::connect()
        );

        $this->google2fa = new Google2FA();
    }

    public function prepararConfiguracao(
        int $usuarioId,
        string $email
    ): array {
        if ($usuarioId < 1) {
            throw new DomainException(
                'Usuário inválido para configuração do MFA.'
            );
        }

        $email = trim($email);

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new DomainException(
                'E-mail inválido para configuração do MFA.'
            );
        }

        $registro = $this->mfa
            ->buscarPorUsuarioId($usuarioId);

        if ($registro !== null) {
            if (
                (int) $registro['ativo'] === 1
                && (int) $registro['qr_confirmado'] === 1
            ) {
                throw new DomainException(
                    'O MFA já está configurado para esta conta.'
                );
            }

            /*
             * Há uma configuração ainda não confirmada.
             * Reutilizamos o mesmo segredo para que atualizar
             * a página não invalide o QR já escaneado.
             */
            $segredo = $this->descriptografarSegredo(
                (string) $registro['segredo_totp_envelope']
            );

            return $this->dadosConfiguracao(
                $segredo,
                $email
            );
        }

        return $this->criarNovaConfiguracaoPendente(
            $usuarioId,
            $email
        );
    }

    /**
     * Inicia uma reconfiguração após a validação de um código
     * de recuperação. O segredo anterior é sempre substituído.
     */
    public function iniciarReconfiguracao(
        int $usuarioId,
        string $email
    ): array {
        if ($usuarioId < 1) {
            throw new DomainException(
                'Usuário inválido para reconfiguração do MFA.'
            );
        }

        $email = trim($email);

        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new DomainException(
                'E-mail inválido para reconfiguração do MFA.'
            );
        }

        return $this->criarNovaConfiguracaoPendente(
            $usuarioId,
            $email
        );
    }

    public function confirmarConfiguracao(
        int $usuarioId,
        string $codigo
    ): bool {
        $registro = $this->mfa
            ->buscarPorUsuarioId($usuarioId);

        if ($registro === null) {
            throw new DomainException(
                'Configuração MFA não encontrada.'
            );
        }

        $segredo = $this->descriptografarSegredo(
            (string) $registro['segredo_totp_envelope']
        );

        $codigo = self::normalizarCodigo($codigo);

        if ($codigo === null) {
            return false;
        }

        $passo = $this->google2fa->verifyKeyNewer(
            $segredo,
            $codigo,
            0
        );

        if ($passo === false) {
            return false;
        }

        $this->mfa->ativarConfiguracao(
            $usuarioId,
            (int) $passo
        );

        return true;
    }

    public function validarCodigo(
        int $usuarioId,
        string $codigo
    ): bool {
        $registro = $this->mfa
            ->buscarPorUsuarioId($usuarioId);

        if (
            $registro === null
            || (int) $registro['ativo'] !== 1
            || (int) $registro['qr_confirmado'] !== 1
        ) {
            return false;
        }

        $codigo = self::normalizarCodigo($codigo);

        if ($codigo === null) {
            return false;
        }

        $segredo = $this->descriptografarSegredo(
            (string) $registro['segredo_totp_envelope']
        );

        $ultimoPasso =
            $registro['ultimo_passo_totp'] !== null
                ? (int) $registro['ultimo_passo_totp']
                : 0;

        $novoPasso = $this->google2fa->verifyKeyNewer(
            $segredo,
            $codigo,
            $ultimoPasso
        );

        if ($novoPasso === false) {
            return false;
        }

        /*
         * Mesmo que duas requisições concorrentes validem o mesmo
         * TOTP, somente uma poderá persistir o novo passo.
         */
        return $this->mfa->registrarPassoSeNovo(
            $usuarioId,
            (int) $novoPasso
        );
    }

    public function configurado(
        int $usuarioId
    ): bool {
        $registro = $this->mfa
            ->buscarPorUsuarioId($usuarioId);

        return
            $registro !== null
            && (int) $registro['ativo'] === 1
            && (int) $registro['qr_confirmado'] === 1;
    }

    private function criarNovaConfiguracaoPendente(
        int $usuarioId,
        string $email
    ): array {
        $segredo = $this->google2fa
            ->generateSecretKey(
                self::SECRET_LENGTH
            );

        $envelope = CryptoHybrid::encryptString(
            $segredo
        );

        $envelopeJson = json_encode(
            $envelope,
            JSON_UNESCAPED_SLASHES
            | JSON_THROW_ON_ERROR
        );

        $this->mfa->salvarConfiguracaoPendente(
            $usuarioId,
            $envelopeJson
        );

        return $this->dadosConfiguracao(
            $segredo,
            $email
        );
    }

    private function dadosConfiguracao(
        string $segredo,
        string $email
    ): array {
        $uri = $this->google2fa->getQRCodeUrl(
            self::ISSUER,
            $email,
            $segredo
        );

        $renderer = new ImageRenderer(
            new RendererStyle(300),
            new SvgImageBackEnd()
        );

        $writer = new Writer($renderer);

        $svg = $writer->writeString($uri);

        return [
            'segredo' => $segredo,
            'qr_data_uri' =>
                'data:image/svg+xml;base64,'
                . base64_encode($svg),
        ];
    }

    private function descriptografarSegredo(
        string $envelopeJson
    ): string {
        try {
            $payload = json_decode(
                $envelopeJson,
                true,
                512,
                JSON_THROW_ON_ERROR
            );
        } catch (JsonException $e) {
            throw new RuntimeException(
                'Envelope MFA armazenado é inválido.',
                0,
                $e
            );
        }

        if (!is_array($payload)) {
            throw new RuntimeException(
                'Envelope MFA armazenado é inválido.'
            );
        }

        return CryptoHybrid::decryptString(
            $payload
        );
    }

    private static function normalizarCodigo(
        string $codigo
    ): ?string {
        $codigo = preg_replace(
            '/\D+/',
            '',
            $codigo
        );

        if (
            !is_string($codigo)
            || !preg_match('/^\d{6}$/', $codigo)
        ) {
            return null;
        }

        return $codigo;
    }
}
