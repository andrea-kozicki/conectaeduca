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

## 2. Snapshots — realização informada, verificações pendentes

O suporte comunicou **snapshots realizados**. Não foram fornecidos nesta comunicação IDs, horários, escopo de cobertura, hipervisor, retenção nem demonstração de restaurabilidade. Não inferir que cada VM tem snapshot recuperável completo.

| Verificação | EP125 | EP126 |
| --- | --- | --- |
| Realização | Informada pelo suporte; identificação ainda não fornecida | Informada pelo suporte; identificação ainda não fornecida |
| ID, horário, operador e hipervisor | PENDENTE | PENDENTE |
| Discos, binds protegidos, volumes, certificados e estado necessários | PENDENTE | PENDENTE (Ferret .runtime/estado e scripts DLP locais) |
| Restore/rollback, retenção e janela autorizada | PENDENTE | PENDENTE |
| Estado funcional atual | Revalidar na janela | Problema de login informado; recuperar e verificar antes de mudanças |

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
2. Confirmar reparo de login da EP126 e se houve restauração para ponto anterior; registrar drift antes de qualquer correção.
3. Solicitar ao suporte origem/destinos/serviços AD; revisar política de menor privilégio no pfSense.
4. Preservar o portal público no WAF e os Resources administrativos no Twingate, conforme decisão docente.
5. Liberar GA08/PA-02 e GA06/Ferret somente em janelas e gates separados; Pentest B após estabilização.

**Este documento não constitui autorização de mudança nem prova de restauração.**
