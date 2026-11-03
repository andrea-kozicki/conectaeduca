# ConectaEduca — decisão docente, snapshots e AD/pfSense

**Data:** 03/11/2026, BRT. **Origem:** comunicação da responsável sobre respostas do professor e suporte. **Natureza:** registro documental, sem alterações de firewall, Twingate, AD, Docker ou VMs.

## 1. Decisão do professor — superfície pública e privada

O professor confirmou que os usuários chegam pela **internet** e que a aplicação deve permanecer publicamente acessível por **HTTPS via WAF**, utilizando seus controles próprios de autenticação, MFA e RBAC. A função do **Twingate** é restringir recursos administrativos e infraestrutura interna, mediante grupos, Resources e políticas/MFA.

| Superfície | Caminho previsto | Controle |
| --- | --- | --- |
| Candidato e empresa (portal público) | Internet → HTTPS/443 → WAF EP125 → aplicação | Autenticação, MFA e RBAC da aplicação; usuário externo não precisa instalar Twingate |
| Administração de infraestrutura e Wazuh EP126 | Twingate Client → Resource privado → Connector interno → serviço | Grupos e política Twingate, MFA e login do serviço |
| Administração do próprio PHP | Deve permanecer protegida por MFA/RBAC; avaliar separação de listener/FQDN/ACL se exigir isolamento por rede | Twingate não filtra automaticamente caminhos administrativos no mesmo site HTTPS público |
| EP125 host→Docker bridge | Rede local de contêineres, independente do acesso remoto Twingate | GA08/PA-02 e controles de bridge/WAF continuam necessários |

Implicação Pentest B: PA-01 deve testar acesso público legítimo e acesso administrativo privado em cenários distintos; PA-02 precisa garantir HTTPS/443 público e impedir bypass por upstream; PA-05 deve separar os papéis PHP (administrador, empresa e candidato) dos grupos Twingate e das identidades Wazuh.

## Atualização operacional — acesso EP126 restabelecido com regras pfSense desativadas

**Informação comunicada pela responsável em 03/11:** a EP126 voltou a funcionar **porque a equipe de suporte desativou todas as regras do pfSense que a responsável havia configurado**. Isso **não** significa que o pfSense inteiro foi desativado, nem que outras regras automáticas/anteriores deixaram de funcionar. Tampouco é evidência de que um snapshot foi restaurado. Os snapshots foram reportados como **realizados**, não como **restaurados**.

- **Diagnóstico provável, não confirmado:** uma ou mais regras antigas estavam interferindo no fluxo necessário ao login/acesso da EP126 (DNS/AD/LDAP/Kerberos/NTP, retorno de conexão, rota ou outra dependência). A relação temporal é forte, mas não identifica regra/serviço culpado sem logs, tracking ID e testes comparáveis.
- **Estado atual de segurança:** acesso à EP126 restabelecido, porém a política específica de segregação/negação criada pela responsável **não está ativa**. Considerar o PA-01 **sem reteste de segmentação válida**, e não declarar resultado Zero Trust integral; o Twingate não substitui a filtragem L3/L4 do pfSense.
- **Não reativar todas as regras conjuntamente** nem recriar bloqueios em massa. Preservar o acesso funcional e um canal de recuperação operado pelo suporte.
- **Não inferir restauração da EP126:** somente se suporte comprovar restore, registrar ID/data e reconciliar divergências Twingate/Wazuh/Ferret/Bacula; sem restore, não promover reconciliação de snapshots como causa provável.

### Reconstrução segura e mínima da política pfSense (planejamento)

1. Solicitar ao suporte **backup da configuração atual** e a lista exata de regras que foram desativadas: interface (LAN/DMZ/floating), ação, ordem/quick, aliases, origem, destino, protocolo, porta, descrição, tracker ID e horário da desativação. Compartilhar somente extrato **sanitizado**, sem credenciais nem configuração integral.
2. Conferir em **Status > System Logs > Firewall** bloqueios relacionados à origem EP126 e destinos institucionais, e em **Diagnostics > States** os fluxos efetivamente aprovados; verificar *rule precedence*, NAT e sessões pré-existentes. Log ausente não prova passagem se a regra não registrava.
3. Identificar o caminho real do login (AD/domain join, SSSD/realmd, RDP/SSH/Guacamole, DNS, NTP) com o suporte; não assumir que a tabela de portas AD é a causa suficiente. Conferir IPs DC reais e eventuais 445/RPC condicionais sem abrir uma faixa ampla.
4. Propor regras **permitir serviço estritamente necessário antes das negativas específicas** com origem, DC e destino restritos; manter bloqueios de movimento lateral não relacionado. Revisar primeiro o **diff e ordem de aplicação**, não operar diretamente no firewall.
5. Reintroduzir **uma regra ou grupo coerente por janela autorizada**, com caminho de gestão/rollback fora do bloqueio, teste positivo de login EP126 e teste negativo de segregação em cada alteração. Em caso de perda de login, desfazer somente a última mudança e registrar o tracker ID.
6. Após estabilização: retestar PA-01 com mesma origem/destino/identidade; só então registrar resultado na matriz Pentest A×B, e avançar GA06/PA07 EP126 conforme seu gate próprio.

