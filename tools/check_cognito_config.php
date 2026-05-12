<?php
declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use ConectaEduca\Config\Env;

$required = [
    'COGNITO_REGION',
    'COGNITO_USER_POOL_ID',
    'COGNITO_CLIENT_ID',
    'COGNITO_DOMAIN',
    'COGNITO_REDIRECT_URI',
    'COGNITO_LOGOUT_URI',
    'COGNITO_SCOPE',
];

echo "### Checagem de configuração Amazon Cognito\n\n";

$ok = true;

foreach ($required as $key) {
    $value = Env::get($key);

    if ($value === null || trim($value) === '') {
        echo "[ERRO] {$key} não configurado.\n";
        $ok = false;
        continue;
    }

    echo "[OK] {$key} = {$value}\n";
}

$secret = Env::get('COGNITO_CLIENT_SECRET');

if ($secret === null || trim($secret) === '') {
    echo "[INFO] COGNITO_CLIENT_SECRET vazio. App client provavelmente está sem secret.\n";
} else {
    echo "[OK] COGNITO_CLIENT_SECRET = [OCULTO]\n";
}

echo "\n### Validações simples\n";

$region = Env::get('COGNITO_REGION');
$userPoolId = Env::get('COGNITO_USER_POOL_ID');
$domain = rtrim((string) Env::get('COGNITO_DOMAIN'), '/');
$redirectUri = Env::get('COGNITO_REDIRECT_URI');
$scope = Env::get('COGNITO_SCOPE', '');

if ($region !== null && $userPoolId !== null && !str_starts_with($userPoolId, $region . '_')) {
    echo "[AVISO] O User Pool ID não parece começar com a região informada.\n";
    echo "        Exemplo esperado: {$region}_XXXXXXXXX\n";
} else {
    echo "[OK] User Pool ID parece compatível com a região.\n";
}

if ($domain !== '' && !str_starts_with($domain, 'https://')) {
    echo "[ERRO] COGNITO_DOMAIN deve começar com https://\n";
    $ok = false;
} else {
    echo "[OK] COGNITO_DOMAIN usa HTTPS.\n";
}

if ($redirectUri !== null && !str_starts_with($redirectUri, 'https://')) {
    echo "[AVISO] COGNITO_REDIRECT_URI não está em HTTPS.\n";
    echo "        Para seu projeto atual, prefira https://conectaeduca.local/callback.php\n";
} else {
    echo "[OK] COGNITO_REDIRECT_URI usa HTTPS.\n";
}

foreach (['openid', 'email', 'profile'] as $neededScope) {
    if (!str_contains((string) $scope, $neededScope)) {
        echo "[AVISO] Escopo ausente: {$neededScope}\n";
    } else {
        echo "[OK] Escopo presente: {$neededScope}\n";
    }
}

if ($domain !== '' && Env::get('COGNITO_CLIENT_ID') !== null && $redirectUri !== null) {
    $params = [
        'client_id' => Env::get('COGNITO_CLIENT_ID'),
        'response_type' => 'code',
        'scope' => $scope,
        'redirect_uri' => $redirectUri,
        'state' => 'TESTE_STATE_NAO_USAR_EM_PRODUCAO',
        'code_challenge_method' => 'S256',
        'code_challenge' => 'TESTE_CODE_CHALLENGE_NAO_USAR_EM_PRODUCAO',
    ];

    echo "\n### URL de autorização aproximada\n";
    echo $domain . '/oauth2/authorize?' . http_build_query($params) . "\n";
}

echo "\n### Resultado\n";

if ($ok) {
    echo "Configuração mínima parece preenchida. Agora confira se as mesmas URLs estão cadastradas no App Client do Cognito.\n";
    exit(0);
}

echo "Há problemas de configuração a corrigir.\n";
exit(1);
