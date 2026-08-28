# Evidência de backup e recuperação — EP126 / VM Interna

**Projeto:** ConectaEduca  
**Data da evidência:** 27/08/2026  
**VM:** `ep126-pucpr`  
**Papel arquitetural:** rede interna / serviços sensíveis  
**Baseline de implantação:** `eco-freeze-pre-vms-2026-08-23`  
**Commit da baseline:** `7c9336259d7cf5db0f90cbb0e1d9e5ce5674cd2d`

## Objetivo

Registrar, sem armazenar segredos no repositório Git, a existência e a integridade de mecanismos independentes de recuperação da VM interna do ConectaEduca.

A estratégia adotada separa:

1. **reprodutibilidade do código e da infraestrutura**, mantida no GitHub;
2. **backup portátil de dados e custódias sensíveis**, armazenado externamente e cifrado;
3. **snapshot da máquina virtual**, realizado pela equipe responsável pela infraestrutura Hyper-V do laboratório.

Essa separação reduz a dependência de um único mecanismo de recuperação e evita transformar o Git em repositório de backup de banco de dados ou de material criptográfico.

## Estado validado da VM antes do backup

O checkpoint técnico final da EP126 foi aprovado antes da criação do kit de recuperação.

Principais validações:

| Componente | Evidência |
|---|---|
| Rede | `192.168.6.50/28`, gateway `192.168.6.49` |
| Git | baseline correta e worktree limpa |
| MariaDB | `running`, `healthy`, sem OOM e sem restart |
| Wazuh Manager | `running`, sem OOM e sem restart |
| Wazuh Indexer | `running`, operacional |
| Wazuh Dashboard | `running`, operacional |
| OpenBao | inicializado, unsealed e ativo |
| Ferret | `running`, HTTP 200, usuário não-root |
| Ferret hardening | root filesystem read-only, `cap_drop=ALL`, `no-new-privileges` |
| Recursos | aproximadamente 11 GiB de RAM disponíveis e 134 GiB de disco livres |
| `vm.max_map_count` | `1048576` |

O único aviso conhecido permaneceu relacionado à sincronização NTP da infraestrutura do laboratório (`NTP_SYNCHRONIZED=no`), sem reprovação do checkpoint.

## Kit portátil de recuperação

Foi criado na EP126 o seguinte artefato:

`conectaeduca-ep126-recovery-20260827-220631.tar.gz`

**Tamanho registrado:** 1,3 MB

**SHA-256:**

```text
617c2a57f4a396fbadfd6fd03b6a2340bcdfcc62c0e390955ffa9550d974d4ef
```

O arquivo de checksum correspondente foi gerado separadamente:

`conectaeduca-ep126-recovery-20260827-220631.tar.gz.sha256`

O kit foi armazenado externamente no Google Drive. O link do armazenamento não é mantido neste repositório para evitar associação desnecessária entre o código público/versionado e o local de custódia do material de recuperação.

## Conteúdo do kit

O pacote de recuperação contém:

- Git bundle completo do repositório;
- archive do código correspondente ao freeze de implantação;
- identificação da baseline;
- inventário sanitizado da VM;
- inventário sanitizado dos containers, imagens, volumes e redes Docker;
- checkpoint técnico final da EP126;
- dump consistente do banco `conectaeduca`, comprimido e cifrado;
- custódia das shares Shamir do OpenBao, arquivada e cifrada;
- checksums SHA-256 internos;
- instruções de recuperação.

## Proteção do conteúdo sensível

O dump do MariaDB e a custódia Shamir foram cifrados antes de compor o artefato final.

Parâmetros registrados pelo procedimento:

- AES-256-CBC;
- PBKDF2;
- HMAC-SHA256;
- salt;
- 300.000 iterações.

A senha de recuperação não foi armazenada no kit nem registrada nos relatórios.

O procedimento também validou explicitamente que:

- o dump SQL não permaneceu em plaintext no host;
- a custódia Shamir foi cifrada e testada;
- o segredo SMTP materializado em `/dev/shm` não foi copiado;
- root token inicial não foi incluído;
- AppRole token e SecretID não foram incluídos;
- arquivos temporários de transferência RSA não foram incluídos;
- arquivos `.env`/runtime contendo segredos não foram incluídos.

## Snapshot Hyper-V

Após a validação e o backup externo, foi solicitado à equipe de suporte responsável pelas VMs do laboratório um snapshot/checkpoint da EP126 no Hyper-V.

O snapshot foi confirmado pela equipe de suporte.

Em seguida, o checkpoint técnico da VM foi executado novamente para comprovar que o estado operacional permaneceu íntegro após a captura.

Resultado pós-snapshot:

```text
FAILURES=0
WARNINGS=1
CHECKPOINT_FINAL_VM_INTERNA_EP126=APROVADO
MARIADB=OPERACIONAL_LOOPBACK
WAZUH=OPERACIONAL_LOOPBACK
OPENBAO=OPERACIONAL_LOOPBACK
FERRET=OPERACIONAL_LOOPBACK
ROOT_TOKEN_INICIAL=REVOGADO
SEGREDOS_TEMPORARIOS_TRANSFERENCIA=AUSENTES
FREEZE=INTEGRO
NTP_PENDENCIA_INFRA=SIM
```

O único warning pós-snapshot permaneceu sendo a dependência de NTP da infraestrutura do laboratório.

## Camadas de recuperação

A EP126 possui, portanto, três mecanismos independentes e complementares:

| Camada | Finalidade | Estado |
|---|---|---|
| GitHub + freeze | Reproduzir código e configuração versionável | Concluído |
| Kit cifrado externo | Recuperar banco, inventários e custódia OpenBao | Concluído |
| Snapshot Hyper-V | Recuperar rapidamente o estado da VM | Concluído |

O GitHub armazena somente esta **evidência de existência e integridade** do backup. O arquivo de recuperação propriamente dito permanece fora do Git para reduzir exposição, evitar crescimento indevido do histórico e manter separação adequada entre versionamento e custódia de dados sensíveis.

## Evidências técnicas relacionadas

Relatórios gerados na EP126:

- `checkpoint-final-vm-interna-ep126-20260827-213654.txt` — checkpoint final pré-snapshot;
- `backup-recovery-ep126-check-20260827-220332.txt` — validação prévia do procedimento de backup;
- `backup-recovery-ep126-apply-20260827-220631.txt` — execução e validação do kit de recuperação;
- `checkpoint-final-vm-interna-ep126-20260827-221950.txt` — checkpoint pós-snapshot.

## Conclusão

A VM interna foi encerrada em estado operacional validado, com reprodutibilidade por Git, recuperação de dados por backup cifrado externo e recuperação de máquina por snapshot Hyper-V.

A abordagem evita o armazenamento de segredos no GitHub e mantém evidência verificável por SHA-256 da cópia externa de recuperação.