**Referência pfSense:** https://docs.netgate.com/pfsense/en/latest/troubleshooting/firewall.html (log, tabela de estados, precedência e interface de entrada); https://docs.netgate.com/pfsense/en/latest/monitoring/logs/firewall.html (tracker ID).

**Status:** EP126 acessível após suspensão de regras personalizadas; causa exata e segurança da segmentação ainda não verificadas; nenhuma regra alterada pelo GitHub.

## Evidência visual complementar — regras pfSense em 03/11

**Fonte:** capturas da responsável do painel `Firewall > Rules`, interfaces LAN33, LAN49, LAN111 e LANDOPFSENSE, em conjunto com capturas anteriores Floating, WAN e Aliases. **Somente leitura, sem export completo.** A aparência cinza e os ícones de habilitação indicam regras desativadas; contadores de tráfego não demonstram por si trajetórias ou eficácia.

| Interface | Regra(s) específica(s) em cinza/desabilitadas | Regras gerais visivelmente habilitadas |
| --- | --- | --- |
| LAN33 (origem EP125 192.168.6.34) | 4 TCP EP125→EP126 nas portas 3306, 1514, 9103 e 1515; bloqueio LAN33→LAN49; DNS para `CE_DNS_INST`:53; egress HTTP/HTTPS (80/443) para fora de `CE_RFC1918`; bloqueio egress restante — **9 regras desabilitadas** | 1 Pass IPv4 origem/destino/porta `*`, além da regra `Default allow LAN to any rule` |
| LAN49 (origem EP126 192.168.6.50) | TCP EP126→EP125 portas 9102, 80 e 443; bloqueio LAN49→LAN33; DNS `CE_DNS_INST`:53; egress Internet HTTP/HTTPS; bloqueio egress restante — **8 regras desabilitadas** | 1 Pass IPv4 origem/destino/porta `*`, além da regra `Default allow LAN to any rule` |
| LAN111 | Nenhuma regra específica do ConectaEduca identificada | Pass IPv4 any→any; outra Pass com origem textual `LAN33 subnets`, a validar se é coerente com a interface |
| LANDOPFSENSE | Nenhuma regra específica do ConectaEduca identificada | Pass IPv4 any→any |
| Floating (captura anterior) | **Quatro regras de bloqueio aparentemente habilitadas**, destino `10.96.41.0/24`, origens LAN33/LAN49/LAN111/LANDOPFSENSE; direção/Quick não demonstrados | Não presumir que foram desabilitadas pelo suporte; checar metadados da regra |
| WAN (captura anterior) | Uma regra desabilitada | Pass IPv4 any→any de descrição institucional `Regra de Acesso (nao alterar)`; confirmar topologia WAN antes de avaliar exposição externa; não alterar |

**Interpretação para PA-01:** regras específicas de allow e deny foram desativadas juntas. As permissões genéricas ativas podem permitir tráfego que se pretendia restringir, mas não justificam afirmar que todo o tráfego passa: Floating com Quick, regras automáticas/NAT e a tabela de estados podem interferir. O restabelecimento do acesso após a desativação é correlação temporal; a causa exata precisa do histórico de bloqueios/regra tracker, direção, interfaces e DCs de AD. Os DNS `10.96.210.37/127` não coincidem com o destino `10.96.41.0/24` dos bloqueios Floating, embora outros DCs/serviços possam estar naquela rede.

**Decisão operacional:** manter configuração atual, obter backup e aprovação do suporte; identificar interface de ingresso, rule order/Quick e origem/destino dos fluxos necessários. **Não reativar o conjunto completo nem desativar as regras genéricas de qualquer→qualquer remotamente.** Planejar permissões mínimas para login/DNS/AD e serviços legítimos e testar um conjunto de regras por vez, com acesso de recuperação independente, logs e rollback. Não limpar a tabela de estados em produção para forçar retestes sem janela autorizada.

