# GA-08 — PA-02: Matriz WAF, Nginx e PHP + testes de isolamento

**Data:** 25/10/2026 • **Estado:** projeto/aceite documental, SEM alteração das VMs ou pfSense.

## 1. Baseline observado (separar fato de inferência)
| Origem → destino | Evidência | Limite |
|---|---|---|
| Cliente → `192.168.6.34:443` (EP125 WAF) | Host WAF publica HTTPS e estava healthy em 25/10. A partir da própria EP125 o preflight HTTPS validou login 200. | Não prova que todos os clientes ou redes consigam chegar pela mesma política pfSense/CA. |
| Cliente → `192.168.6.34:80` (EP125 WAF) | WAF publica também a porta host 80. | Revisar política de redirecionamento; não assumir bloqueios/regras externas. |
| Host EP125 → Nginx bridge `172.18.0.3:8080` (inventário 24/10) | HTTP local chegou ao upstream. `/healthz` deu 404 no Nginx e 200 no WAF. | 404 demonstra resposta, não bypass efetivo nessa consulta. Endereço de bridge é efêmero e deve ser reconciliado antes da mudança. |
| Tráfego sintético WAF vs Nginx interno na primeira campanha | WAF bloqueou com 403; requisição comparável ao Nginx local obteve 200. | Diferença de filtragem comprovada, sem bypass externo nem movimentação lateral explorada. |
| Porta host EP125 `8088` | Sem `LISTEN` e Nginx sem host port bindings em 24–25/10. | Mitigação do acesso direto pelo HOST, mas não bloqueio de processos locais à bridge. |
| EP126 → `192.168.6.34:443` | TCP alcançável em 25/10. Validação TLS falhou `verify_code=20` por cadeia local não confiável. | Ainda não houve HTTPS autenticado/validado nessa origem; SAN/nome não foi conclusivo. |
| Nginx → PHP-FPM | Ambos `running/healthy`, sem bindings host para PHP. | Dependência funcional existe no stack, mas a política de rede entre contêineres não foi comprovada como deny-by-default. |

## 2. Política pretendida (depende do desenho e aprovação do suporte)
1. **Entrada pública:** HTTP/HTTPS do usuário final chega unicamente à superfície aprovada do WAF, preservando site público e observabilidade. Se acesso direto ao site público for mantido, não afirmar exclusividade Twingate.
2. **Upstream:** apenas a identidade/rede autorizada do WAF deve encaminhar HTTP ao Nginx. Conectividade host→bridge ou contêineres na mesma bridge deve ser avaliada explicitamente; simplesmente retirar a publicação de portas no host **não** produz isolamento interno.
3. **PHP:** somente origem autorizada do Nginx encaminha ao PHP-FPM nas portas efetivas, sem exposição pelo host. Examinar redes Docker, host firewall/DOCKER-USER e conexões de manutenção para não romper o serviço.
4. **EP126:** manter apenas acessos pontuais e aprovados à DMZ/rede interna; substituir permissões residuais amplas LAN49 por regras específicas, somente por operador institucional.
5. **Administração:** `/admin` e front público no mesmo IP:443 **não são diferenciados pelo Twingate em nível de URL**. Um endpoint privado separado (IP/porta/FQDN com rota realmente privada) requer desenho/aprovação; o RBAC/MFA PHP permanece necessário.

## 3. Matriz de reteste proposta pós-mudança/autorização
| ID | Origem autorizada ou adversária | Alvo | Resultado esperado | Evidência |
|---|---|---|---|---|
| GA08-P1 | Navegador público autorizado | HTTPS WAF, rota pública | HTTPS validado e resposta funcional | Status, HSTS/CSP, certificado, horário |
| GA08-P2 | WAF | Nginx upstream efetivo | Encaminhamento legítimo funciona | Config/sessão sanitizada, sem segredo |
| GA08-N1 | Identidade/processo local **não autorizado** na EP125, posição permitida pelo laboratório | Upstream sem passar pelo WAF | Bloqueio pela política aprovada | Origem, destino, decisão de firewall, logs correlacionados |
| GA08-N2 | Origem EP126 **não autorizada** | Upstream/bridge EP125 | Bloqueio esperado, sem ampliar acessos | Regra pfSense/host e evidência de negação; sem alegar bypass externo |
| GA08-N3 | Conta comum/cliente sem autorização privada | Endpoint administrativo privado | Negado pela política de acesso e pelo RBAC | Logs/identidades fictícias, sem expor token |
| GA08-R1 | Usuário final/autorizado | Login, MFA, oportunidade, inscrição | Sem regressões no aplicativo | HTTP esperados 200/302/401/403 conforme fluxo autorizado |

