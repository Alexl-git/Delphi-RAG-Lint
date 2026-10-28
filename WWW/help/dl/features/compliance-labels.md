---
id: compliance-labels
title: Compliance labels (CWE, CERT, MISRA)
summary: Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field
product: DL
group: linting
order: 30002
since: 1.37.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Compliance labels (CWE, CERT, MISRA)

Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field.

Read this when you must show which lint rules map to CWE, CERT or MISRA, or restrict a run to one standard. Labelled findings print their ids with --labels, and the cwe, cert, misra and cwe-top25 profiles select the labelled rules.

## How to run it

```text
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>] - list every lint rule (catalog)
```

Example:

```text
drag-lint rules --standard cwe
```

Full flag list: [rules in the CLI reference](../cli.md#rules).

```text
drag-lint lint-all [--db <file.sqlite>] [--project <.dproj>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--quiet] [--lint-third-party] [--no-preprocess]
```

Example:

```text
drag-lint lint-all --db <db> --profile cwe-top25 --labels
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Every lint rule can carry the CWE, CERT and MISRA ids it answers. The labels are metadata for audit tooling; they never change a rule's severity, its default state or an exit code.

### Where they live

One file, `rules\compliance.json`, shipped beside the other rule sidecars: an object keyed by rule id, one line per rule, sorted, every rule present (an unlabelled rule is `{}`). `weak` lists the ids whose fit is only plausible.

### Using them

| You want | Command |
|---|---|
| the ids of each rule | `drag-lint rules` (suffix `[CWE-476 EXP34-C]`) or `rules --json` (`compliance` object: `cwe`, `cert`, `misra`, `weak`, always present) |
| only rules under one standard | `drag-lint rules --standard cwe` (or `cert` / `misra`) |
| the ids on findings (machine) | `lint --json` / `lint-all --json`: a `compliance` object on each labelled finding, absent otherwise |
| the ids on findings (text) | `lint --labels` / `lint-all --labels` appends ` [CWE-798]` to the message; default text is unchanged |

### Rules of the file

* Id formats: `CWE-<n>`; CERT `ABC12-C|CPP|J`; MISRA `MISRA-C-2012-R<n>.<n>`, `D<n>.<n>`, `MISRA-CPP-2008-<n>-<n>-<n>`. A malformed id makes `drag-lint rules` fail (exit 2); a missing file gives empty labels and one stderr note.
* Guard: `tests\autotest\run_compliance_labels_guard.ps1` (completeness, formats, positive and negative controls, `lint --json`).
* Not an extractor change; `DRAGLINT_EXTRACTOR_VERSION` is untouched.

### SARIF taxonomies

`--format sarif` carries the labels: `run.taxonomies[]` holds one toolComponent per standard that
has an id in the run (CWE / MITRE, CERT / SEI, MISRA / MISRA; `taxa[]` ids only, CWE without the
`CWE-` prefix). Each `driver.rules[i]` gains `name`, `shortDescription`, `defaultConfiguration.level`,
`properties.tags` (category, `external/cwe/cwe-798`, `external/cert/MSC41-C`, ...),
`properties["security-severity"]` for CWE-labelled rules (error 8.0, warning 5.0, else 2.0) and
`relationships[]` (`kinds: ["relevant"]`) pointing into the taxonomy. A rule without labels has no
`relationships` key. Weak ids are emitted like confident ones (SARIF has no per-relationship confidence).

### Built-in profiles

`--profile cwe | cert | misra | cwe-top25` enables the rules labelled under that standard, disables
every other rule and floors the selected rules at severity `warning`, so
`drag-lint lint-all --profile cwe --fail-on warning` is an audit gate. `cwe-top25` selects rules
with a CWE id in the 2025 CWE Top 25 (`CWE_TOP25_2025` in `DRagLint.Lint.Compliance.pas`, read from
https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html on 2026-10-27). A profile of the same
name in `drag-lint-lint.json` wins over the built-in one. Guard: `tests\autotest\run_compliance_profile.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
