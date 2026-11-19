# ConectaEduca — Cronologia pública do Zero Trust (31/10–15/11/2026)

> **Síntese documental sanitizada; sem execução em VM nesta revisão.** Esta linha do tempo confronta a [PR histórica #214](https://github.com/andrea-kozicki/conectaeduca/pull/214), o relatório **Zero Trust consolidado v2 (06/11/2026)** e o relatório **Pentest B v41 (16/11/2026; evidências até 15/11)**, ambos sob custódia da autora. Não equivale a homologação atual da infraestrutura. O histórico original da #214 continua separado, em draft, por conter scripts operacionais, capturas referenciadas e metadados de ambiente.

## Fronteiras de segurança

- **Aplicação pública:** portal PHP via HTTPS/WAF; autenticação, MFA e autorização por objeto pertencem à aplicação, e não são automaticamente asseguradas pelo Twingate.
- **Recursos privados:** Twingate introduz controle por identidade, grupo, Resource e política. A configuração no painel só demonstra intenção; teste efetivo exige identidade, dispositivo, recurso, política e resultado correlacionados.
- **Segmentação interna:** pfSense controla fluxos entre DMZ e Intranet; permitir ou negar um Resource Twingate não elimina uma rota direta entre hosts ou bridges.
- **Observabilidade e DLP:** Wazuh, Ferret e Bacula exigem evidências próprias de funcionamento, não apenas uma tela de acesso ao Resource.

## Linha do tempo comparada

| Período e fonte | Observação delimitada | O que não se pode concluir |
|---|---|---|
| **31/10 — #214** | Serviços Connector e cliente foram observados em contextos distintos; saúde local de contêiner e disponibilidade no Controller divergiram em algumas janelas. | Container `healthy` não comprova sessão estável, política aplicada nem alcance E2E. |
| **01–02/11 — adendos #214** | Registros datados mostram configuração de Resources, grupo de operação, política de MFA e ensaios pontuais de permissões no portal e Wazuh. | Esses ensaios não cobrem todas as identidades, revogação, redes, navegadores ou disponibilidade contínua. |
| **05/11 — Zero Trust v2** | Fluxos interzona selecionados foram permitidos e o SSH foi bloqueado após correção de regra, com logs no pfSense; acesso administrativo institucional preservado. | `PASS` vale para portas, direções e horários daquele teste; não representa toda a microsegmentação ou egress. |
| **06/11 — Zero Trust v2, CE-ZT50–52.3** | Connectors localmente saudáveis, porém erros recorrentes de sessão/controle e resets TCP correlacionados na rede; o painel e os Resources oscilaram. | A origem causal dos resets não foi provada; acesso E2E e estabilidade sustentada continuaram sem homologação naquele corte. |
| **12–15/11 — Pentest B v41** | Posteriormente, a rede interna alcançou SSH da DMZ (**CE-F01**), o painel Wazuh apresentou intermitência (**CE-F05**) e houve falha de confiança da cadeia TLS no cliente observado (**CE-L05**). | Não afirmar que a regra de 05/11 permaneceu válida, que o Twingate causou a divergência, nem que o Manager ficou indisponível de forma contínua. |

## Leitura dos controles e resultados

| Camada | Evidência necessária para aceite | Limite deste documento |
|---|---|---|
| Connector/Controller | Estado conectado sustentado no Controller, sem confundir com healthcheck local | Dados históricos em janelas não equivalentes |
| Resource/MFA | Acesso permitido e negado de identidades autorizadas, com eventos da política e MFA | Registros pontuais de tela/fluxo não validam todas as combinações |
| Wazuh/TLS | Nome e CA confiável no cliente, sessão permitida, acesso funcional e negação de perfil limitado | Certificado válido no servidor não prova confiança do cliente; a v41 detectou falha |
| pfSense/SSH | Regra efetiva, direção, log e resultado TCP comparáveis na mesma janela | O PASS em 05/11 e o alcance em novembro posterior exigem conciliação, sem atribuição automática |
| Aplicação/WAF | Login/MFA/RBAC por conta, objeto sintético e tráfego legítimo sem bloqueio indevido | A v41 registrou duas inscrições legítimas bloqueadas pelo WAF (**CE-F06**), que não é evidência de ZTNA eficaz |

## Pendências e custódia

1. A [matriz pré-VM](../operacao/CE-PREVM-GATES-20261118.md) registra **12 gates ainda `PENDING_VM`**; esses gates não se fecham com documentação ou CI.
2. [A issue #220](https://github.com/andrea-kozicki/conectaeduca/issues/220) acompanha pfSense/Twingate; as decisões operacionais dependem de nova autorização, inventário e evidência na janela correta.
3. A comparação Pentest A×B não tem condições idênticas e **não permite porcentagem causal de redução de risco pelo Twingate**.
4. Não anexar tokens, certificados privados, prints de painel, identificadores de sessão, IPs internos, arquivos de captura, logs brutos ou hashes de artefatos institucionais. As fontes completas ficam sob custódia da autora.
5. [A política de privacidade](PRIVACIDADE-E-PUBLICACAO.md) e o [gate pré-publicação](../release/GATE-PREPUBLICACAO-ACADEMICA-2026-11-18.md) continuam sujeitos à revisão de direitos, privacidade e autorização. Não criar tag ou release por causa desta síntese.

**Classificação:** material didático de cronologia e limites, não runbook, autorização de teste ou prova de ambiente atual. A PR #214 continua histórica e não deve ser mesclada integralmente.
