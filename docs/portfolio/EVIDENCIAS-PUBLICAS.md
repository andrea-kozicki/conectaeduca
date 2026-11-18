# ConectaEduca — Matriz pública de evidências

**Responsável pela execução e análise:** Andréa Kozicki (trabalho acadêmico individual)  
**Recorte temporal:** outubro–17 de novembro de 2026  
**Ambiente:** EP125/DMZ, EP126/rede interna e clientes autorizados; infraestrutura acadêmica da PUCPR.

## Critério de leitura

Este documento distingue quatro afirmações: **fonte versionada** (arquivo no Git), **configuração observada** (arquivo ou serviço na VM), **comportamento testado** (resultado de execução sob condições específicas) e **homologação completa** (matriz de comportamentos repetível, incluindo negativos). Uma evidência de nível anterior não prova automaticamente o posterior.

Os pentests **A (antes do Twingate)** e **B (após a introdução do Twingate e outras correções)** usaram condições e identidades nem sempre equivalentes. Portanto, não há base para atribuir diferenças exclusivamente ao Twingate ou calcular uma taxa geral de redução de risco.

## Matriz PA-01 a PA-07

| PA | Antes: Pentest A / contexto | Depois: Pentest B / evidência observada | Limite, não comprovado | Publicação apropriada |
| --- | --- | --- | --- | --- |
| **01 — reconhecimento** | Inventário de ativos e superfície de rede; não há baseline quantitativo comparável neste resumo | Metadados de host e identidade coletados no escopo autorizado | Nenhuma exploração ou redução mensurável inferida | Metodologia e resultados agregados, sem inventário bruto |
| **02 — portal/DMZ** | Arquitetura pré-ZTNA com WAF e backends em revisão | HTTPS com WAF observado; em testes selecionados, acesso direto a `8080`/`9000` recusado na EP125 | Outras origens, rotas e horários não equivalem a uma varredura completa | Explicação da fronteira e decisões GA-08, sem ativos operacionais sensíveis |
| **03 — privilégios** | Sem reteste de baseline idêntico documentado aqui | Wrapper institucional `/usr/local/bin/sudo` com permissão `0777` observado | Não houve escrita efetiva nem escalada de privilégios; não classificar como exploração crítica | Explicação anonimizada do achado e das restrições |
| **04 — segredos** | Gestão OpenBao implantada, com recuperação operacional em novembro | Identidade de teste com operações sensíveis negadas (`403`), incluindo consulta de capacidades e revogação própria | Não é auditoria completa de ACLs, tokens nem AppRole | Resultado HTTP e limites, nunca token ou segredo |
| **05 — autorização** | Inscrições e regras da aplicação em avaliação | Rotas e respostas HTTP observadas na identidade disponível | BOLA/IDOR não concluídos por insuficiência de contas de teste | Metodologia, sem registros de pessoas |
| **06 — Wazuh** | Regra 80710 com alertas que exigiram qualificação de falsos positivos (incluindo eventos numerosos no primeiro ciclo) | Override V6, `logtest`, SHA-256 de origem e alerta positivo pós-correção | Falta comprovação de correlação negativa E2E e cobertura de toda a telemetria | XML e validador de integridade versionados |
| **07 — DLP/backup** | Ferret e Bacula inspecionados; ao menos um alerta de DLP MEDIUM no primeiro ciclo | Ferret V5 em execução, proveniência/monitor e superfícies Bacula observados | UI DLP, restore e caminhos de egress sem reteste abrangente | Manifestos e validadores offline; não TAR institucional nem relatórios brutos |

**Conclusão:** os sete PAs tiveram atividades, mas **profundidade e força das evidências variaram**. PA executado não é sinônimo de vulnerabilidade explorada nem de correção homologada.

## Cadeia de evidências que pode ser auditada sem as VMs

| Artefato público | O que permite verificar | O que não permite inferir |
| --- | --- | --- |
| [PR #237 — Ferret GA-06](https://github.com/andrea-kozicki/conectaeduca/pull/237) | Manifestações de proveniência, políticas e scripts de preflight da imagem V5 | Posse do arquivo TAR institucional, disponibilidade da VM ou restauração |
| [PR #240 — Wazuh PA-06](https://github.com/andrea-kozicki/conectaeduca/pull/240) | XML V6 e sua identidade SHA-256, validadores estáticos | Cobertura E2E completa no runtime após o merge |
| [PR #238 — dependência PHP](https://github.com/andrea-kozicki/conectaeduca/pull/238) | Alteração versionada de dependência de segurança | Resultado de pentest equivalente a uma revisão externa |
| [Modelo STRIDE](../stride.md) e [fluxos de dados](../dfd.md) | Hipóteses de ameaça e arquitetura concebida | Correspondência automática com todo o estado de implantação |
| [Script de inventário EP125](../../scripts/evidencias/ep125_pre_encerramento_manifest.sh) | Após execução autorizada, lista caminhos candidatos e gera hashes de arquivos locais | Exportação automática, validação de conteúdo ou homologação do GA-08 |

O SHA-256 do arquivo XML Wazuh V6 documentado no recorte de novembro é:

```text
4da3e4fe32a151f058c6d646340e8fc8a410e7bcfd41124207830cfc7e691ecf
```

Este hash comprova identidade de bytes quando confrontado com o arquivo correto; não é assinatura de uma entidade independente.

## Política de divulgação da evidência

**Pode ser publicado após revisão:** diagrama lógico, trechos sanitizados de logs, contagens agregadas, procedimentos que não exponham contas institucionais, hashes e testes sintéticos.

**Não publicar:** tokens, senhas, chaves, certificados privados, caminhos com nomes de usuários institucionais, dumps de bancos, backups, TARs de imagem sob custódia, snapshots, relatórios DLP com conteúdo real, IPs detalhados de uma infraestrutura ainda ativa e registros identificáveis.

Antes de acrescentar prints ou relatórios, verifique titularidade, autorização de publicação, conteúdo visível, metadados de arquivo e histórico de commits. A remoção de um arquivo na versão atual não apaga suas cópias no histórico Git.

## Pendências reconhecidas

1. Conciliar, quando houver acesso, os candidatos e scripts GA-08 ainda locais na EP125, sem sobrescrever runtime.
2. Concluir inventário de Fish/EP126 e cópias de segurança antes do encerramento das VMs.
3. Separar PRs em rascunho de mudanças efetivamente integradas à `main`.
4. Preservar o status de RBAC/MFA/Twingate e de restauração como **parcial/não homologado**.

Veja também [lições aprendidas](LESSONS_LEARNED.md), [triagem de PRs](PR_TRIAGE.md) e [plano de encerramento EP125](EP125-PRE-ENCERRAMENTO.md).
