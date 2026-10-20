# Minuta — solicitação de autorização para Twingate no ConectaEduca

**Assunto:** ConectaEduca EC8 — autorização para Pentest B com Twingate após encerrar Pentest A

Prezados,

Após a finalização e preservação das evidências do Pentest A (sem Zero Trust), solicitamos a autorização e as condições para um Pentest B comparativo com Twingate, **sem alterar arbitrariamente a Fase 1 congelada**.

O desenho já previsto no repositório é um Connector na EP126, com acesso limitado à aplicação via **WAF HTTPS EP125, 192.168.6.34:443/TCP**. O usuário `teste` está sem sudo/Docker e **não executará** a ativação.

Solicitamos resposta aos seguintes pontos:

1. Podemos ativar um container Connector na EP126 **somente após** concluir o Pentest A? Quem será o operador e responsável por rollback?
2. Se não, existe host alternativo **autorizado** com rota EP125:443 e saída aos serviços de controle/relay do Twingate?
3. Qual egress externo Twingate está permitido e como deve ser autorizado? Não solicitamos abertura genérica.
4. Será permitido restringir o HTTPS direto no Pentest B para verificar efetivo isolamento? Se não, documentaremos acesso controlado em paralelo, **sem alegar Zero Trust exclusivo**.
5. Qual dispositivo de teste autorizado poderá usar Twingate Client, com certificado/CA interna e relógio confiáveis?
6. Há requisitos de privacidade, logs, gestão/rotação de tokens e reversão que devemos seguir?

A aplicação PHP, login, MFA, RBAC e serviços da Fase 1 serão preservados. Qualquer mudança exigirá aprovação específica e evidência.

Atenciosamente,
Equipe ConectaEduca — Experiência Criativa 8

[Plano completo](../seguranca/TWINGATE-RUNBOOK-POS-PENTEST-A.md).
