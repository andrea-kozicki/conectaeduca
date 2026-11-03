# Fase 3 — handoff único para 03/11/2026: Zero Trust, PA-02 e Ferret v5

**Elaborado em 02/11/2026 (America/Sao_Paulo)** · **Natureza:** DOCUMENTAÇÃO PRONTA PARA EXECUÇÃO FUTURA, não autorização nem afirmação de implementação.  
**Regra:** esta branch contém **somente Markdown**, não muda runtime, regras, Compose, pipelines, scripts, tokens ou `main`.
**Prazo:** preservar o trabalho já validado. Usar uma janela por VM, gates objetivos e um pacote de provas; evitar inventários, reruns e PRs duplicadas.

## Atualização de 03/11 — resposta docente, snapshots e AD

[Registro da orientação docente, snapshots e tabela AD/pfSense](DECISAO-DOCENTE-SNAPSHOTS-AD-PFSENSE-20261103.md).

- O professor confirmou **portal de usuários finais via internet/HTTPS/WAF**. **Twingate** fica para administração e infraestrutura interna, mantendo MFA/RBAC da aplicação e a segregação do Wazuh.
- O suporte informou que **snapshots foram realizados**. A comunicação não trouxe ID, cobertura, restore e janela; portanto **G0 permanece fechado**, individualmente por EP125 e EP126. Não pressupor restauração da EP126 ou persistência das configurações até verificar o problema de login e o eventual ponto restaurado.
- A tabela sugerida de DNS/Kerberos/LDAP/GC/NTP para o AD é **hipótese inicial, não abertura efetiva**. Confirmar o cliente, os DCs, origem/destino, modalidade de ingresso e necessidade de SMB/RPC/LDAPS antes de qualquer mudança pfSense.

## 1. Pacotes preparados para a janela
| Entrega | Local | Situação |
| --- | --- | --- |
| Decisão professor, snapshots e tabela AD/pfSense | [ATUALIZAÇÃO 03/11](DECISAO-DOCENTE-SNAPSHOTS-AD-PFSENSE-20261103.md) | **REGISTRADO**, G0 e firewall pendentes de validação |
| Roteiro de execução Python, gates e aceite por PA | [ROTEIRO PENTEST B](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md) | **PREPARADO** na documentação, não executado; alinhado à PR #219 e seus 64 testes offline |
| Matriz Pentest A×B para PA-01…07 | [MATRIZ PA01–07](PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md) | **PRONTA PARA USO**, resultados B não executados |
| Checklist PA-02/EP125 e GA08.18 | [ROTEIRO GA08](../release/GA08-18-EP125-ROTEIRO-CORTE-RETESTE-20261103.md) | **PRONTO, G0 FECHADO** até snapshot e revisão |
| Checklist Ferret v5/EP126 e GA06 | [ROTEIRO GA06](../release/GA06-FERRET-V5-EP126-ROTEIRO-CORTE-RETESTE-20261103.md) | **PRONTO, G0 FECHADO** até snapshot/autorização |
| Rastreabilidade de PRs, Zero Trust e ordem de trabalho | Este documento | **PRONTO**; não alterar PRs de código para simular aceite |

## 2. Linha de base do Zero Trust — fatos observados e limites
- **EP125 DMZ 192.168.6.34** e **EP126 interna 192.168.6.50**; roteamento, NAT e regras interzonas pertencem ao pfSense; bridge Docker local é caminho independente, não automaticamente submetido ao Twingate.
- Connectors institucionais `conectaeduca-dmz-01` EP125 e `conectaeduca-interna-ep126` EP126 foram reportados **Running/healthy/Connected** em 31/10–02/11; conectores antigos/cadastrados não conectados NÃO são motivo para reinstalar os saudáveis.
- Resource `ConectaEducaAPP` para EP125 HTTPS/443: openSUSE com FortiClient desconectado e Twingate online acessou portal com cadeia CA confiável, `curl` HTTP200/TLS verificado e Firefox no perfil isolado. **Prova de acesso pelo cliente, não de backend isolado.**
- Resource `ConectaEduca — Wazuh Dashboard`: no Connector EP126 destino `127.0.0.1:443`, alias `wazuh.dashboard`, grupo `CE-SOC-OPERACAO` com política MFA. `twingate auth` mostrou sucesso; login de aplicação Wazuh com conta de teste e negações de leitura em Users/Roles/Policies/Roles mapping versus admin permitido foram documentados em 01/11.
- **Teste de segregação ZT-07.26B/C (02/11):** identidade limitada no Android em 5G com Twingate conectado alcançou ConectaEducaAPP, mas Wazuh não apareceu e o alias não resolveu DNS nessa sessão. **PASS_WITH_SCOPE**: duas identidades em **dispositivos distintos**, sem packet capture universal ou logs completos de auditoria de negação; não transformar em prova de impossibilidade de qualquer rota lateral.
- **PA-02 permanece aberto:** acesso direto host→bridge Nginx EP125 reproduzido antes do cutover; o Twingate não inspeciona sozinho o upstream HTTP. A proposta dual socket exige G0 e GA08.18.
- **Arquitetura de exposição:** página pública HTML/HTTPS e endpoints administrativos privados são papéis distintos. Um Resource `IP:443` Twingate não protege apenas caminho `/admin`; exigir listener/hostname/endpoint próprio ou negação explícita no WAF para isolamento administrativo futuro.
- Nunca repetir prints de QR MFA, URL efêmera, token, cookie ou exportar secret dos Configs; evidência acadêmica usa screenshots **sanitizados** e hashes de cópias privadas.

