# Histórico de evolução — ConectaEduca

Este é um **registro de marcos técnicos e acadêmicos**, não uma lista de
releases SemVer. O repositório não recebeu uma versão de produção nem uma tag
de encerramento final por meio deste documento. **Código versionado, estado
observado nas VMs e homologação funcional são coisas diferentes.**

## 18 de novembro de 2026 — documentação e portfólio

- A [PR #241](https://github.com/andrea-kozicki/conectaeduca/pull/241)
  integrou a apresentação pública da autoria individual, três estudos de caso,
  matriz de evidências e plano de preservação pré-encerramento da EP125.
- A [PR #242](https://github.com/andrea-kozicki/conectaeduca/pull/242)
  adicionou infográficos de arquitetura e comparação entre os ciclos de
  pentest, disponíveis em versões PNG e SVG.
- A documentação passou a distinguir explicitamente correção de fonte,
  implantação observada, teste pontual e homologação completa.

## 17 de novembro de 2026 — reconciliação de fontes e dependências

- A [PR #237](https://github.com/andrea-kozicki/conectaeduca/pull/237)
  reconciliou arquivos do Ferret V5/GA-06 observados na EP126, incluindo
  política de imagem local, proveniência e validações offline. **O merge não
  realizou um novo deploy nem ensaiou rollback**.
- A [PR #238](https://github.com/andrea-kozicki/conectaeduca/pull/238)
  atualizou a dependência `phpseclib` para `4.0.3`.
- A [PR #240](https://github.com/andrea-kozicki/conectaeduca/pull/240)
  reconciliou a fonte do override Wazuh `80710` V6, verificada por SHA-256.
  O merge **não reexecutou testes de detecção na VM**.

## Outubro–novembro de 2026 — Pentests e arquitetura de acesso

- **Pentest A:** revisão ofensiva inicial da aplicação, serviços e controles
  antes da introdução do Twingate; sete pontos de ameaça consolidados com
  níveis de evidência distintos.
- **Hardening e Zero Trust:** ajustes de WAF, Nginx/PHP, monitoramento,
  gestão de segredos e Ferret; conectores, grupos, recursos e políticas de
  acesso do Twingate configurados em ambas as zonas.
- **Pentest B:** nova campanha a partir de identidade limitada, com testes
  de acesso, isolamento de backends, privilégios, OpenBao, Wazuh e DLP/backup.
  Nem todos os cenários tiveram reteste funcional conclusivo.
- Permaneceram abertos o acesso ao Wazuh Dashboard via alias DNS/Twingate,
  parte da matriz RBAC/MFA e a restauração ponta a ponta de backup.

## Anteriormente em 2026 — base do laboratório

- Evolução de uma aplicação web PHP acadêmica para laboratório segmentado
  com DMZ, rede interna e pfSense.
- Introdução de controles AppSec, integração contínua, testes PHPUnit,
  verificadores de segurança, SIEM, DLP, gestão de segredos e backup.

## Em revisão em 18 de novembro de 2026 — **não integradas à `main`**

| PR | Escopo | Estado neste corte |
| --- | --- | --- |
| [#243](https://github.com/andrea-kozicki/conectaeduca/pull/243) | Privacidade e governança de publicação | Aberta, sem merge |
| [#244](https://github.com/andrea-kozicki/conectaeduca/pull/244) | Validação estática YAML/XML sem VMs | Aberta, checks aprovados, sem merge |
| [#245](https://github.com/andrea-kozicki/conectaeduca/pull/245) | Encerramento técnico e preservação EP126 | Aberta, checks aprovados, sem merge |

PRs antigas em rascunho são **propostas ou registros históricos**, não
implantação ou release. Consulte a [triagem documental](docs/portfolio/PR_TRIAGE.md)
e a [matriz pública de evidências](docs/portfolio/EVIDENCIAS-PUBLICAS.md).

## Como referenciar uma versão do trabalho

Até que a autora aprove um corte final e uma tag, referencie o **SHA completo do
commit** consultado e a respectiva data. O arquivo [CITATION.cff](CITATION.cff)
fornece os metadados da autoria acadêmica; **citação não é concessão de licença
de reutilização**. Componentes de terceiros continuam sujeitos aos respectivos
termos, e arquivos institucionais não se tornam publicáveis por estarem
documentados neste histórico.
