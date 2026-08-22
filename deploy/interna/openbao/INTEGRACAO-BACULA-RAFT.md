# ConectaEduca — OpenBao Raft e Bacula

## Objetivo

O backup do OpenBao usa snapshot lógico do storage Raft. O volume Raft bruto
não é copiado pelo Bacula.

## Identidade operacional

A workload usa a AppRole `bacula-snapshot`, associada exclusivamente à policy
`bacula-snapshot`.

A policy concede somente:

- `read` em `sys/storage/raft/snapshot`.

Os tokens emitidos pela AppRole são curtos, não recebem `default` policy e
possuem uso limitado. RoleID e SecretID ficam em `.runtime`, com modo 0600, e
não entram no Git nem no handoff.

## Bootstrap administrativo

Quando a AppRole precisa ser criada e não existe root token persistente, o
script `scripts/recuperacao/recuperar_approle_bacula_snapshot.py` executa uma
recuperação administrativa de laboratório:

1. habilita temporariamente o endpoint legado `generate-root` somente no
   listener local;
2. usa o quorum das shares locais de custódia sem imprimi-las;
3. recupera um root token somente em memória;
4. registra policy/AppRole;
5. revoga o root temporário;
6. restaura o HCL endurecido;
7. recria e unseal o OpenBao;
8. confirma que `generate-root` voltou a ficar indisponível.

O processo não executa `bao operator init` e não apaga o volume Raft.

## Prova Bacula

O checkpoint final:

1. autentica via AppRole;
2. obtém snapshot Raft;
3. coloca somente o snapshot na bancada sintética Bacula;
4. cria um canário de custódia fora do FileSet;
5. executa backup;
6. remove o snapshot original;
7. executa restore;
8. compara SHA-256 original/restaurado;
9. confirma que o canário de custódia não foi incluído.

## Implantação nas VMs

RoleID/SecretID atuais não devem ser copiados para a nova VM. A identidade deve
ser recriada no OpenBao da VM destino durante a implantação, seguindo o mesmo
contrato de mínimo privilégio.