## Detalhamento visual da primeira regra Floating — 03/11/2026

**Capturas de visualização de edição, nenhuma alteração realizada:**

| Campo | Valor confirmado na interface |
| --- | --- |
| Ação / estado | `Block` / `Disabled` desmarcado (**habilitada**) |
| Quick | Habilitado — processa imediatamente correspondências |
| Direção / protocolo | Any (entrada e saída) / IPv4 qualquer protocolo |
| Origem / destino | `LAN33 subnets` → `10.96.41.0/24` |
| Interfaces | LAN33 e LAN49 aparecem selecionadas no trecho visível; a lista da regra na aba Floating mostra LAN33/LAN49/LAN111/LANDOPFSENSE (verificar todos os itens quando necessário) |
| Logging | Desabilitado: ausência no log **não prova** que não houve bloqueio |
| Tracking ID | `1753729384` |
| Criada / atualizada | 28/07/2025 15:03:04 / 15:04:56; usuário exibido `admin` de `10.96.43.224` |

**Interpretação:** por ter `Quick` marcado, a regra Floating de bloqueio pode ter precedência sobre as permissões genéricas nas abas de interface quando houver correspondência efetiva; direção `any` abrange entrada e saída no conjunto de interfaces selecionadas. A origem `LAN33 subnets` está associada à rede da EP125, **não diretamente à origem EP126 `LAN49 subnets`**. Os endereços DNS institucionais informados, `10.96.210.37` e `10.96.210.127`, **não pertencem** a `10.96.41.0/24`. Isso **não identifica** o bloqueio responsável pelo login EP126, podendo haver regras adicionais, DCs em outras redes, roteamento, estados ou dependências. O histórico de julho/2025 **não autoriza atribuir autoria à responsável**. Pedir ao suporte identificação das regras antigas e propriedade/objetivo antes de alterá-las.

**Próxima verificação de risco zero:** examinar sem salvar o editor da regra Floating cuja origem é **`LAN49 subnets`**, verificar `Disabled`, `Quick`, interfaces, direção, destino e Tracking ID. Confirmar com suporte qual fluxo falhava durante o login e quais regras de fato foram desativadas. Não ativar `Log`, não mudar regras ou limpar states remotamente para tentar reproduzir o defeito.

Fonte técnica: https://docs.netgate.com/pfsense/en/latest/firewall/floating-rules.html (ordem, Quick e direção).

## Esclarecimento da responsável — autoria das regras e falha de acesso Guacamole

**Informação posterior de 03/11:**

- A responsável **criou apenas as regras específicas do ConectaEduca nas abas LAN33 e LAN49**, **não** as duas regras genéricas `Pass` remanescentes em cada interface. As quatro regras Floating não devem ser atribuídas à responsável; a primeira tinha data de criação em julho de 2025.
- O sintoma da EP126 era **falha ao entrar na sessão de desktop Ubuntu por meio do Apache Guacamole**, e não necessariamente falha de login direto do Ubuntu ou autenticação no Active Directory. O acesso Guacamole foi restabelecido depois de as regras personalizadas terem sido desabilitadas. **AD não está demonstrado como causa**.
- Distinguir **(1) navegador→portal Guacamole; (2) serviço guacd/Guacamole→EP126 RDP/xrdp (geralmente 3389/TCP, confirmar protocolo/porta configurados); (3) autenticação Linux/PAM/SSSD apenas após conexão RDP**. Falha em qualquer trecho pode produzir percepção de "login não entra".
- **Hipótese prioritária PA-01, condicionada à localização do servidor Guacamole:** se o Guacamole/guacd inicia a conexão da LAN33 para EP126 (LAN49), a regra personalizada `Block LAN33 subnets → LAN49 subnets`, **se habilitada**, poderia negar a sessão RDP por não haver uma regra `Pass` específica de Guacamole→EP126:3389 acima desse bloqueio. Os `Pass` LAN33→EP126:3306/1514/9103/1515 não equivalem a RDP. **Isto é hipótese, não prova:** determinar primeiro IP/interface do serviço Guacamole e protocolo/porta da conexão.
- Não criar uma permissão ampla `LAN33→LAN49`, nem liberar RDP para qualquer origem, sem validar origem real. Se o serviço Guacamole estiver em outra interface, investigar a regra dessa **interface de ingresso** e eventuais Floating/Quick; as regras pfSense de interface são processadas na interface de entrada e são stateful. O retorno de uma conexão permitida não requer abrir indiscriminadamente tráfego no sentido oposto.
- Evidência necessária, **somente leitura**: tela da conexão Guacamole mostrando tipo de protocolo, hostname/IP e porta (ocultar usuário, senha, domínio, tokens); IP/interface do processo `guacd` ou servidor que inicia a sessão, mensagem exata de erro (conexão recusada/timeout versus credencial negada), e logs minimizados dos bloqueios quando disponíveis. Não tentar reproduzir a falha com o bloqueio reativado antes de janela e rollback aprovados.

