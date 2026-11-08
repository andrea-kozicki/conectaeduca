# CE-PA04-ACL01 — OpenBao EP126: isolamento KV v2 e AppRole read-only

**Responsável:** Andréa Kozicki · **Data:** 08/11/2026 · **Escopo:** OpenBao da EP126, após CE-OB01/02 (desbloqueado e Docker healthy).

## Objetivo da implementação

Instalar **um novo domínio de segredos isolado**, um método AppRole específico e uma ACL **somente leitura para um caminho exato**, sem manipular valores existentes ou criar credenciais permanentes.

- Novo mount KV v2: `ce-app/`. Não modifica nem converte mounts de segredos atuais.
- Novo auth mount: `ce-approle/` (`type=approle`), independente dos métodos de autenticação preexistentes.
- Política `ce-app-runtime-read-v1`:
  ```hcl
  path "ce-app/data/runtime/app" {
    capabilities = ["read"]
  }
  ```
- Role `ce-app-runtime-read`, `bind_secret_id=true`, `secret_id_num_uses=1`, `secret_id_ttl=10m`, `token_policies=[ce-app-runtime-read-v1]`, `token_no_default_policy=true`, `token_ttl=15m`, `token_max_ttl=1h`, `token_type=service`.

A ACL não tem `list`, `create`, `update`, `delete`, `sudo` nem permissões administrativas. Caminhos fora de `ce-app/data/runtime/app` são negados por padrão. O papel não recebe `default`.

## Limites importantes

**Este procedimento NÃO integra a aplicação em produção ao cofre nem cria um segredo de negócio**. O caminho `ce-app/data/runtime/app` é uma interface de runtime reservada; seu conteúdo e a identidade que realmente fará login ainda devem ser definidos em uma mudança de integração. A API OpenBao está publicada no host apenas em `127.0.0.1:18200` com HTTP local; **não ampliar para a DMZ nem usar HTTP atravessando VMs**. Integração EP125→EP126 requer TLS validado, recurso controlado e fluxo de custódia credencial.

Nenhum `RoleID`, `SecretID` ou token será impresso ou persistido. O operador digita seu token **somente no prompt oculto do terminal EP126**, sem enviá-lo ao chat/GitHub; o script o mantém em memória por sua execução. O script **não gera SecretID**, evitando materialização prematura. Não usar unseal share como token administrativo: são elementos distintos.

## Gates e execução

- Script `ops/pa04/ce_pa04_acl01.py` validado em Python, baixado por commit imutável e Git blob conferido.
- EP126 `ep126-pucpr-br`, usuária `andrea.kiew`, **sem sudo** e sem shell de root, checkout HEAD `04f88d275064a005d0ffcd4f9372a371c28c32d5`; alterações tracked anteriores do PA-07 são preservadas.
- A API local deve informar `initialized=true`, `sealed=false`, status ativo 200. O token administrativo deve estar disponível sob custódia da operadora e permitir gestão desses caminhos de mount/auth/policy.
- Antes de mudar, consulta somente metadados de `sys/mounts`, `sys/auth`, ACL e AppRole com os nomes reservados. Se existir conflito de mount/policy/role, **aborta, não sobrescreve**. Se um mount `ce-app/` já existir mas não tiver a política `ce-app-runtime-read-v1` idêntica à gerenciada, aborta também: não conceder acesso a um cofre preexistente potencialmente alheio.
- Se ausentes, cria mount KVv2, habilita AppRole, cria política e role restritos; caso já existam de forma equivalente, não repete a gravação. Confere por leitura somente os atributos de restrição da role.
- Se o token não tiver permissão, **pode haver estado parcial** conforme a etapa autorizada; o script não desfaz automaticamente mounts/policies, para não destruir dados existentes. Uma falha deve ser triada a partir dos marcadores já emitidos, **sem repetir cegamente**.

## Evidência imediata da implantação

```text
OPENBAO=ATIVO_NAO_SELADO
COLISOES_PREEXISTENTES=NAO
KV2_CE_APP=CRIADO
AUTH_APPROLE=CRIADO
POLITICA_READONLY=CRIADA
APPROLE=CRIADA
APPROLE_RESTRITA=CONFIRMADA
CAPACIDADE=READ_UNICO_CAMINHO_KV2
CAMINHO=ce-app/data/runtime/app
TOKEN_PADRAO=DESABILITADO
SECRET_ID_OBRIGATORIO=SIM
SECRET_ID_GERADO=NAO
SEGREDOS_CRIADOS_OU_LIDOS=NAO
INTEGRACAO_APP=AINDA_NAO_REALIZADA
SERVICOS_REINICIADOS=NAO
CE-PA04-ACL01_CONCLUIDO
```

Marcadores `EXISTENTE_VALIDO` são igualmente aceitáveis em reaplicação, desde que o script conclua; `COLISOES_PREEXISTENTES=NAO` significa apenas ausência de conflito, não ausência de recursos. **Não postar o texto digitado no prompt.**

## Estado e próximos passos

- [ ] Execução real CE-PA04-ACL01 na EP126.
- [ ] Registro no relatório/Trello sem segredos.
- [ ] Em mudança separada, definir quais segredos reais entram no KV, identidade do processo cliente, caminho autorizado e entrega segura do RoleID/SecretID; preparar integração TLS quando acesso inter-VM for necessário.
- [ ] Um teste positivo e um negativo **curtos** de AppRole/ACL para completar o aceite PA-04; não repetir pentest.
- [ ] Verificar coleta da auditoria OpenBao (config declarativa atual destina auditoria ao `stdout` do contêiner, ainda não equivale a prova de ingestão Wazuh).

**Não reiniciar OpenBao, não executar `bao operator init`, não fazer unseal novamente e não modificar políticas/mounts existentes.**

Referências oficiais: [AppRole API](https://openbao.org/docs/api/auth/approle/), [ACL Policies](https://openbao.org/docs/api/system/policies/), [KVv2](https://openbao.org/docs/secrets/kv/kv-v2/).
