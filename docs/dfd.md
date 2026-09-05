# DFD — ConectaEduca pós-VMs

**Objetivo:** representar fluxos de dados, processos e trust boundaries da arquitetura atual.

**Escopo:** aplicação, DMZ, rede interna, observabilidade, segredos, backup e serviços externos.

Um DFD não substitui o diagrama de rede. Ele evidencia **quem produz/consome dados, por qual fronteira eles passam e quais dados não devem atravessar determinadas superfícies**.

## DFD nível 0

```mermaid
flowchart LR
    U[Entidade externa<br/>Usuário]
    APP((ConectaEduca))
    SEC((Plataforma de segurança))
    SMTP[Entidade externa<br/>Relay SMTP]

    U -->|requisições HTTPS / dados de negócio| APP
    APP -->|respostas / oportunidades / estado de conta| U
    APP -->|eventos e dados operacionais minimizados| SEC
    SEC -->|segredos materializados / recuperação / alertas| APP
    APP -->|mensagem de recuperação| SMTP
    SMTP -->|entrega de e-mail| U
```

## DFD nível 1

```mermaid
flowchart TB
    USER[Usuário / navegador]
    SMTP[Relay SMTP externo]
    ADMIN[Operador autorizado]
    KALI[Kali / teste autorizado]

    subgraph B0["Trust boundary 0 — rede externa"]
        USER
        SMTP
        KALI
    end

    PF((pfSense))

    subgraph B1["Trust boundary 1 — DMZ / EP125"]
        WAF((P1 WAF / TLS))
        NG((P2 Nginx))
        PHP((P3 PHP-FPM / aplicação))
        BFD1((P4 Bacula FD nativo))
        LOGA[(D1 logs locais sanitizados)]

        WAF -->|HTTP privado| NG
        NG -->|FastCGI| PHP
        PHP --> LOGA
    end

    subgraph B2["Trust boundary 2 — rede interna / EP126"]
        DB[(D2 MariaDB)]
        BAO[(D3 OpenBao Raft)]
        FERRET((P6 Ferret))
        RAW[(D4 relatório DLP bruto)]
        SAN((P7 sanitizador allowlist))
        EVT[(D5 dlp.jsonl)]
        WA((P8 Wazuh Agent))
        WM((P9 Wazuh Manager))
        WI[(D6 Wazuh Indexer)]
        WD((P10 Wazuh Dashboard))
        BD((P11 Bacula Director))
        BS[(D7 Bacula Storage)]
        BC[(D8 Bacula Catalog/PostgreSQL)]

        FERRET --> RAW --> SAN --> EVT --> WA --> WM --> WI
        WI --> WD
        BD --> BS
        BD --> BC
    end

    USER -->|HTTPS 443| PF --> WAF
    PHP -->|TCP 3306| PF --> DB
    SMTPSEC[(D9 arquivo SMTP efêmero<br/>host da DMZ)]
    SMTPSEC -->|secret somente leitura| PHP
    BAO -. futuro: TLS + Agent/Proxy + bootstrap seguro .-> SMTPSEC
    PHP -->|STARTTLS 587 quando habilitado| SMTP

    BD -->|TCP 9102 controle| PF --> BFD1
    BFD1 -->|TCP 9103 dados| PF --> BS

    BAO -. snapshot Raft consistente .-> BD

    ADMIN -. superfície administrativa restrita .-> WD
    KALI -. Pentest A/B autorizado .-> PF
```

## Fluxos e classificação

| ID | Origem → destino | Dado | Fronteira | Controle principal | Resultado/estado |
|---|---|---|---|---|---|
| F-01 | navegador → WAF | requisição HTTPS | externa→DMZ | TLS + CRS | entrada web prevista |
| F-02 | WAF → Nginx → PHP | HTTP/FastCGI interno | Docker DMZ | redes privadas, sem binding direto | backend não exposto |
| F-03 | PHP → MariaDB | consultas/dados da aplicação | DMZ→interna | pfSense + bind DB + credencial | TCP/3306 alcançável no teste |
| F-04 | arquivo efêmero do host DMZ → PHP | segredo SMTP | host DMZ→workload | arquivo fora do Git, permissões restritivas, secret somente leitura | contrato de consumo definido; integração OpenBao cross-VM ainda não habilitada |
| F-05 | PHP → relay SMTP | mensagem de recuperação | DMZ→externo | STARTTLS/autenticação | habilitado conforme runtime |
| F-06 | Ferret → relatório bruto | finding técnico | interna | filesystem restrito | não vai ao SIEM |
| F-07 | sanitizador → Wazuh Agent | evento DLP minimizado | interna | allowlist de campos | classificação Manager validada |
| F-08 | Agent EP125 → Manager | telemetria/FIM/YARA | DMZ→interna | TCP/1514 + regras Wazuh | fluxo operacional |
| F-09 | Director → FD EP125 | controle Bacula | interna→DMZ | TCP/9102 | alcançável no teste |
| F-10 | FD EP125 → Storage | dados de backup | DMZ→interna | TCP/9103 | alcançável no teste |
| F-11 | OpenBao → Bacula | snapshot Raft | interna | AppRole mínima + staging protegido | restore/hash validado em laboratório |
| F-12 | operador → Dashboard | administração SIEM | administrativa→interna | binding/rede restrita | não deve atravessar DMZ |
| F-13 | Kali → perímetro | probes/pentest | teste→arquitetura | escopo autorizado | pendente Pentest A/B |

## Dados que não devem atravessar determinadas fronteiras

Nunca encaminhar ao Wazuh como conteúdo normal:

- `reports/raw/` do Ferret;
- conteúdo original do arquivo analisado;
- senha;
- token;
- TOTP;
- recovery code;
- chave privada;
- unseal share;
- root token;
- dump SQL.

Nunca armazenar no Git:

- `.runtime/`;
- `.env` real;
- RoleID/SecretID reais;
- senha SMTP;
- credenciais Bacula/MariaDB/Wazuh;
- chaves privadas.

## Relação com STRIDE

O DFD fornece as trust boundaries usadas pelo threat model:

- **B0 → B1:** exposição web e ataques de aplicação/perímetro;
- **B1 → B2:** principal fronteira de movimento lateral;
- **runtime OpenBao → workload:** spoofing/elevação de privilégio de identidade;
- **Ferret → Wazuh:** risco de information disclosure por telemetria;
- **Bacula:** tampering/denial of service contra recuperabilidade;
- **administração:** elevação de privilégio e acesso indevido a superfícies internas.

Consulte `docs/stride.md` para o detalhamento das ameaças e `docs/plano-testes.md` para os casos de validação.