**Referências ZT atuais:** [PR #214](https://github.com/andrea-kozicki/conectaeduca/pull/214), `docs/evidencias/CONSOLIDADO-ZT08-TWINGATE-PORTAL-WAZUH-20261102.md` e `docs/runbooks/TWINGATE-WAZUH-GATE-NEGATIVO-20261102.md` **na branch do PR #214**. Alguns parágrafos mais antigos do corpo da PR #214 ainda refletem 31/10 (CA ou login pendentes) e não devem prevalecer sobre os adendos datados 01–02/11.

## 3. PRs abertas — coordenação sem merges inesperados
| PR / escopo | Situação no GitHub em 02/11 | Encaminhamento correto |
| --- | --- | --- |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) Kit Python Pentest B | OPEN/DRAFT; 64 testes offline PASS (03/11); fases 1–5 e gerador Markdown Daily 9; **nenhum ataque real executado** | usar [ROTEIRO PENTEST B](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md), observar gates EP125/EP126, nunca converter fixture ou CI em PASS |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) GA08/PA02 dual socket | OPEN/DRAFT; 6 CI workflows PASS HEAD `67ab035b`; mudança runtime ainda não aplicada | usar [GA08.18](../release/GA08-18-EP125-ROTEIRO-CORTE-RETESTE-20261103.md), snapshot **EP125**, validar 9/10 Compose e mounts, revisar rollback, só depois cutover |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) Ferret v5 | OPEN/DRAFT; 6 CI workflows PASS HEAD `1c7b8e1`; imagem 2.4.3 em produção | usar [GA06](../release/GA06-FERRET-V5-EP126-ROTEIRO-CORTE-RETESTE-20261103.md), snapshot **EP126**, custódia TAR/monitor/CLI/rollback, reteste pós-cutover |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) Wazuh DLP rules | OPEN/DRAFT; ruleset operacional corrigido EP126 | evidências GA07.3–4 e GA07.8R PASS **não são merge**, preservar diferença Git/runtime |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) ZT docs | OPEN/DRAFT; Connectors e Recursos parcialmente operacionais | corrigir interpretação histórica com observações de 02/11; evitar reinstalação e coleta repetitiva |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) desenho ZT amplo | OPEN/DRAFT, `mergeable=false` em 02/11 | **não** fazer merge do lote heterogêneo; a correção PA02 isolada está na #217 |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) MFA/login PHP | OPEN/DRAFT; testes offline de contrato | não misturar com PA02/GA06; exige decisão de compatibilidade WebCrypto/UX e testes app |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) audit.log | OPEN/DRAFT em histórico (não revalidado neste pacote) | política retenção/rotação exige validação separada |

**Fonte de verdade Git:** `main@b74ea581a0814d86a99b6b455d5569f12fa967e5` em 02/11. Branch desta documentação foi criada **a partir desse commit**. Não supor atualização automática nas VMs após merge. A EP126 tem **dois arquivos locais modificados deliberadamente** pela GA07.7B (`scripts/dlp/sanitizar_ferret.py` e `validar_eventos_ferret.py`), ambos correspondentes aos blobs da #207, com backups privados `GA07_7B_cxonskrl`; não sobrescrever com reset/reconciliação cega. Na EP125, `deploy/dmz/compose.audit-persistent.yml` não versionado deve ser preservado. Não comitar segredos ou estado Docker.