**Ajuste de interpretação do documento:** referências anteriores a "falha AD na EP126" devem ser lidas como **possível dependência a investigar**, não diagnóstico confirmado.

Referências: https://guacamole.apache.org/doc/gug/configuring-guacamole.html (RDP hostname/port); https://docs.netgate.com/pfsense/en/latest/firewall/rule-methodology.html (interface de ingresso e estados).

## Evidência complementar — segunda regra Floating LAN49 (03/11)

**Fonte:** duas capturas de tela da edição da regra Floating cuja origem é `LAN49 subnets` (associada à rede EP126).

| Parâmetro | Valor observado |
| --- | --- |
| Ação / estado | Block / Disabled desmarcado — **habilitada** |
| Quick | Marcado, avaliação imediata ao corresponder |
| Direção / protocolo | Any / IPv4 qualquer |
| Interfaces selecionadas visíveis | LAN33 e LAN49 (não assumir que a lista visível mostra todas) |
| Origem | `LAN49 subnets` |
| Destino | `10.96.41.0/24` |
| Log | Desmarcado |
| Tracking ID | `1753729514` |
| Data de criação / atualização | 28/07/2025 15:05:14; usuário registrado `admin` em `10.96.43.224` |

**Interpretação cautelosa:** a regra Floating anterior tem origem `LAN33 subnets` e tracker `1753729384`; as duas precedem o ConectaEduca e não são alterações feitas pela responsável. A regra LAN49 bloqueia tráfego **com destino `10.96.41.0/24`**. A conexão normal Guacamole/guacd→EP126 via RDP, se configurada para o IP da EP126 `192.168.6.50`, **não corresponde diretamente ao destino** deste bloqueio. Poderia haver dependências secundárias nessa rede, mas isso não foi demonstrado. Os DNS institucionais `10.96.210.37/127` não estão no prefixo `10.96.41.0/24`.

A **principal hipótese ainda não confirmada** é uma regra do ConectaEduca em LAN33 bloqueando comunicação interzona Guacamole/guacd→EP126, **se** a origem Guacamole estivesse na LAN33 e o protocolo fosse RDP/3389. Alternativamente, podem ser necessários DNS/AD/SSSD após a conexão: sem logs e informação de origem Guacamole e tipo da mensagem de erro, não atribuir a falha a nenhum deles.

**Próxima ação de risco zero:** obter do suporte IP/interface de origem do serviço Guacamole/guacd, protocolo/porta configurados e o estágio exato da falha (timeout/transporte versus credenciais/PAM/SSSD). Não reativar, desativar ou reordenar as regras nem apagar estados enquanto o acesso recuperado é necessário. Não são necessários novos prints das Floating já analisadas.

## 2. Snapshots — realização informada, verificações pendentes

O suporte comunicou **snapshots realizados**. Não foram fornecidos nesta comunicação IDs, horários, escopo de cobertura, hipervisor, retenção nem demonstração de restaurabilidade. Não inferir que cada VM tem snapshot recuperável completo.

| Verificação | EP125 | EP126 |
| --- | --- | --- |
| Realização | Informada pelo suporte; identificação ainda não fornecida | Informada pelo suporte; identificação ainda não fornecida |
| ID, horário, operador e hipervisor | PENDENTE | PENDENTE |
| Discos, binds protegidos, volumes, certificados e estado necessários | PENDENTE | PENDENTE (Ferret .runtime/estado e scripts DLP locais) |
| Restore/rollback, retenção e janela autorizada | PENDENTE | PENDENTE |
| Estado funcional atual | Revalidar na janela | Acesso restabelecido após suporte desativar todas as regras criadas pela responsável no pfSense; confirmar método de login e serviços sem generalizar a segurança da segmentação |

**Decisão:** gates GA08-G0 (EP125) e GA06-G0 (EP126) ainda FECHADOS até confirmação dos demais requisitos, apesar da notícia positiva dos snapshots.

