# Privilégio mínimo — criação e validação do usuário de sistema teste na EP125

## Objetivo

Registrar de forma rastreável a criação do usuário de sistema teste na VM EP125 / DMZ, conforme requisito da atividade acadêmica de Experiência Criativa 8, aplicando o princípio de menor privilégio e preservando a política administrativa da VM.

A senha padrão definida para a atividade foi utilizada, mas seu valor não é registrado neste documento, no Git, no Trello, nos relatórios ou nas evidências.

## Critérios de aceite

A conta deveria:

- existir como usuário local comum;
- possuir UID diferente de 0;
- utilizar home próprio;
- autenticar com a senha padrão definida na atividade;
- não pertencer a grupos administrativos ou sensíveis;
- não possuir autorização sudo;
- não ler /etc/shadow;
- não possuir escrita direta em /etc;
- não exigir alteração global de PAM, sudoers ou política de senhas.

## Ambiente

VM: EP125  
Hostname: ep125-pucpr  
Zona: DMZ  
Sistema: Ubuntu  
Usuário administrativo do laboratório: andrea.kiew  
Usuário criado: teste

## Linha do tempo da execução

### 1. Primeira tentativa

O primeiro procedimento criou a conta teste com adduser --disabled-password e tentou, em seguida, definir a senha com sudo passwd teste.

A conta foi criada, porém a etapa de senha falhou antes de permitir a digitação.

Resultado da primeira execução:

    [PASS] Host correto confirmado: ep125-pucpr.
    [PASS] Ferramentas mínimas disponíveis.
    [PASS] Usuário local teste criado.
    [FAIL] Não foi possível definir a senha do usuário.

    PASS=3 WARN=0 FAIL=1 GAP=0

A falha foi tratada como falha segura: nenhum privilégio foi concedido e nenhuma alteração em sudoers, PAM ou grupos foi realizada para contornar o bloqueio.

### 2. Reprodução manual da falha

A tentativa direta confirmou que o problema não era a senha, mas uma restrição administrativa explícita da VM:

    sudo passwd teste

    Sorry, user andrea.kiew is not allowed to execute
    '/usr/bin/passwd teste' as root on ep125-pucpr.

### 3. Diagnóstico da política sudo

Foi executado um diagnóstico somente leitura com sudo -l.

A política da conta administrativa permite um conjunto amplo de comandos, porém contém bloqueios explícitos, entre outros, para /usr/bin/passwd, /usr/sbin/useradd, /bin/su, /usr/sbin/visudo, shells privilegiados e edição direta de arquivos sensíveis.

Ao mesmo tempo, o utilitário adduser não estava bloqueado.

O diagnóstico também confirmou que a conta incompleta criada na primeira tentativa era um usuário comum:

    uid=1001(teste) gid=1001(teste) groups=1001(teste),100(users)
    HOME=/home/teste
    SHELL=/bin/bash

Resultado do diagnóstico:

    PASS=4 WARN=0 FAIL=0 GAP=0

## Decisão de correção

Não foi adotado qualquer bypass da política sudo.

Foram explicitamente descartadas as seguintes alternativas:

- editar /etc/sudoers;
- alterar PAM;
- utilizar chpasswd como forma de escapar do bloqueio;
- abrir shell root persistente;
- conceder grupo administrativo temporário;
- alterar a política global de senhas.

A solução foi adequar o procedimento ao fluxo administrativo já autorizado pela VM: utilizar o próprio adduser em modo interativo, que solicita a senha durante a criação da conta.

Como a primeira conta havia sido criada sem senha e ainda não possuía uso operacional, ela foi removida de forma controlada e recriada.

## 4. Recriação pelo fluxo autorizado

A sequência de correção foi:

1. confirmar que a conta existente era a criada no teste anterior;
2. verificar ausência de processos ativos da conta;
3. remover a conta incompleta e seu home;
4. confirmar a remoção via NSS/getent;
5. recriar teste com sudo adduser --gecos "" teste;
6. fornecer a senha padrão de forma interativa;
7. não registrar senha ou hash em qualquer evidência.

Resultado:

    [PASS] Conta anterior removida de forma controlada.
    [PASS] Remoção confirmada pelo NSS/getent.
    [PASS] Conta criada pelo adduser autorizado.
    [PASS] Conta resolvida pelo NSS/getent.

## 5. Aviso de comprimento da senha

A senha padrão fornecida para a atividade possui cinco caracteres.

Durante a criação, o PAM exibiu o aviso:

    BAD PASSWORD: The password is shorter than 8 characters

O sistema permitiu a continuidade após a confirmação da mesma senha.

A decisão de segurança foi não reduzir a exigência global da VM para acomodar uma credencial específica da atividade. Assim, o requisito acadêmico foi preservado, a senha padrão foi usada conforme instrução e nenhuma configuração PAM foi alterada.

O aviso foi registrado como uma incompatibilidade entre uma credencial acadêmica padronizada e a recomendação local de comprimento, e não como motivo para degradar o host.

## 6. Falha no coletor de validação

A recriação da conta foi concluída corretamente, porém a primeira versão do coletor pós-criação encerrou antes dos testes finais.

A causa foi um defeito no script de evidência: foi utilizada a variável GROUPS, que é uma variável especial/read-only do Bash.

Esse problema afetou apenas a coleta de evidência, não a criação, a senha ou as permissões da conta.

A correção foi substituir essa variável por um nome comum e executar uma terceira versão somente leitura, sem alterar a conta já criada.

## 7. Validação final somente leitura

O validador final confirmou:

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

Resultado consolidado:

    PASS=9
    WARN=0
    FAIL=0
    GAP=0

Critério final:

    [PASS] Critério de privilégio mínimo atendido na EP125.

## Interpretação de segurança

A conta teste possui apenas as capacidades necessárias a um usuário local comum.

A ausência de grupos como sudo, wheel, adm, docker, lxd, libvirt, shadow, disk e systemd-journal reduz superfícies de escalonamento por associação de grupo.

A ausência de autorização sudo impede execução administrativa delegada.

Os testes negativos de leitura de /etc/shadow e escrita em /etc fornecem evidência prática de que a conta não possui acesso a duas classes relevantes de recurso privilegiado.

## O que o procedimento demonstra

O resultado não se limita à existência do usuário. O processo demonstra uma sequência auditável:

requisito acadêmico -> tentativa inicial -> falha segura -> diagnóstico da política sudo -> uso do fluxo administrativo autorizado -> criação com senha padrão -> validação independente somente leitura -> privilégio mínimo comprovado.

## Evidências

Relatórios locais utilizados:

- conectaeduca-evidencia-usuario-teste-ep125-20260911-200504.txt
- conectaeduca-diagnostico-sudo-usuario-teste-ep125-20260911-201335.txt
- conectaeduca-evidencia-usuario-teste-ep125-v2-20260911-201910.txt
- conectaeduca-evidencia-usuario-teste-ep125-v3-20260911-203147.txt

O Git registra apenas informações sanitizadas. Nenhuma senha, hash de senha ou segredo é versionado.

## Estado

EP125 / usuário de sistema teste: concluído e validado em 11/09/2026.

Este documento cobre exclusivamente o usuário de sistema na EP125. A criação do usuário equivalente na EP126 e a conta de aplicação teste@pucparana.com devem ser documentadas nas respectivas etapas, mantendo a mesma separação entre identidade de sistema e identidade da aplicação.
