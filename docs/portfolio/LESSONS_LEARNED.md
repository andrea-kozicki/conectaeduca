# ConectaEduca — Lições aprendidas e decisões de engenharia

**Autoria do trabalho acadêmico:** Andréa Kozicki, execução individual, com VMs, rede e suporte institucionais.  
**Contexto:** aplicação PHP em laboratório segmentado; dois ciclos de pentest, hardening, observabilidade e proposta Zero Trust.

O valor deste estudo não está em afirmar que todos os controles terminaram perfeitos: está na capacidade de **formular uma hipótese, testar, registrar a evidência, corrigir com limite de mudança e admitir o que não foi homologado**.

## 1. Fonte, VM e execução são três estados

**Problema:** um `merge` no GitHub não atualiza automaticamente o checkout de uma VM, não instala um override em Docker/Systemd e não comprova que o serviço executou aquele arquivo.

**Como tratei:** inventários por host, hashes SHA-256, comparação arquivo a arquivo, PRs de proveniência e uma worktree separada para revisão da `main`, protegendo arquivos locais. A PR #237 documentou Ferret V5 e a #240 registrou o XML Wazuh V6 no escopo *source-only*.

**Aprendizado:** usar o vocabulário certo nos relatórios: *proposto*, *versionado*, *observado no runtime*, *testado* e *homologado*. Cada salto exige nova evidência.

## 2. Endurecer a DMZ exige validar dependências

**Problema:** bloquear backends pode interromper o próprio portal quando Nginx e PHP-FPM usam interfaces/socket não alinhados.

**Como tratei:** configuração candidata GA-08, preflight, preparação de sockets, validação do acesso HTTPS, teste de recusa de acesso direto a `8080`/`9000`, registro de rollback e preservação de imagens.

**Aprendizado:** um teste `healthy` do contêiner é necessário, mas não substitui HTTP funcional via WAF e teste negativo do bypass. Os arquivos GA-08 ainda locais na EP125 continuam pendentes de reconciliação definitiva.

## 3. Detectar é diferente de reduzir falso positivo

**Problema:** volume de alertas da regra Wazuh 80710 não prova a mesma quantidade de incidentes reais. A definição de condições de detecção pode produzir ruído.

**Como tratei:** casos `logtest` positivos e negativos, override V6 com critérios de auditd, verificação da integridade do XML aplicado e observação de um alerta positivo depois do ajuste.

**Aprendizado:** o falso positivo deve ser demonstrado por entradas e condições reproduzíveis. O teste negativo E2E ainda requer verificação: **não** divulgar taxa de redução de falso positivo sem medir um conjunto comparável.

## 4. Zero Trust exige identidades distintas, DNS e evidência de negação

**Problema:** conectores saudáveis e grupos criados no painel de administração não provam que cada identidade só acessa os recursos autorizados. O alias do Wazuh Dashboard apresentou `NXDOMAIN` em clientes de teste.

**Como tratei:** implantação de conectores nas zonas, cadastro de recursos/grupos/políticas MFA e testes nos clientes Linux e Android.

**Aprendizado:** a homologação precisa de matriz `identidade × dispositivo × recurso × decisão/MFA`, com cenários permitidos e negados, além de DNS e certificados. Um dashboard inacessível por nome não prova nem negação intencional nem proteção eficaz.

## 5. Privilégios e indícios não são exploração

**Problema:** permissões `0777` no wrapper institucional de `sudo` eram visualmente preocupantes, mas a inspeção não demonstrou escrita efetiva nem escalada.

**Como tratei:** comparei metadados e limites da identidade sem privilégios e identifiquei a finalidade institucional do wrapper de aviso.

**Aprendizado:** separar condição aparente, capacidade efetiva e impacto; não classificar um achado como comprometimento sem comprovação.

## 6. DLP, segredos e backup requerem custódia e reteste

**Problema:** imagens offline, certificados, logs DLP e cópias de segurança podem ser úteis para evidenciar um exercício e, ao mesmo tempo, conter material inadequado para um GitHub público.

**Como tratei:** validação offline e de proveniência do Ferret V5, sanitização dos eventos enviados ao Wazuh, testes de acesso mínimo ao OpenBao e observação de serviços Bacula.

**Aprendizado:** não publicar imagens TAR institucionais, tokens ou dumps. Um Bacula saudável não equivale a restauração fim a fim; o que ficou sem reteste deve permanecer explicitamente pendente.

## 7. O encerramento de laboratório também é um exercício de governança

**Problema:** parte do estado executável permanece nas VMs e pode se perder quando as máquinas forem desligadas no fim do semestre.

**Resposta planejada:** inventário de candidatos GA-08 da EP125, comparação com a `main`, hashes, revisão de informações sensíveis e preservação autorizada do que for necessário; na EP126, conferir Fish local e backup anterior à reconciliação. Sem alterar serviços nem arrastar dados institucionais ao repositório.

**Aprendizado:** documentar o fim de vida do laboratório, as dependências externas e a não reprodutibilidade parcial é parte da qualidade do portfólio.

## O que eu faria diferente em uma próxima implementação

1. Estabeleceria, desde o início, **contratos de entrega por controle**: configuração, caso positivo, negativo, rollback e responsável.
2. Criaria um inventário versionado de **fonte versus runtime**, executado por CI e pela VM sem alterações automáticas.
3. Prepararia identidades de teste distintas e contas sintéticas antes dos testes de RBAC/BOLA.
4. Registraria a cadeia de custódia e regras de sanitização das evidências desde o primeiro dia.
5. Reservaria uma janela formal de desligamento para preservar artefatos autorizados, hashes e documentação, separadamente dos snapshots institucionais.

O projeto foi uma oportunidade prática de unir **AppSec, redes, Linux, SIEM, DLP, gestão de segredos, recuperação e DevSecOps** com um compromisso central: não exagerar as conclusões dos testes.