Se o suporte restaurar a EP126 de um snapshot mais antigo, primeiro obter **qual ponto foi restaurado e o que mudou**. Não presumir que persistem Connector Twingate, regras Wazuh PA07, scripts DLP GA07.7B, Bacula e demais mudanças posteriores. Reconciliar somente diferenças verificadas; não executar reset Git, reinstall ou reconfiguração em lote.

## 3. Tabela AD informada pelo suporte — proposta inicial, não regra aplicada

| Destino | Porta | Protocolo | Finalidade |
| --- | --- | --- | --- |
| Resolvedores DNS 10.96.210.37 e 10.96.210.127 | 53 | TCP/UDP | DNS/SRV para localizar domínio/DCs |
| Controladores de domínio (endereços a confirmar) | 88 | TCP/UDP | Kerberos |
| Controladores de domínio (endereços a confirmar) | 389 | TCP/UDP | LDAP/CLDAP |
| Controladores de domínio (endereços a confirmar) | 464 | TCP/UDP | Alteração de senha Kerberos |
| Controladores de domínio (endereços a confirmar) | 3268 | TCP | Global Catalog (conforme cliente) |
| Servidor NTP a identificar | 123 | UDP | Sincronismo de horário (conforme arquitetura) |

**Não presumir que os IPs DNS também são IPs dos DCs ou NTP.** O suporte reconheceu que a tabela pode conter aberturas de mais ou de menos.

### Portas adicionais a avaliar, não liberar preventivamente

| Porta | Cenário de possível necessidade |
| --- | --- |
| 445/TCP | SMB/SYSVOL/GPO e determinadas integrações/ingresso |
| 135/TCP | RPC endpoint mapper, especialmente ingresso Windows/Netlogon |
| 49152–65535/TCP | RPC dinâmico conforme clientes Windows/servidores; **não liberar a faixa inteira por padrão** |
| 636/TCP | LDAPS, exigindo CA/certificado/hostname apropriados |
| 3269/TCP | Global Catalog via TLS, se utilizado |
| 9389/TCP | AD Web Services, apenas se houver uso administrativo demonstrado |

As exigências dependem do cliente (Ubuntu SSSD/realmd/adcli, Windows, aplicação LDAP etc.), funcionalidade (login, join, GPO, serviços) e controladores reais. A publicação WAN de Kerberos/LDAP/RPC não faz parte do escopo. Referências técnicas:

- Microsoft: https://learn.microsoft.com/pt-br/troubleshoot/windows-server/active-directory/config-firewall-for-ad-domains-and-trusts
- Microsoft (ingresso): https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/active-directory-domain-join-troubleshooting-guidance
- Red Hat (SSSD/Linux): https://docs.redhat.com/pt-br/documentation/red_hat_enterprise_linux/9/html-single/integrating_rhel_systems_directly_with_windows_active_directory/index
- Twingate Resources: https://www.twingate.com/docs/resources/

## 4. Decisão sobre pfSense — somente preparar change control

1. Identificar **host de origem, IP/sub-rede e direção** do fluxo AD (EP126, EP125 ou outro), SO, stack de autenticação e finalidade de ingresso/login.
2. Solicitar FQDN do domínio, endereços exatos dos DCs, papel dos DNS 10.96.210.37/127 e NTP efetivo; não misturar DNS e DC sem confirmação.
3. Propor aliases de hosts exatos e grupos de portas necessários por serviço, política stateful de origem→destino e logs de negação; **não** liberar Any→Any, CIDRs amplos ou todas as portas RPC preventivamente.
4. Aplicar somente com aprovação institucional do pfSense, backup de configuração/diff e rollback; testar em etapas DNS SRV/A, horário, Kerberos/LDAP, login de conta de teste e SMB/GPO apenas se necessário.
5. Preservar credencial local de recuperação da EP126 e distinguir falha de rede AD de falha de restauração ou configuração do host.

**Nenhuma regra pfSense foi alterada por este registro.**

## 5. Prioridades

1. Confirmar IDs, cobertura, retenção e restaurabilidade dos snapshots EP125 e EP126.
2. Confirmar com o suporte o **método de login EP126 que voltou a funcionar e o conjunto exato de regras pfSense desativadas**; verificar se houve restauração (ainda não demonstrada) e manter acesso recuperável antes de reconstruir a política.
3. Solicitar ao suporte origem/destinos/serviços AD; revisar política de menor privilégio no pfSense.
4. Preservar o portal público no WAF e os Resources administrativos no Twingate, conforme decisão docente.
5. Liberar GA08/PA-02 e GA06/Ferret somente em janelas e gates separados; Pentest B após estabilização.

**Este documento não constitui autorização de mudança nem prova de restauração.**
