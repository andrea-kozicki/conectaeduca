# PKI interna e TLS confiável da aplicação — EP125

## Objetivo

A aplicação ConectaEduca na VM **EP125 (DMZ)** utiliza HTTPS com terminação TLS no WAF. Esta documentação registra a implantação de uma **CA interna exclusiva do laboratório ConectaEduca**, a emissão do certificado do endpoint e a validação ponta a ponta da cadeia de confiança.

O objetivo não foi apenas remover o aviso de certificado do navegador. A mudança fecha uma lacuna arquitetural: o cliente passa a validar criptograficamente a identidade do serviço exposto pela DMZ, em vez de depender de confiança implícita no endereço IP ou de exceções manuais no navegador.

## Posição na arquitetura

```text
Cliente / navegador
        |
        | HTTPS validado
        v
ConectaEduca Lab Root CA
        |
        | assina
        v
Certificado do WAF
        |
        v
EP125 — DMZ
        |
        +--> WAF / ModSecurity / OWASP CRS
        |
        v
      Nginx
        |
        v
      PHP-FPM
```

A terminação TLS permanece no WAF. O Nginx e o PHP-FPM não são expostos diretamente ao cliente quando o WAF está ativo.

## Identidade do endpoint

O certificado do serviço foi emitido especificamente para os identificadores usados na implantação:

```text
DNS: conectaeduca.local
IP:  192.168.6.34
```

Metadados públicos validados no endpoint:

```text
Subject:
  C=BR, ST=PR, L=Curitiba, O=ConectaEduca,
  OU=DMZ, CN=conectaeduca.local

Issuer:
  C=BR, ST=PR, L=Curitiba, O=ConectaEduca,
  OU=Experiencia Criativa 8,
  CN=ConectaEduca Lab Root CA

SAN:
  DNS:conectaeduca.local
  IP Address:192.168.6.34
```

Fingerprint SHA-256 do certificado promovido:

```text
89:35:0A:EC:31:19:C0:C9:AB:82:51:04:45:78:11:56:
04:46:94:B3:DD:63:6F:75:C2:37:55:F4:74:0A:AF:17
```

Fingerprint SHA-256 da CA pública:

```text
C4:CF:23:F1:1F:3C:2D:71:13:4D:4F:63:61:D3:6B:1F:
E1:F2:D9:72:E6:37:9C:E7:42:9F:F7:FD:18:48:59:D4
```

Os fingerprints são dados públicos e servem apenas para identificação e conferência de integridade.

## Arquivos versionados relacionados

A infraestrutura declarativa do TLS continua representada no repositório por:

```text
deploy/dmz/compose.waf.yml
deploy/dmz/compose.waf-tls.yml
deploy/dmz/compose.host.yml
deploy/dmz/nginx/app-https.conf
deploy/dmz/waf/README.md
```

O overlay `compose.waf-tls.yml` fornece ao WAF os caminhos dos secrets TLS e mantém apenas TLS 1.2 e TLS 1.3 habilitados.

Os artefatos reais de chave permanecem externos ao repositório.

## Material que NÃO pertence ao Git

Nunca devem ser versionados:

- chave privada da CA interna;
- chave privada do certificado do WAF;
- passphrases usadas no transporte;
- arquivos de secrets materializados no host;
- backups que contenham material privado.

O certificado público e a CA pública não são secretos, mas continuam tratados como artefatos de implantação, pois possuem ciclo de vida e validade próprios do ambiente.

## Fluxo de implantação realizado

### 1. Criação da CA

A CA `ConectaEduca Lab Root CA` foi criada fora da EP125. Sua chave privada permaneceu no ambiente de administração e não foi enviada ao servidor, ao GitHub ou às evidências.

### 2. Emissão do certificado do WAF

Foi emitido um certificado de servidor contendo simultaneamente:

- `DNS:conectaeduca.local`;
- `IP:192.168.6.34`.

Isso permite validar tanto o hostname planejado quanto o acesso direto por IP usado no laboratório.

### 3. Transporte controlado

Como a EP125 não estava alcançável por SSH a partir do cliente administrativo, o material necessário para a promoção foi transportado via Google Drive em pacote cifrado.

A proteção aplicada ao pacote foi:

```text
AES-256-CBC
+ PBKDF2-HMAC-SHA256
+ 300.000 iterações
+ HMAC-SHA256
```

A passphrase permaneceu fora da nuvem e a chave privada da CA não integrou o pacote.

Na EP125, o conteúdo foi decifrado temporariamente em `/dev/shm`, validado por SHA-256 e removido após o uso.

Resultado do checkpoint de transporte:

```text
PASS=7
WARN=0
FAIL=0
PERSISTENT_EXTRACTION=0
WAF_MUTATION_PERFORMED=0
```

### 4. Promoção do certificado

A promoção do certificado:

