<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use RuntimeException;

final class CognitoOAuthClient
{
    public static function authorizationUrl(): string
    {
        SecureSession::start();

        $domain = rtrim(Env::required('COGNITO_DOMAIN'), '/');
        $clientId = Env::required('COGNITO_CLIENT_ID');
        $redirectUri = Env::required('COGNITO_REDIRECT_URI');

        $state = bin2hex(random_bytes(32));
        $codeVerifier = self::base64UrlEncode(random_bytes(64));
        $codeChallenge = self::base64UrlEncode(hash('sha256', $codeVerifier, true));

        $_SESSION['oauth_state'] = $state;
        $_SESSION['oauth_code_verifier'] = $codeVerifier;

        $params = [
            'client_id' => $clientId,
            'response_type' => 'code',
            'scope' => Env::get('COGNITO_SCOPE', 'openid email profile'),
            'redirect_uri' => $redirectUri,
            'state' => $state,
            'code_challenge_method' => 'S256',
            'code_challenge' => $codeChallenge,
        ];

        return $domain . '/oauth2/authorize?' . http_build_query($params);
    }

    public static function exchangeCodeForTokens(string $code, string $state): array
    {
        SecureSession::start();

        if (empty($_SESSION['oauth_state']) || !hash_equals($_SESSION['oauth_state'], $state)) {
            AuditLogger::log('cognito_invalid_state');
            throw new RuntimeException('State OAuth inválido.');
        }

        if (empty($_SESSION['oauth_code_verifier'])) {
            throw new RuntimeException('Code verifier ausente na sessão.');
        }

        $domain = rtrim(Env::required('COGNITO_DOMAIN'), '/');
        $clientId = Env::required('COGNITO_CLIENT_ID');
        $clientSecret = Env::get('COGNITO_CLIENT_SECRET');
        $redirectUri = Env::required('COGNITO_REDIRECT_URI');

        $postFields = [
            'grant_type' => 'authorization_code',
            'client_id' => $clientId,
            'code' => $code,
            'redirect_uri' => $redirectUri,
            'code_verifier' => $_SESSION['oauth_code_verifier'],
        ];

        $headers = [
            'Content-Type: application/x-www-form-urlencoded',
        ];

        if ($clientSecret !== null && trim($clientSecret) !== '') {
            $headers[] = 'Authorization: Basic ' . base64_encode($clientId . ':' . $clientSecret);
        }

        $ch = curl_init($domain . '/oauth2/token');

        if ($ch === false) {
            throw new RuntimeException('Não foi possível iniciar cURL.');
        }

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query($postFields),
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
        ]);

        $response = curl_exec($ch);
        $httpCode = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $curlError = curl_error($ch);

        curl_close($ch);

        unset($_SESSION['oauth_state'], $_SESSION['oauth_code_verifier']);

        if ($response === false || $httpCode < 200 || $httpCode >= 300) {
            AuditLogger::log('cognito_token_exchange_failed', [
                'http_code' => $httpCode,
                'curl_error' => $curlError,
                'response' => is_string($response) ? $response : null,
            ]);

            throw new RuntimeException('Falha ao trocar authorization code por tokens.');
        }

        $tokens = json_decode($response, true);

        if (!is_array($tokens) || empty($tokens['id_token'])) {
            throw new RuntimeException('Resposta inválida do Cognito.');
        }

        return $tokens;
    }

    public static function logoutUrl(): string
    {
        $domain = rtrim(Env::required('COGNITO_DOMAIN'), '/');
        $clientId = Env::required('COGNITO_CLIENT_ID');
        $logoutUri = Env::get('COGNITO_LOGOUT_URI', Env::get('APP_URL', '/'));

        $params = [
            'client_id' => $clientId,
            'logout_uri' => $logoutUri,
        ];

        return $domain . '/logout?' . http_build_query($params);
    }

    private static function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}