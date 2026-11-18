# ConectaEduca | Information Security Lab

**[Leia em português](README.md)** · [My role](#individual-ownership-and-scope) · [Architecture](#architecture) · [Case studies](#selected-case-studies) · [Pentests](#security-assessments) · [Evidence](docs/portfolio/EVIDENCIAS-PUBLICAS.md)

ConectaEduca began as an academic PHP application for educational opportunities and evolved into a **secure application, network defense, Linux administration, and DevSecOps lab** during the 2026 *Experiência Criativa 8* course.

The project combines a PHP application, a segmented DMZ/internal network, WAF, secrets management, DLP, SIEM, backup, and an experimental Zero Trust access layer. Security testing was conducted **before and after introducing Twingate**.

**Individually developed and documented by Andréa Kozicki.** I led the academic project end to end: architecture, integration, Linux hardening, automation, testing, security analysis, and presentation. PUCPR provided the academic infrastructure and technical support for its operation; this is not a claim of co-authorship. Third-party tools and dependencies retain their original authorship.

> **Reference date: November 17, 2026.** This is an academic lab, not a production service. Source code, deployed configuration, and end-to-end validation are different levels of evidence. The limitations below are intentional and should not be interpreted as completed security certifications.

## Individual ownership and scope

I carried out the student project **on my own**, from planning and implementation through two pentest rounds and their written reports. I distinguish personal engineering work from institutional access approvals and infrastructure support. The source history documents technical decisions, but does not imply that every third-party software component was written from scratch.

## Highlights

| Area | Implementation or assessment | Evidence boundary |
| --- | --- | --- |
| Application security | Local authentication, RBAC, TOTP MFA, CSRF protection, rate limiting, PHPUnit | Application-level tests, not an external certification |
| Defense in depth | pfSense segmentation; ModSecurity/OWASP CRS, Nginx, PHP-FPM in DMZ | HTTPS observed; selected direct-backend bypass attempts refused |
| Blue Team | Wazuh, FIM, auditd, YARA, Ferret DLP with minimized event forwarding | Wazuh rule 80710 V6 integrity verified; telemetry coverage not complete |
| Secrets and resilience | OpenBao, MariaDB, Bacula and recovery procedures | Selected tests/healthchecks; not every restore was retested end to end |
| Zero Trust | Twingate connectors, resources, groups and MFA policy configuration | Partial identity/access validation; Wazuh Dashboard DNS issue remains |
| Offensive security | Pentest A (before Twingate), Pentest B (after Twingate), seven threat points | Scenarios executed at different depths; no claim of full coverage |
| DevSecOps | PHPUnit, Composer Audit, Semgrep, Gitleaks, Snyk, source-integrity checks | CI supports source assurance, not direct runtime certification |

## Architecture

- **EP125 / DMZ:** web application behind WAF, Nginx and PHP-FPM.
- **EP126 / internal zone:** MariaDB, OpenBao, Ferret DLP, Wazuh and Bacula.
- **pfSense:** allowlisted traffic between zones, with no Docker network spanning the VMs.
- **Twingate:** identity-aware access to configured resources; its successful deployment did not establish complete MFA/RBAC enforcement for every identity or endpoint.
- **Telemetry:** Ferret's raw reports stay local; a sanitization step forwards minimized events to Wazuh.

The logical diagram and detailed security boundaries are in the [Portuguese README](README.md#arquitetura-do-laboratório). Additional context is in the [VM architecture](deploy/ARQUITETURA-VMs.md) and [STRIDE threat model](docs/stride.md).

## Selected case studies

| Challenge | My work | Observed result | Remaining limitation |
| --- | --- | --- | --- |
| DMZ WAF bypass paths (GA-08) | Prepared controlled Unix-socket/runtime configuration candidates, testing and rollback plan | Web route through WAF healthy; tested backend ports `8080`/`9000` refused connection | Some EP125 candidate files were not yet reconciled to GitHub |
| Wazuh rule 80710 false-positive analysis (PA-06) | Validated the V6 override, `logtest` cases, file hash and alert provenance | Positive post-change alert; immutable source evidence in PR #240 | Full negative end-to-end validation was not established |
| Identity-aware access (Twingate) | Configured connectors, resources, groups and MFA policies; tested Linux/Android clients | Healthy connectors and selected authenticated portal access | Wazuh Dashboard DNS resolution and full identity/MFA matrix incomplete |

Read the [detailed case studies in Portuguese](README.md#três-estudos-de-caso) and the [public evidence matrix](docs/portfolio/EVIDENCIAS-PUBLICAS.md).

## Security assessments

The before/after comparison helped assess the observed attack surface and access boundaries. **It does not isolate Twingate as the sole cause of changes:** test conditions and other controls also evolved.

Selected findings:

| Threat point | Observed result | Important limitation |
| --- | --- | --- |
| PA-02 — web entry | HTTPS/WAF path observed; direct access to selected backends refused | Limited to tested endpoints and origins |
| PA-03 — local privileges | Unusual `0777` permissions on an institutional `sudo` wrapper | No successful write or privilege escalation established |
| PA-04 — OpenBao | Limited identity received `403` for sensitive operations | Not a comprehensive policy audit |
| PA-05 — enrollment/authorization | Route and response observations | BOLA/IDOR coverage constrained by available accounts |
| PA-06 — Wazuh | Rule 80710 V6 captured byte-for-byte and positive alert documented | Negative end-to-end correlation not fully verified |
| PA-07 — DLP and recovery | Ferret/Bacula surfaces and health observed | Functional DLP UI and restore retests incomplete |

See the [Pentest discussion and coverage](README.md#pentests-e-resultados) for methodology details.

**Before vs. after:** the DMZ backend refusal, Wazuh V6 provenance, and Twingate authenticated access are selected observations—not controlled quantitative proof that Twingate alone caused every improvement.

## Source reconciliation and CI

- [PR #237 — Ferret V5 / GA-06](https://github.com/andrea-kozicki/conectaeduca/pull/237): versioned provenance and offline validation without performing a deployment.
- [PR #240 — Wazuh rule 80710 V6 / PA-06](https://github.com/andrea-kozicki/conectaeduca/pull/240): exact EP126 XML, SHA-256 validation and a read-only CI workflow.
- [PR #238 — phpseclib security update](https://github.com/andrea-kozicki/conectaeduca/pull/238).

The Wazuh V6 source artifact can be checked without access to the original VMs:

```bash
python3 scripts/evidencias/pa06_validar_80710_v6.py
```

Other source checks include Composer validation/audit, PHPUnit, Semgrep and Gitleaks. The institutional Ferret image archive is **not** distributed with this repository.

## Limitations

1. Reconciliation of source artifacts does not mean every VM checkout or runtime configuration was synchronized.
2. Some EP125/GA-08 deployment candidates and scripts remained local in the last inventory.
3. Full Twingate identity/MFA/deny testing and Wazuh Dashboard name resolution remained open.
4. Some pentest scenarios were partial because of identity, scope, infrastructure or time constraints.
5. The infrastructure relied on institutional network, hypervisor and support arrangements; it is **not** a one-command deployable demo.
6. Raw evidence may contain private or institution-specific data and is not automatically suitable for publication.

## Documentation and responsible use

- [Architecture evolution](docs/EVOLUCAO-ARQUITETURA-EC8.md) (Portuguese, historical)
- [Data-flow diagram](docs/dfd.md)
- [Security requirements](docs/requisitos-seguranca-asvs.md)
- [Ferret GA-06 provenance](docs/release/GA06-RECONCILIACAO-EP126.md)
- [Wazuh PA-06 V6 provenance](docs/release/PA06-WAZUH-80710-V6-EP126.md)
- [Public evidence and limitations](docs/portfolio/EVIDENCIAS-PUBLICAS.md) (Portuguese)
- [Lessons learned](docs/portfolio/LESSONS_LEARNED.md) (Portuguese)
- [Outstanding draft PR assessment](docs/portfolio/PR_TRIAGE.md) (Portuguese)
- [EP125 shutdown preparation](docs/portfolio/EP125-PRE-ENCERRAMENTO.md) (Portuguese)
- [Security reporting](SECURITY.md)

This repository documents academic laboratory work carried out individually by Andréa Kozicki, with institutional infrastructure support and third-party dependencies. It is not a production security guarantee. Do not publish private keys, live credentials, personal data, institutional dumps, or unapproved infrastructure evidence. No general reuse rights should be inferred from the absence of an explicit license.
