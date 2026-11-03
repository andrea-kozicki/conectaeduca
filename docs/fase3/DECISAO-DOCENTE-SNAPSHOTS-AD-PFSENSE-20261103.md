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