1. validou certificado, chave, CA e SANs;
2. identificou os secret mounts já usados pelo WAF;
3. criou backup pré-mudança;
4. substituiu somente o material TLS;
5. reiniciou apenas o WAF;
6. aguardou o healthcheck;
7. validou o certificado realmente apresentado em TCP/443;
8. preservou rollback automático em caso de falha.

O Nginx e o PHP-FPM não foram reiniciados pela operação.

Resultado:

```text
PASS=18
WARN=0
FAIL=0
ROLLBACK_USED=0

WAF_STATUS=running|healthy
HTTP_IP=200
HTTP_DNS=200
```

Backup pré-mudança:

```text
/var/backups/conectaeduca/tls/20260911-185010
```

## Validação da cadeia de confiança

A validação foi feita em mais de uma camada para evitar concluir sucesso apenas porque o serviço respondia HTTPS.

### Sistema operacional da EP125

A CA pública foi adicionada ao trust store do Ubuntu da EP125.

Resultado de `curl` sem `-k` / `--insecure`:

```text
HTTP=200
VERIFY=0
```

Resultado do OpenSSL:

```text
Verify return code: 0 (ok)
```

Isso comprova que o sistema operacional reconhece a cadeia como válida.

### Navegador Chrome

O Chrome da VM utilizada na demonstração manteve inicialmente sua própria avaliação de confiança e apresentou:

```text
NET::ERR_CERT_AUTHORITY_INVALID
```

A CA pública foi então adicionada em:

```text
Gestor de certificados
  -> Certificados locais
  -> Instalados por si
  -> Certificados fidedignos
```

Após a atualização do navegador, o acesso a:

```text
https://192.168.6.34
```

passou a ser exibido como:

```text
A ligação é segura
```

Esse comportamento evidencia a diferença entre o trust store do sistema operacional e o mecanismo de confiança usado pela aplicação cliente.

## Impacto arquitetural

A implantação acrescenta quatro propriedades importantes ao caminho de entrada da aplicação:

### Confidencialidade

O tráfego entre o cliente e o WAF é cifrado.

### Integridade

Alterações no tráfego protegido pelo TLS são detectadas durante a comunicação.

### Autenticação do servidor

O cliente pode verificar que o endpoint apresentado corresponde ao serviço autorizado do ConectaEduca, em vez de confiar somente em IP ou hostname.

### Governança de confiança

A emissão de certificados do ambiente passa a depender de uma autoridade interna controlada pelo projeto.

Isso complementa, sem substituir, as demais camadas:

```text
TLS
  -> identidade do endpoint + proteção do canal

WAF
  -> inspeção e bloqueio de requisições HTTP maliciosas

RBAC
  -> autorização de usuários autenticados

Wazuh / Auditd / FIM
  -> detecção, correlação e auditoria

OpenBao
  -> governança de segredos
```

## Relação com defesa em profundidade

TLS não impede SQL Injection, XSS, abuso de privilégios ou comprometimento do servidor. Da mesma forma, o WAF não substitui a validação de identidade do endpoint.

A arquitetura combina controles independentes para que uma camada não seja tratada como substituta das demais.

Um fluxo resumido da mudança é:

```text
Criação da CA
      |
      v
Emissão do certificado
      |
      v
Secret TLS do WAF
      |
      v
Restart isolado do WAF
      |
      v
OpenSSL Verify = 0
      |
      v
curl ssl_verify_result = 0
      |
      v
Chrome: "A ligação é segura"
```

## Operação e renovação

Antes do vencimento do certificado do WAF, um novo certificado deve ser emitido pela mesma CA ou por uma CA sucessora explicitamente aprovada.

A renovação deve repetir, no mínimo:

1. validação de SANs;
2. conferência certificado/chave;
3. backup do material anterior;
4. promoção isolada;
5. healthcheck do WAF;
6. validação OpenSSL;
7. validação HTTP sem bypass TLS;
8. conferência visual no navegador.

A chave privada da CA não deve ser copiada para a EP125 como parte desse processo.

## Evoluções possíveis

Não fazem parte desta implantação atual, mas a PKI interna cria base para evoluções futuras, como:

- emissão de certificados por OpenBao PKI;
- mTLS entre serviços selecionados;
- identidade de máquina para componentes internos;
- integração com políticas de Zero Trust;
- rotação automatizada de certificados.

Essas evoluções devem ser tratadas como trabalhos separados, com modelo de ameaça e justificativa próprios.

## Estado

**Implantação concluída e validada em 11/09/2026.**

Critérios de encerramento atingidos:

- certificado correto apresentado pelo WAF;
- SAN DNS e IP corretos;
- WAF saudável;
- HTTPS 200 por IP e DNS;
- cadeia validada pelo sistema operacional;
- cadeia validada por OpenSSL;
- cadeia validada por `curl` sem bypass;
- CA reconhecida como confiável no Chrome;
- navegador exibindo conexão segura;
- rollback não utilizado;
- nenhuma chave privada versionada.
