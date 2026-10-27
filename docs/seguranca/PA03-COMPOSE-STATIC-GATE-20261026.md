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

**Evidência executada:** [Repository Static Integrity, run 40413535276](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40413535276): `Ran 17 tests ... OK`; `COMPOSE_SECURITY_INVARIANTS=PASS files=36 services=59`. No mesmo HEAD (`b941b81377767bb3b5c06ef470219e36975e74cd`), PHPUnit, Gitleaks e Semgrep também `SUCCESS`. Isso **não** substitui revisão de overlays efetivos ou inventário de capabilities/permissões no host.

## Relação com Pentest A/B

A PA-03 da primeira campanha teve **PASS restrito às superfícies testadas** e não demonstrou escalonamento pelo usuário `teste`. Esta mudança fortalece a prevenção de regressões na configuração **para o Pentest B**, sem reclassificar a PA-03 histórica.

Permanecem pendentes para eventual reteste autorizado: identidade Linux/grupos, socket Docker/containerd, permissões de arquivo, capabilities **efetivas** de contêineres, política de LSM/namespace e caminhos de escalonamento nas duas VMs. O gate estático não mede runtime nem garante que todos os formatos YAML/Compose sejam cobertos.

## Reconciliação CI após o advisory PHPUnit (27/10/2026)

Em 27/10, após integração do PR #209, o teste `composer audit --locked` deste PR detectou o aviso `GHSA-9vw2-f4vp-x7gf` no PHPUnit antigo (`>=13.4.0,<13.4.4`), tornando a CI vermelha por uma **dependência dev preexistente na main**, não por esta mudança no parser Compose. A `main` foi corrigida separadamente pelo PR #211, atualizando `composer.lock` para PHPUnit 13.4.5 e `sebastian/git-state` 1.1.0, com 5/5 workflows verdes, audit sem advisories e 132 testes PHPUnit aprovados. Este PR **não modifica `composer.lock`**, não silencia o auditor e não altera serviços das VMs.

Este commit documental provoca nova execução da CI do PR #210 sobre a `main` corrigida. A integração depende novamente de 4/4 checks aprovados, Gitleaks sem exceção duplicada e mergeability confirmada, sem `pull`/deploy na EP125/EP126.
