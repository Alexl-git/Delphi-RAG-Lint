# Compliance labels

Every lint rule can carry the CWE, CERT and MISRA ids it answers. The labels are metadata for audit tooling; they never change a rule's severity, its default state or an exit code.

## Where they live

One file, `rules\compliance.json`, shipped beside the other rule sidecars: an object keyed by rule id, one line per rule, sorted, every rule present (an unlabelled rule is `{}`). `weak` lists the ids whose fit is only plausible.

## Using them

| You want | Command |
|---|---|
| the ids of each rule | `drag-lint rules` (suffix `[CWE-476 EXP34-C]`) or `rules --json` (`compliance` object: `cwe`, `cert`, `misra`, `weak`, always present) |
| only rules under one standard | `drag-lint rules --standard cwe` (or `cert` / `misra`) |
| the ids on findings (machine) | `lint --json` / `lint-all --json`: a `compliance` object on each labelled finding, absent otherwise |
| the ids on findings (text) | `lint --labels` / `lint-all --labels` appends ` [CWE-798]` to the message; default text is unchanged |

## Rules of the file

* Id formats: `CWE-<n>`; CERT `ABC12-C|CPP|J`; MISRA `MISRA-C-2012-R<n>.<n>`, `D<n>.<n>`, `MISRA-CPP-2008-<n>-<n>-<n>`. A malformed id makes `drag-lint rules` fail (exit 2); a missing file gives empty labels and one stderr note.
* Guard: `tests\autotest\run_compliance_labels_guard.ps1` (completeness, formats, positive and negative controls, `lint --json`).
* Not an extractor change; `DRAGLINT_EXTRACTOR_VERSION` is untouched.