## 4. Solicitação objetiva ao suporte para amanhã (DUAS VMs)
**EP125 — PA02:** confirmar ID/timestamp do snapshot, discos/binds/volumes/CA e restaurabilidade; dar visibilidade sobre seis origens protegidas que o usuário comum não consegue inspecionar, sem compartilhar conteúdo. Manter o pacote GA08/17B e rollback revisado antes de qualquer recriação.
**EP126 — Ferret:** confirmar identificação do **snapshot reportado como realizado**, com cobertura `.runtime`, `state`, `inbox`, `reports/raw`, configuração e possibilidade de retorno. Confirmar custódia/aceite de uso do TAR offline e do procedimento de monitor v5; não presumir que o TAR local feito 01/11 é snapshot restaurável.
**pfSense:** mudanças de firewall/NAT/interzonas são **frente separada** que requer decisão institucional e diffs específicos; não abrir regra genérica para fazer o teste ZT passar.
**Se o suporte fornecer apenas o snapshot de uma VM, somente a respectiva frente pode avançar**, condicionada aos demais gates.

## 5. Sequência de execução de 03/11 — sem retrabalho
1. **Receber confirmação documental dos snapshots reportados e seus planos de recuperação**. Registrar separadamente EP125 vs EP126, operador, cobertura, retenção, hora e autorização.
2. **Escolher a janela de uma VM de cada vez**, impedir concorrência entre GA08 e GA06. Prioridade sugerida: **PA02/EP125** (bypass WAF P0 e dependência de Pentest B). Se EP125 não tiver snapshot válido mas EP126 tiver, considerar apenas Ferret, sem cruzar change control.
3. **GA08.18 (somente com G0 completo)**: executar o procedimento gated da #217, retestes positivos/negativos e registrar estado final. Um 403 WAF sem negativa de backend não encerra PA02.
4. **GA06/v5 (somente com G0 próprio)**: executar procedimento da #207 para imagem/monitor/CLI e seis testes dirigidos; um UI health sem falha 403/inconclusão não encerra PA07.
5. **Pentest B por prioridade de lacunas**: usar [roteiro de execução e aceite](EXECUCAO-E-ACEITE-PENTEST-B-EP125-EP126-CLIENT-20261103.md) e [matriz PA01–07](PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md); executar scripts da PR #219 somente nas identidades, janelas e alvos autorizados. A saída do comparador e os 64 testes CI **não** encerram automaticamente um PA; atrelar resultados às duas campanhas sem reescrever histórico do Pentest A.
6. **Fechamento:** evidências locais com SHA256, relatório Daily 9, links PR/Trello, conclusão/limites, retorno de eventual rollback; só então avaliar review/merge de PRs, uma a uma.

## 6. Checklist único de recebimento do suporte (não contém secrets)
```text
DATA=2026-11-03
EP125_SNAPSHOT_ID=
EP125_TIMESTAMP=
EP125_DISCOS_VOLUMES_COBERTURA=
EP125_RESTAURABILIDADE_CONFIRMACAO=
EP125_OPERADOR_SUPORTE=
EP125_JANELA_E_APROVACAO=
EP125_GA08_G0=ABERTO|FECHADO

EP126_SNAPSHOT_ID=
EP126_TIMESTAMP=
EP126_RUNTIME_STATE_COBERTURA=
EP126_RESTAURABILIDADE_CONFIRMACAO=
EP126_OPERADOR_SUPORTE=
EP126_TAR_V5_EXCECAO_APROVADA=
EP126_JANELA_E_APROVACAO=
EP126_GA06_G0=ABERTO|FECHADO

PA02_CUTOVER=NÃO_EXECUTADO
FERRET_V5_CUTOVER=NÃO_EXECUTADO
PENTEST_B=NÃO_EXECUTADO
```

## 7. Critério de conclusão desta preparação documental
- [x] Matriz de sete PAs produzida, com origem e resultado A, controles B e limitações.
- [x] Roteiro operacional Pentest B com cinco fases, três posições, condições de bloqueio e evidência mínima por PA vinculado à PR #219 (03/11).
- [x] GA08.18 definido com G0, positivos/negativos, drift 9/10 Compose e retorno.
- [x] GA06 v5 definido com TAR/proveniência, monitor, CLI, seis retestes dirigidos e retorno.
- [x] PRs relevantes e estados históricos reconciliados **documentalmente**, sem alterar conteúdo de produção.
- [ ] Snapshots EP125 e EP126 **informados pelo suporte como realizados**; comprovar IDs, cobertura e restaurabilidade para liberar G0.
- [ ] Operação autorizada e executada; retestes pós-cutover e aceite.
- [ ] Pentest B comparativo e revisão/merge posterior das PRs.

**Esta entrega de 02/11 encerra a preparação do dia, NÃO declara encerrados PA-02, PA-07, Zero Trust integral ou Pentest B.**
