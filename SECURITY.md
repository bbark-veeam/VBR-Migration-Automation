# Security Policy

## ⚠️ Not an official Veeam product

This is an **independent, community/courtesy tool**. It is **not an official Veeam
product** and is **not supported, endorsed, or maintained by Veeam Software**.
Although the author is a Veeam employee, it was developed independently. Veeam
Support cannot assist with it.

- **Vulnerabilities in Veeam Backup & Replication itself** (the product, its REST
  API, or the appliance) are **out of scope here** — report those through
  [Veeam's official vulnerability disclosure page](https://www.veeam.com/vulnerability-disclosure.html),
  not this repository.
- This policy covers **only the scripts in this repository**.

## Reporting a vulnerability

**Please do not open a public GitHub issue for a security problem** — that would
disclose it before it can be addressed.

Instead, use **GitHub's private vulnerability reporting**:

> Go to the repository's **Security** tab → **Report a vulnerability** (or the
> **"Report a vulnerability"** button under *Security advisories*).

This keeps the report private between you and the maintainer until a fix and an
advisory are published. Please include:

- what the issue is and the potential impact,
- steps to reproduce (and a proof-of-concept if you have one),
- the affected file(s)/function(s) and the version/commit you tested.

As a courtesy project this is handled on a **best-effort** basis — there is no
guaranteed response time or SLA. Please allow reasonable time to investigate and
fix before any public disclosure.

## Supported versions

Only the latest code on the **`main`** branch is maintained. Fixes are applied
there; there are no long-term support branches.

## Security considerations when using this tool

This tool moves Veeam configuration between servers and **forwards credential
passwords you supply at runtime**, so handle it accordingly:

- **Secrets are never committed.** The repository contains no credentials. Export
  artifacts (`output/`), real config files, `*.bco`, and credential exports are
  git-ignored. Keep them that way — never commit run output or a populated config.
- **Exports are environment-sensitive.** Even though Veeam omits plaintext
  passwords from its exports, the JSON still contains server FQDNs, UUID
  references, and structural details. Treat the `output/` folder, any CSV/JSON it
  produces, and any configuration backup (`.bco`) as **sensitive material** —
  store and dispose of them accordingly.
- **Credentials in transit.** When you provide source/target passwords, they are
  passed to the Veeam REST API over the connection you configure. Use HTTPS to the
  VBR servers and run from a trusted host.
- **Least privilege.** Use accounts with only the rights the migration needs, and
  rotate them afterward if appropriate.
- **Test first.** Run against a non-production environment and always have a
  verified Veeam configuration backup before importing into a target server.
