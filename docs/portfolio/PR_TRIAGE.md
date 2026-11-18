# ConectaEduca — Triagem das PRs históricas em rascunho

**Inventário remoto:** 18/11/2026.  
**Autora responsável pela decisão final:** Andréa Kozicki.  
**Escopo desta matriz:** revisão documental **sem merge, fechamento, alteração de histórico ou execução em VM**.

As PRs abaixo permaneciam abertas em modo **draft** na consulta inicial. Algumas representam propostas de implantação, outras preservam evidências ou materiais superados por merges posteriores. Uma PR em draft não prova implantação, teste completo ou aprovação institucional.

| PR | Tema | Encaminhamento proposto | Validação obrigatória antes de qualquer decisão |
| --- | --- | --- | --- |
| [#235](https://github.com/andrea-kozicki/conectaeduca/pull/235) | Relato Pentest B | **Revisão editorial / possível integração documental** | Sanitização de evidências, coerência com relatório final e limites PA-01..07 |
| [#232](https://github.com/andrea-kozicki/conectaeduca/pull/232) | Consolidado Fase 3 | **Consolidação histórica** | Datas, resultados observados vs. pretendidos e links a PRs integradas |
| [#230](https://github.com/andrea-kozicki/conectaeduca/pull/230) | Socket HTTP GA-08/PA-02 | **Manter bloqueada para revisão de runtime** | Paridade EP125, imagem PA-05, testes WAF, rollback e permissões institucionais |
| [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229) | Autorização UPDATE PA-05 | **Revisão de segurança de aplicação** | Testes negativos de ownership/publicação, efeitos sobre autorização e migrations |
| [#228](https://github.com/andrea-kozicki/conectaeduca/pull/228) | OpenBao AppRole | **Revisão, sem implantação presumida** | Políticas KV2, identidades limitadas, eventual exposição de credenciais |
| [#227](https://github.com/andrea-kozicki/conectaeduca/pull/227) | Launchers Ferret CLI | **Comparar com #237 antes de integrar** | Diffs de Fish/Bash, compatibilidade SUSE, override V5 e ausência de conflitos |
| [#226](https://github.com/andrea-kozicki/conectaeduca/pull/226) | Cutover Ferret V5 | **Analisar sobreposição com #237** | Quais ações já executadas, artefatos redundantes e rollback não ensaiado |
| [#225](https://github.com/andrea-kozicki/conectaeduca/pull/225) | Logrotate auditd EP125 | **Revisão operacional** | Configuração instalada, simulação segura, permissões e efeito sobre coleta Wazuh |
| [#224](https://github.com/andrea-kozicki/conectaeduca/pull/224) | Sincronização de checkouts | **Não aplicar automaticamente** | Existência de alterações locais, mudanças na `main`, política de backup e drift atual |
| [#221](https://github.com/andrea-kozicki/conectaeduca/pull/221) | Inventário EP125/126 | **Reaproveitar metodologia, sem executar cegamente** | Atualizar base de commits, filtrar nomes institucionais e dados privados |
| [#219](https://github.com/andrea-kozicki/conectaeduca/pull/219) | Kit Pentest B | **Revisão de código/testes** | Execução segura, scripts sem privilégio, evidência sanitizada, código de terceiros |
| [#218](https://github.com/andrea-kozicki/conectaeduca/pull/218) | Pacote Fase 3 | **Consolidação documental histórica** | Instruções de janela antiga não devem ser reproduzidas como plano atual |
| [#217](https://github.com/andrea-kozicki/conectaeduca/pull/217) | Candidato dual socket | **Comparar com GA-08 da EP125** | Source/runtime, rollback, compatibilidade PA-05 e material sensível |
| [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) | Kits de preflight | **Revisão de reutilização** | Semântica read-only, comandos que exigem sudo e links obsoletos |
| [#214](https://github.com/andrea-kozicki/conectaeduca/pull/214) | Evidências Twingate | **Revisão editorial / possível integração documental** | Remover identificadores de contas, sem alegar MFA/RBAC E2E concluído |
| [#213](https://github.com/andrea-kozicki/conectaeduca/pull/213) | Conector Twingate DMZ | **Revisar fonte contra runtime conhecido** | Identidade do conector, tokens nunca no Git, ausência de deploy por merge |
| [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) | Ferret UI/fail-closed | **Revisão técnica; reteste pendente** | Compatibilidade com V5, cadeia de eventos e comportamento de erro |
| [#206](https://github.com/andrea-kozicki/conectaeduca/pull/206) | Severidades DLP | **Revisão de integração Wazuh** | Testes LOW/MEDIUM/HIGH, regras efetivas e telemetria minimizada |
| [#205](https://github.com/andrea-kozicki/conectaeduca/pull/205) | Login híbrido v2 | **Revisão de risco elevada; não implantar sem teste** | MFA, regressões de autenticação, proteção contra downgrade e casos negativos |
| [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203) | Persistência audit.log | **Revisão de operação/privacidade** | Coleta real, persistência, proteção de logs e conflitos com V6 Wazuh |
| [#200](https://github.com/andrea-kozicki/conectaeduca/pull/200) | Arquitetura Zero Trust proposta | **Manter como histórico ou integrar com ressalvas** | Diferenciar projeto pretendido, configuração observada e testes concluídos |

## Alertas de privacidade no histórico público

Uma triagem **dos textos das descrições** identificou marcadores de conta institucional em **oito** PRs: **#203, #217, #224, #226, #227, #228, #229 e #230**. A ocorrência não prova segredo ou credencial, mas identifica detalhes de ambiente que merecem minimização. Outras PRs e **seus diffs, comentários, anexos e commits antigos** ainda requerem inspeção independente.

**Ação recomendada:** revisar descrições atuais e comentários antes de divulgar o repositório como portfólio, substituir caminhos absolutos por caminhos relativos ou `$HOME` onde não se perde contexto, e eliminar desnecessária exposição de identificadores. **Não** fazer `force-push`, reescrita de histórico ou fechamento em massa para tentar apagar o conteúdo: versões antigas podem continuar acessíveis e qualquer tratamento deve considerar o escopo preciso de material sensível.

## Ordem sugerida

1. **Privacidade:** revisar os oito textos identificados e procurar dados sensíveis também nos patches/anexos.
2. **Documentação:** analisar #235, #232, #218, #214 e #200, mantendo uma narrativa histórica única e datada.
3. **Sobreposição:** comparar #226/#227/#207 com #237 (Ferret) e #203/#206 com #240 (Wazuh), evitando merges redundantes.
4. **Mudanças operacionais:** manter #230/#217/#225/#224/#213 em revisão até o encerramento/documentação da infraestrutura.
5. **Aplicação e testes:** revisar #229/#228/#205/#219 com casos positivos e negativos, CI e avaliação de autorização.

Esta lista é **proposta de triagem baseada nos títulos, descrições e no estado conhecido da infraestrutura**. A decisão sobre fechar, converter, atualizar ou integrar cada PR depende de inspeção do diff, da autora e das evidências atuais; não houve alteração automática das PRs listadas.
