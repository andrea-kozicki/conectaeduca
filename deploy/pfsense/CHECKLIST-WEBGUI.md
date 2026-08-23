# Checklist — WebGUI do pfSense

## 1. Interfaces

- [ ] Confirmar WAN.
- [ ] Renomear/confirmar `DMZ`.
- [ ] Renomear/confirmar `INTERNA`.
- [ ] Confirmar endereços IPv4.
- [ ] Não expor WebGUI pela WAN.

## 2. Aliases

Hosts sugeridos:

- `VM_DMZ`
- `VM_INTERNA`

Portas sugeridas:

- `PORT_HTTP` = 80
- `PORT_HTTPS` = 443
- `PORT_MARIADB` = 3306
- `PORT_WAZUH_AGENT` = 1514
- `PORT_WAZUH_ENROLL` = 1515
- `PORT_BACULA_FD` = 9102
- `PORT_BACULA_SD` = 9103
- `PORT_SMTP_SUBMISSION` = 587

Só criar aliases de serviços que realmente entrarem na fase.

## 3. Regras

Regras são aplicadas na interface por onde o tráfego entra.

Prioridade inicial:

1. negar WAN -> INTERNA;
2. negar DMZ -> INTERNA por padrão;
3. adicionar exceção DMZ/PHP -> INTERNA/MariaDB TCP 3306;
4. adicionar Bacula 9102/9103 somente quando o Bacula entrar;
5. adicionar Wazuh 1514/1515 somente quando Agent/Manager entrarem;
6. manter serviços administrativos fora da WAN;
7. publicar WAF 80/443 somente após a aplicação estar saudável.

## 4. NAT

- [ ] Manter Outbound NAT automático no início, salvo exigência do laboratório.
- [ ] Não criar Port Forward para MariaDB/OpenBao/Wazuh/Bacula.
- [ ] Criar WAN -> WAF/DMZ 443 somente após teste interno.
- [ ] Porta 80 é opcional e deve servir apenas ao redirecionamento para HTTPS.

## 5. Administração

- [ ] Testar regra administrativa antes de remover proteções anti-lockout.
- [ ] WebGUI não acessível pela WAN.
- [ ] SSH permanece desativado inicialmente.
- [ ] Trocar senha padrão de administração.

## 6. Backup

Após cada marco importante, exportar `config.xml` via Backup & Restore e
guardar fora do Git.

Não versionar o `config.xml` bruto.
