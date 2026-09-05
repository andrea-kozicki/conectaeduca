# Pacotes adicionais — CE-PFSENSE

## Fase 1A — rede base

Instalar **nenhum pacote adicional**.

Critério de saída:

- WAN/DMZ/INTERNA identificadas;
- endereçamento validado;
- regras mínimas aplicadas;
- fluxos esperados testados;
- bloqueios esperados testados;
- evidência coletada.

## Fase 1B — incremento IDS

Depois de aprovar a rede base:

- instalar **Suricata** pelo gerenciador oficial;
- iniciar em IDS/alert-only;
- habilitar fonte de regras adequada;
- validar logs/alertas;
- somente depois avaliar IPS.

## Fora de escopo no firewall

Não instalar apenas por conveniência:

- syslog-ng;
- Git;
- Docker;
- Wazuh;
- componentes da aplicação;
- banco;
- OpenBao;
- Bacula core;
- Twingate.

Princípio: mínimo de software no firewall e mudança de uma camada por vez.
