# ConectaEduca — estado técnico para encerramento do laboratório

**Corte documental:** 18/11/2026 (America/Sao_Paulo).

**Autoria acadêmica:** Andréa Kozicki, execução individual do projeto. A infraestrutura
de laboratório e o suporte foram fornecidos pela instituição; ferramentas de terceiros
mantêm suas respectivas licenças e autorias.

**Natureza:** fotografia documental e de código-fonte; **não é homologação final da operação**.

## Ponto de referência e regras de evidência

O registro inicial da consulta de 18/11/2026 apontava para
[`7d4c017`](https://github.com/andrea-kozicki/conectaeduca/commit/7d4c017ef79a3e21cc449ccda3f6e5e13f80de44),
**antes** das PRs de fechamento. Na mesma data, as PRs
[#243](https://github.com/andrea-kozicki/conectaeduca/pull/243),
[#244](https://github.com/andrea-kozicki/conectaeduca/pull/244),
[#245](https://github.com/andrea-kozicki/conectaeduca/pull/245) e
[#246](https://github.com/andrea-kozicki/conectaeduca/pull/246) foram
integradas: o baseline **pós-consolidação, antes da preparação do release** é
[`527d6a08034beff78549b6f5757606ed302b9e68`](https://github.com/andrea-kozicki/conectaeduca/commit/527d6a08034beff78549b6f5757606ed302b9e68).
Ambos os SHA são fotografias históricas, **não tags de freeze**, e não
comprovam paridade das VMs.

Interpretar cada afirmação na ordem correta:

1. **Código versionado:** fonte disponível para revisão no Git.
2. **Estado observado:** registro de arquivo, serviço ou configuração na VM, com data.
3. **Teste executado:** resultado limitado à origem, identidade, janela e procedimento.
4. **Homologação completa:** depende de matriz positiva/negativa reprodutível e critérios
   de aceite atendidos; não inferir dos três estados anteriores.

## Matriz de encerramento por domínio

| Domínio | Última evidência relevante | Situação demonstrável | Lacuna no encerramento |
| --- | --- | --- | --- |
| **EP125 / DMZ / GA-08** | Registro de 09–10/11: WAF, Nginx e PHP saudáveis; HTTPS observado e tentativas diretas a `8080`/`9000` recusadas | Isolamento observado nas condições testadas | **22 artefatos locais GA-08** ainda aguardavam inventário/custódia; sem prova de paridade integral com `main` |
| **EP126 / Ferret / GA-06** | Cutover V5 e monitor verificados em 08/11; comparação Git de 17/11 | Fonte de seis arquivos V5 e processador Bash reconciliada na [PR #237](https://github.com/andrea-kozicki/conectaeduca/pull/237); identidade de arquivos comparada | Dois scripts Fish modificados localmente e metadados de release exigem triagem; rollback não foi ensaiado |
| **EP126 / Wazuh / PA-06** | Override 80710 V6 aplicado em 08/11; integridade e contêineres saudáveis verificados em 17/11 | Fonte literal e hash registrados na [PR #240](https://github.com/andrea-kozicki/conectaeduca/pull/240); alerta positivo pós-correção documentado | Cobertura E2E negativa, persistência futura e telemetria global não homologadas |
| **OpenBao** | Recuperação Shamir autorizada e healthcheck saudável em 08/11 | Serviço deslacrado naquele recorte | Não presumir disponibilidade futura, recuperação geral ou auditoria completa das ACLs |
| **Bacula** | Serviços, plano de backup e verificações parciais registrados | Arquitetura e controles documentados | Restore ponta a ponta e independência física do backup não demonstrados como cobertura completa |
| **Twingate / Zero Trust** | Conectores e políticas cadastrados, clientes autenticados e acesso ao portal observado | Implantação parcial de camada de acesso por identidade | Alias DNS do Wazuh com falha observada; MFA/RBAC com identidades separadas e caminhos legados ainda sem homologação abrangente |
| **Pentests A e B** | Sete pontos de ameaça exercitados, antes/depois de mudanças de arquitetura | Resultados e negativas pontuais documentados | Condições não equivalentes em todos os cenários; sem inferir redução percentual de risco ou exploração em todos os PAs |
| **GitHub / DevSecOps** | PRs integradas, testes e checks CI disponíveis | Código-fonte e verificações estáticas reproduzíveis sem as VMs | CI não prova implantação, política efetiva, restauração ou compatibilidade integral entre hosts |

### Não confundir evidência com disponibilidade futura

Snapshots de hipervisor foram informados pelo suporte em 09/11; sua existência
naquele momento **não concede custódia pessoal nem garante retenção** após o
desligamento institucional. Arquivos sob custódia da instituição, dumps, imagens
de contêiner, certificados e backups **não devem ser exportados para o Git**.

## Rotas de encerramento

| Quando | Documento | Objetivo |
| --- | --- | --- |
| **Agora, sem VMs** | [Continuidade offline](CONTINUIDADE-OFFLINE.md) | Preservar reprodutibilidade do código, resultados estáticos e narrativa técnica |
| **Último acesso autorizado à EP125** | [Checklist EP125 existente](../portfolio/EP125-PRE-ENCERRAMENTO.md) | Inventariar candidatos GA-08 sem deploy ou transferência indiscriminada |
| **Último acesso autorizado à EP126** | [Checklist EP126](EP126-ULTIMA-JANELA.md) | Inventariar diferenças Fish/Ferret e registrar integridade sem expor material privado |
| **Revisão de privacidade** | [Matriz pública de evidências](../portfolio/EVIDENCIAS-PUBLICAS.md) e [triagem de PRs](../portfolio/PR_TRIAGE.md) | Separar material publicável de conteúdo institucional ou sensível |
| **Candidato de arquivo acadêmico** | [Notas de release e gates](../release/RELEASE-ACADEMICO-CANDIDATO-2026-11-18.md) | Preparar um corte de **fonte e documentação**, sem declarar homologação operacional |

## Critérios de aceite para um fechamento documental honesto

- [x] Arquitetura, autoria individual e limites descritos publicamente no README.
- [x] Correções Ferret V5 e Wazuh V6 versionadas em PRs integradas, com ressalva de *source-only*.
- [x] Inventário EP125 preparado em código; execução final ainda **não confirmada**.
- [x] Plano EP126 preparado para execução futura; execução final ainda **não confirmada**.
- [x] PRs #243–246 integradas na `main` em 18/11, com SHA de referência pós-consolidação registrado.
- [ ] Revisão/autorização de divulgação da evidência final e de seus metadados.
- [ ] Situação dos arquivos locais EP125 e EP126 registrada após última janela ou marcada **NÃO VERIFICÁVEL**.
- [ ] PRs históricas ainda pendentes triadas individualmente; nenhuma PR de deploy promovida por presunção.
- [ ] Commit definitivo e checks do fechamento identificados após os merges aprovados.
- [ ] Registro explícito de **encerrado por expiração do laboratório**, se a infraestrutura for retirada sem novos testes.

**Status de fechamento em 18/11: EM PREPARAÇÃO.** Não declarar `FREEZE FINAL=PASS`,
`ZERO TRUST HOMOLOGADO`, `RESTORE E2E=PASS` ou `PARIDADE_GITHUB_VM=PASS`
sem nova evidência adequada.
