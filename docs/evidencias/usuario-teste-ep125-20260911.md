# Evidência sanitizada — usuário teste / EP125

Data: 11/09/2026  
Host: ep125-pucpr  
Zona: DMZ  
Objetivo: comprovar privilégio mínimo do usuário de sistema teste.

## Resultado final

    HOST=ep125-pucpr
    USER=teste
    UID=1001
    GID=1001
    GROUPS=teste users
    HOME=/home/teste
    SHELL=/bin/bash
    PRIVILEGED_GROUPS=none
    SUDO_ALLOWED=no
    ETC_SHADOW_READABLE=no
    ETC_WRITABLE=no

    PASS=9
    WARN=0
    FAIL=0
    GAP=0

Conclusão:

    [PASS] Critério de privilégio mínimo atendido na EP125.

## Rastreabilidade do processo

A validação final foi precedida por:

1. primeira tentativa que criou a conta sem senha e falhou ao executar passwd;
2. diagnóstico da política sudo, confirmando bloqueio explícito de /usr/bin/passwd;
3. recriação controlada pelo fluxo permitido de adduser;
4. aceitação da senha padrão definida pela atividade, sem alteração da política global de PAM;
5. correção de um defeito no coletor de evidência e nova validação somente leitura.

Detalhes completos: ../seguranca/PRIVILEGIO-MINIMO-USUARIO-EP125.md

## Sanitização

Este arquivo não contém senha, hash de senha, tokens, segredos, conteúdo de /etc/shadow ou qualquer material de autenticação.