**Importante:** testar a hipótese de bypass somente após mudança de política e com autorização; resultados de timeout isolado não provam qual dispositivo bloqueou. Comparar cada evidência à baseline original e usar Wazuh/pfSense sem publicar logs completos.

## 4. Gates em 28/10
- [ ] Operador valida redes/bridges e as portas realmente usadas na versão atual do Compose; não confiar apenas em `172.18.0.3` histórico.
- [ ] Professor/suporte aprovam matriz origem→destino→porta, tratamento de LAN49, host firewall e redes Docker.
- [ ] Snapshots/configuração original/rollback da topologia e risco de perda de acesso conhecidos.
- [ ] DNS/CA e certificado oficial decididos para o FQDN; confiança TLS na EP126 validada depois da correção.
- [ ] Entrada de administração privada projetada e delimitada sem expor serviços internos.
- [ ] Retestes positivos/negativos agendados e autorizados, com custódia no diário e hash.

**Situação de encerramento do GA-08:** documentação preparada em 25/10. A **vulnerabilidade/risk residual PA-02 NÃO foi declarada corrigida**, pois a regra que impediria a origem não autorizada ainda não foi implantada e retestada. Referências: issue #204, PR #200, inventários EP125 de 24–25/10.

## 5. Gate automatizado offline GA-08 + Zero Trust (26/10/2026)

Durante a manutenção institucional, foi adicionado ao **PR #200, ainda DRAFT** um gate source-only, sem VM, tenant Twingate, Docker, pfSense nem alteração de firewall.

- **Código:** `tests/python/test_ga08_zt_contract_offline.py`, 14 testes, com leitura exclusiva de documentos e Compose versionados.
- **CI:** `.github/workflows/ga08-zt-offline.yml`, checkout por SHA fixado, permissões `contents: read`, nenhum segredo ou permissão de escrita.
- **Evidência:** GitHub Actions [GA08 ZT Static Contract, run 40401962266](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40401962266), job `121849850053`: **14/14 PASS**.

### O que esses testes realmente cobrem

1. O Compose-base contém `nginx:127.0.0.1:8088:8080` somente no contexto **de laboratório**; o overlay versionado `compose.waf.yml` mantém `ports: !reset []` e `expose: 8080`; `compose.host.yml` modifica bindings do WAF, não reabre 8088 no Nginx.
2. O `BACKEND` do WAF aponta a `http://nginx:8080` e preserva `no-new-privileges`.
3. O relatório GA-08 contém testes positivos e negativos e **não afirma** que o bypass da bridge já foi eliminado.
4. A matriz de Twingate documenta a entrada Admin PHP como **a projetar**, DENY para público e usuário sem grupo, ALLOW+MFA somente no grupo previsto; os grupos PHP RBAC não são convertidos em privilégios de rede.
5. Recursos privados SOC/Bacularis permanecem segregados e OpenBao/MariaDB/Catalog sem Resource exposto; conta sem grupo não recebe acesso privado; HTTP público 443 não é rotulado isolamento administrativo.
6. O Compose do Connector mantém digest SHA-256 explícito, perfil `twingate`, `network_mode: host`, `no-new-privileges` e sem declaração de `ports`, `volumes` ou socket Docker.

**Limites fundamentais:** a suíte não resolve Compose em runtime (ordem completa de overlays, variáveis secretas e `docker compose config`), não testa alcance real à bridge, nem implementa deny-by-default entre contêineres; examina invariantes textuais. A presença de `ports: !reset []` remove a publicação no host **quando o overlay correto é usado**, mas não impede que processos locais na EP125 acessem o IP da bridge Docker. O controle real ainda depende de política no host/Docker/pfSense, validação por origem autorizada e não autorizada e rollback institucional.

**Estado GA-08:** **preparação offline ampliada e teste estático 14/14 PASS; achado PA-02 continua ABERTO operacionalmente**. Nenhuma VM ou regra de firewall foi modificada.
