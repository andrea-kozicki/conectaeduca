# Fase 3 — pacote de redução de pendências offline (29/10/2026)

**Somente revisão de código e preparação de homologação. Não executar nas VMs.**

## 1. PHP — issue #201 (P0)
- Dockerfile versionado: `php:8.5.9-fpm-alpine3.24@sha256:9dc81f...`; proveniência textual também registra 8.5.9.
- **Não alterar o FROM sem obter tag corrigida e digest oficial verificado.** Não supor que `apk upgrade` substitua patch do interpretador PHP.
- Critério de aceite: tag/digest conferidos, atualização consistente das duas referências no Dockerfile, build reproduzível, scan, teste PHP/Composer, regressão de RBAC/MFA/DB/WAF e versão ativa na EP125.
- A confirmação de CVE/versão afetada requer validação em avisos oficiais; esta revisão registra o estado do repositório, não comprova exploração nem patch.

## 2. GA-08
- `compose.ga08-socket.candidate.yml` passa a zerar `php.expose` herdado por `!reset []`, commit `da97e04b`.
- Teste offline reforçado para exigir remoção da declaração, commit `eab8ffc5`.
- Conferir `docker compose config` com overlays reais na ordem aprovada; testar socket UID/GID, FastCGI, WAF/TLS, isolamento lateral e SQL na EP126.
- Não remover `expose` da base antes de aprovar o candidato: baseline precisa permanecer íntegro.

## 3. PA-06 — issue #195
- Diagnóstico versionado: `storage/logs/audit.log` dentro de tmpfs; não demonstrada retenção durável nem coleta Wazuh.
- Projeto de solução: destino durável com permissões restritas, rotação, encaminhamento ao Wazuh com parser validado, eventos sintéticos, sem conteúdo sensível, backup e teste de restart/recreate.
- **Não montar volume nem alterar Wazuh sem aprovação**; persistência não está corrigida.

## 4. PA-07 — issue #196
- Bacula Director/Catalog e PgBouncer: preparar diagnóstico de configuração, resolução DNS, credenciais por segredo, porta 5432 do serviço Catalog vs porta 6432 do PgBouncer, logs sanitizados e teste de conexão com usuário autorizado.
- Não mudar endpoint por inferência: testar topologia e autorização reais antes do ajuste.

## 5. Twingate
- Connector versionado usa digest fixado, `network_mode: host`, tokens obrigatórios por variáveis, perfil `twingate`, sem portas `ports` nem socket Docker.
- O modo host amplia a superfície de rede do Connector: confirmar necessidade, escopo, firewall e egress com suporte.
- Regras propostas: menor privilégio por grupo; Admin não é sinônimo de RBAC do PHP; usuário sem grupo não deve obter Resource; sem Resource direto para OpenBao/DB/Catalog.
- A rota pública `/admin` não é isolada por Twingate se usar o mesmo host/443; definir entrada administrativa privada e regra de negação pública.

## 6. Roteiro de retestes
| PA | Preparação offline | Dependência para encerramento |
|---|---|---|
| PA-01 | recuperar cenário, origem, alvo, logs e critérios de negativa | teste autorizado e evidência |
| PA-02 | matriz WAF→Nginx→PHP e PHP→upstream negativo | isolamento runtime + WAF/TLS |
| PA-03 | casos RBAC usuario/empresa/admin, autorização horizontal/vertical | contas e logs de teste |
| PA-04 | caminhos documentados e controle de rota | evidência de acesso negado/permitido |
| PA-05 | registrar limitação metodológica de contas | aceite explícito da limitação |
| PA-06 | correlação de eventos e retenção PHP/Wazuh | prova de ingestão e durabilidade |
| PA-07 | recuperação Bacula/Catalog e serviço | teste de recuperação/autorização |
Não atribuir resultados não presentes nas evidências originais.

## 7. PRs e release
- PR #200: manter Draft até aceite professor/suporte e critérios de runtime, TLS, egress, endpoint Admin, rollback.
- Issue #204: PA-02 permanece aberta; porta host 8088 removida não comprova isolamento da bridge.
- Issue #201: PHP patch P0 pendente de digest/versão verificados e VM.
- Issue #195: persistência e Wazuh pendentes.
- Issue #196: Bacula/Catalog pendente.
- Freeze 07/11, Pentest B 08–14/11, apresentação 17/11 são marcos planejados, não aprovações.

## 8. Pacote operacional mínimo (quando houver VM)
1. Autorização de mudança, snapshot identificado, baseline e hashes.
2. Compose final sanitizado, UID/GID do socket, portas e redes.
3. Healthchecks + FastCGI `pong` + WAF HTTPS e SQL autenticado.
4. Teste lateral negativo, observabilidade, evidências e SHA256.
5. Ensaio rollback e pós-restauração; registrar aceite ou abortar.

**Estado:** preparação offline consolidada. Nenhum deploy, merge, rollback ou mudança nas VMs.
