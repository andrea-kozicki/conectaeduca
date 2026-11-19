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
| **01 — segmentação** | Inventário de superfície e alcance entre zonas no Pentest A, sem baseline integral equivalente | A rede interna alcançou SSH da DMZ, contrariando a negativa esperada (**CE-F01**, alta); outros fluxos tiveram respostas limitadas à origem testada | Sem login SSH, movimento lateral autenticado ou atribuição da regra causal do pfSense | Efeito e escopo do teste, sem rastreadores ou regras reais de firewall |
| **02 — portal/DMZ** | WAF e acesso a backend investigados antes das mudanças de outubro/novembro | HTTPS via WAF respondeu; conexões diretas selecionadas recusadas, mas **duas inscrições legítimas foram bloqueadas pelo WAF (CE-F06, alta)** | A recusa de portas não cobre todas as bridges/origens; regra que bloqueou os POSTs legítimos requer correlação | Sintomas e correção proposta, sem payloads ou topologia privada |
| **03 — privilégios** | Sem baseline idêntico para todo o ambiente | A conta limitada não alterou o wrapper institucional `sudo`, embora apresentasse modo permissivo; imutabilidade bloqueou a escrita (**CE-F03**) | Sem escalada de privilégios demonstrada; comportamento e permissões exigem revisão com suporte | Descrição anonimizada do wrapper, sem SHA-256 e conteúdo do script |
| **04 — segredos** | Gestão OpenBao e controles de acesso em evolução | Leitura autorizada e negativas de operações fora da política foram observadas no teste da v41, inclusive fora da janela do token | Não equivale a teste de todas as ACLs, perfis, revogações e AppRole | Resultado por classe de operação, nunca tokens ou conteúdo de segredos |
| **05 — autorização** | Inscrições, MFA e RBAC avaliados de modo parcial no Pentest A | No Pentest B houve recusas por perfil, CSRF, logout e sessão liberada após segundo fator; envios legítimos de inscrição foram bloqueados pelo WAF | **BOLA horizontal não comprovada** por falta de objetos de inscrição comparáveis; controles de sessão não substituem autorização por objeto | Resumo de testes sintéticos, sem IDs de usuários ou registros |
| **06 — Wazuh** | Alertas e falsos positivos da regra 80710 investigados | Override V6 com alerta positivo pertence a um recorte anterior; na v41 o painel resolveu, mas houve falha de confiança TLS no cliente e não se produziu nova cadeia E2E de eventos | Correlação contemporânea, negações e telemetria integral permanecem pendentes | Regras e testes offline versionados; nenhum log bruto institucional |
| **07 — DLP/backup** | Ferret e Bacula inspecionados na primeira campanha, sem restauração aceita | Ferret v5 observado, porém inspeção sintética ficou **inconclusiva**; superfície de Bacula alcançável e acesso à API sujeito a autenticação | DLP efetivo, exportação, egress e restauração comprovada permanecem abertos | Contratos e evidência resumida, sem TAR, amostras reais ou backups |

**Conclusão atualizada em 18/11:** a v41 classifica o risco qualitativo do **recorte testado como alto**, principalmente pelo bloqueio de inscrições legítimas (**CE-F06**), alcance SSH entre zonas (**CE-F01**) e intermitência de acesso ao Wazuh (**CE-F05**). Sete PAs com atividade não significam sete explorações, sete correções aprovadas nem homologação Zero Trust.

## Conciliação editorial com o Pentest B v41

- **Fonte do confronto:** relatório acadêmico Pentest B **v41, de 16/11/2026, com evidências até 15/11**, sob custódia da autora e **não anexado a este diff**. A matriz histórica da [#218](https://github.com/andrea-kozicki/conectaeduca/pull/218) era um **plano em 02–03/11**, não o resultado final.
- **Cobertura:** duas origens de rede (DMZ e Intranet) e uma posição lógica autenticada no portal. A v41 **não comprova terceira origem de rede independente pela Internet pública**.
- **Efeitos prioritários:** falha de disponibilidade funcional de inscrição sob WAF (CE-F06), divergência de alcance SSH entre zonas (CE-F01) e intermitência do recurso Wazuh (CE-F05). A cadeia TLS não confiável no cliente aparece como limite adicional (CE-L05).
- **Interpretação:** bloqueio HTTP, resposta de porta, status `healthy`, script de teste e resultado sintético não certificam a política que causou o efeito nem o estado permanente da infraestrutura. A comparação A×B tem origens, datas e intervenções diferentes; não permite atribuir uma taxa global de melhora ao Twingate.
- **Pendências preservadas:** BOLA por objeto, WAF legítimo/negativo, autorização de fluxos de rede, investigação do TLS e disponibilidade Twingate, DLP e restore Bacula. A matriz [pré-VM](../operacao/CE-PREVM-GATES-20261118.md) mantém **12/12 `PENDING_VM`**; a publicação acadêmica tem gates próprios ainda pendentes.
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
