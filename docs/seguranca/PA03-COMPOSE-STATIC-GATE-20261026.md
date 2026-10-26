# PA-03 — Endurecimento do verificador Docker Compose (offline, 26/10/2026)

**Classificação:** melhoria preventiva de segurança da CI, proposta em branch DRAFT, sem acesso às VMs. Não constitui exploração real de privilégios.

## Motivo e evidência no código

O baseline possui `scripts/evidencias/checkpoint_compose_security_invariants.py` como gate de segurança do Compose. A função `parse_services` examina `cap_add`, `cap_drop`, `security_opt` e `ports` por listas YAML multilinha. Antes desta revisão, um YAML Compose válido usando valores numa só linha — por exemplo `cap_add: [SYS_ADMIN]` — **não era interpretado como lista**, e o gate podia retornar falsamente ausência de capability inesperada. O mesmo risco de inspeção incompleta existia para `cap_drop`, `security_opt` e `ports`. É um risco no **mecanismo de validação estática**, não um achado provado em runtime da EP125/EP126.

## Mitigação proposta

O analisador agora registra valores de lista que não consegue interpretar em `invalid_inline_lists`, reportando falha fechada por serviço/chave no `analyze_content`. O contrato aceita formas vazias documentadas (`[]`, `!reset []`, `!override []`) e marcadores de tag usados com listas multilinha (`!reset`, `!override`); listas não vazias devem permanecer multiline até que seja adotado um parser YAML Compose completo.

Não foi alterada configuração de container nem Compose do serviço; somente o gate e a CI. Não se afirma que um atacante já utilizou o caminho `cap_add` inline, nem que o teste estático impede uma pessoa com acesso privilegiado de alterar a VM.

## Testes negativos e preservação dos controles

Adicionados **17 testes sintéticos** em `tests/python/test_pa03_compose_inline_lists.py`: arrays inline para `cap_add`, `cap_drop`, `security_opt`, `ports`, listas com `!override`/`!reset`, valor escalar inválido, egress/publicação wildcard, Docker socket, `privileged:true`; positivos para reset vazio, override vazio e listas multilinha normais. As fixtures não contêm credenciais nem operações Docker.

O workflow `.github/workflows/repository-static-integrity.yml` passou a executar essas 17 verificações na mesma etapa `Compose security invariants`, **antes** do scan total de YAMLs Compose rastreados.

**Aceite futuro:** obter `Repository Static Integrity=SUCCESS` e registrar número executado; o scan de repositório também deve permanecer PASS. Isso não substitui revisão de overlays efetivos ou inventário de capabilities/permissões no host.

## Relação com Pentest A/B

A PA-03 da primeira campanha teve **PASS restrito às superfícies testadas** e não demonstrou escalonamento pelo usuário `teste`. Esta mudança fortalece a prevenção de regressões na configuração **para o Pentest B**, sem reclassificar a PA-03 histórica.

Permanecem pendentes para eventual reteste autorizado: identidade Linux/grupos, socket Docker/containerd, permissões de arquivo, capabilities **efetivas** de contêineres, política de LSM/namespace e caminhos de escalonamento nas duas VMs. O gate estático não mede runtime nem garante que todos os formatos YAML/Compose sejam cobertos.
