# CRED-01 — consistência da identidade técnica `teste`

## Objetivo

Fechar, antes do freeze, a autenticação e o menor privilégio da identidade
técnica de pentest `teste` em cada mecanismo onde ela realmente existe.

CRED-01 **não** transforma todos os serviços em password-based. Quando o
mecanismo nativo é certificado, PSK, AppRole ou service account sem login
humano, registrar `N_A` com justificativa e validar o mecanismo nativo em seu
gate próprio.

A senha acadêmica nunca entra no Git, em argumentos de processo ou em
evidências.

## Tooling

Preparar a matriz em cada VM:

```bash
python3 scripts/evidencias/cred01_consistencia_identidades.py \
  --prepare --host-role ep125
```

ou:

```bash
python3 scripts/evidencias/cred01_consistencia_identidades.py \
  --prepare --host-role ep126
```

O script cria um diretório 0700 no HOME com:

```text
CRED01-MATRIZ.tsv
RESUMO-CRED01-RAW.txt
SHA256SUMS-RAW
```

Nenhuma senha é solicitada no `--prepare`.

Depois dos testes, preencher a matriz sem inserir credenciais e finalizar:

```bash
python3 scripts/evidencias/cred01_consistencia_identidades.py \
  --finalize ~/conectaeduca-cred01-<host>-<UTC>
```

O `--finalize` falha se houver mecanismo obrigatório pendente, se faltar
evidência/justificativa ou se o menor privilégio não estiver comprovado.

## Matriz mínima — EP125

| Componente | Mecanismo | Resultado esperado |
|---|---|---|
| Linux host | PAM / senha | PASS |
| Wazuh Agent | identidade de máquina | N_A para senha humana |
| Nginx | service account | N_A |
| PHP-FPM | service account | N_A |
| WAF | service account | N_A |

### Prova Linux/PAM

Executar interativamente, sem registrar a senha:

```bash
su - teste -c 'whoami; id; pwd'
```

Evidência esperada: `whoami=teste`, UID/GID/grupos mínimos e autenticação
concluída. A senha permanece somente no prompt do `su`.

## Matriz mínima — EP126

| Componente | Mecanismo | Resultado esperado |
|---|---|---|
| Linux host | PAM / senha | PASS |
| OpenBao | userpass | PASS |
| Bacularis | Web login | PASS |
| MariaDB/phpMyAdmin | SQL + Web login | PASS |
| PostgreSQL/PgBouncer | SCRAM | PASS |
| Bacula Console | Console/TLS-PSK | PASS |
| Wazuh | Dashboard/Indexer + RBAC | PASS |
| Ferret | sem login humano próprio | N_A |

### Linux/PAM

Mesmo teste interativo da EP125.

### OpenBao

Depois da correção da senha do `userpass/teste`:

```bash
python3 scripts/implantacao/gui01_openbao_human_access.py verify
```

O verificador solicita a senha por `getpass`, exige policy mínima exclusiva,
testa leitura autorizada, paths vizinhos/operacionais negados, escrita negada,
administração negada e revoga o token de teste.

Para CRED-01, a credencial antiga digitada incorretamente deve ser testada uma
única vez e rejeitada, sem ser registrada na evidência.

### Bacularis

Teste pela WebGUI em `127.0.0.1:9097`:

- login `teste`: PASS;
- consultas/status: PASS;
- mutação por API: DENY/405;
- painel administrativo: DENY/403.

A evidência CRED-01 registra apenas o resultado e a referência do artefato/print,
nunca a senha.

### MariaDB / phpMyAdmin

Em `https://localhost:9443`:

- login `teste`: PASS;
- SELECT na view de pentest: PASS;
- DML seguro de prova: DENY pelo MariaDB.

O principal SQL permanece separado da conta funcional
`teste@pucparana.com`.

### PostgreSQL / PgBouncer

Caminho esperado:

```text
teste no host -> 127.0.0.1:6432 -> PgBouncer -> PostgreSQL bacula
```

A senha deve ser fornecida por prompt/variável efêmera do cliente, nunca argv ou
arquivo versionado.

Provar:

- autenticação SCRAM como `teste`;
- SELECT permitido;
- CREATE TABLE negado;
- CREATE TEMP TABLE negado para `teste`;
- nenhuma exposição direta de 5432 no host.

Se 6432 ainda não estiver materializado, CRED-01 permanece BLOCK nesse item; não
marcar N_A.

### Bacula Console

Usar a configuração dedicada 0600 da identidade `teste` e o endpoint
loopback 9101.

Provar:

- conexão do `bconsole` como Console `teste`;
- comando informativo permitido;
- comando mutante negado pela ACL.

A configuração/PSK não deve ser copiada para a evidência.

### Wazuh

Usar o reconciliador em modo CHECK:

```bash
python3 scripts/implantacao/reconciliar_wazuh_teste_readonly.py
```

O modo padrão é CHECK. A senha é solicitada de forma oculta e o teste deve
comprovar autenticação real, role `readonly`, consulta permitida e operações
administrativas negadas, sem publicar 55000/9200.

### Ferret

`N_A` para senha humana quando o runtime continuar sem RBAC/login próprio.
Validar a service account e o pipeline DLP→Wazuh nos gates específicos; não
inventar usuário `teste` dentro do container.

## Estados aceitos na matriz

- `PASS`: mecanismo obrigatório comprovado;
- `N_A`: mecanismo sem autenticação humana/password aplicável, com
  justificativa;
- `PENDENTE`: ainda não testado; bloqueia fechamento;
- `BLOCK`: caminho existe no desenho, mas a prova falhou ou não está
  materializada; bloqueia fechamento.

Para mecanismos `PASS`:

- `AUTH_POSITIVA=PASS`;
- `MENOR_PRIVILEGIO=PASS`;
- `AUTH_NEGATIVA=PASS` quando o teste negativo é tecnicamente seguro;
- caso contrário, `AUTH_NEGATIVA=N_A_SAFE` com justificativa.

OpenBao exige `AUTH_NEGATIVA=PASS` após a correção da senha antiga.

## Critério de fechamento

CRED-01 fecha somente quando:

1. EP125 e EP126 possuem pacote final e SHA-256;
2. todos os mecanismos obrigatórios estão `PASS`;
3. todos os `N_A` possuem justificativa de mecanismo;
4. autenticação positiva e menor privilégio estão comprovados;
5. nenhum segredo aparece no TXT/TSV/Git;
6. OpenBao comprova rejeição da credencial antiga;
7. PostgreSQL/PgBouncer não permanece como GAP live;
8. evidências são referenciadas na matriz pré-freeze.

Até lá:

```text
CRED01_STATUS=BLOCK
```
