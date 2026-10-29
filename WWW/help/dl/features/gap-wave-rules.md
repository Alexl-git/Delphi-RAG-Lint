---
id: gap-wave-rules
title: Gap-wave lint rules
summary: About 50 new lint rules (bug patterns, dead code, data flow, platform, structure) added in the 1.37.0 gap wave
product: DL
group: linting
order: 30014
since: 1.37.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Gap-wave lint rules

About 50 new lint rules (bug patterns, dead code, data flow, platform, structure) added in the 1.37.0 gap wave.

Read this to see what the 1.37.0 lint rule additions check. Each rule is listed by drag-lint rules with its category and default, and most have an autofix.

## How to run it

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

The 1.37.0 release adds about 50 lint rules in nine groups: security `.scm` rules, shape rules, memory and overflow checks, ownership and lifetime checks, nil and bounds checks, exception and thread checks, declaration parity, project-wide DFM / virtual-method rules, and FixInsight parity.

### Running it from the CLI
```text
drag-lint rules                     (the whole catalog)
drag-lint rules --category bug-patterns
drag-lint rules --json              (id, category, severity, enabled, fixable, compliance)
drag-lint lint <file> --rule <id>   (naming an OFF rule opts it in for the run)
```
The catalog is the authority for what each rule is and whether it is on by default; opt-in rules (for example `uses-movable-to-implementation`) are OFF. Most of the new rules have an auto-fix (see Fix-it); their CWE / CERT / MISRA ids are in compliance-labels.

### What it needs
Nothing beyond the engine; project-wide rules fire only in `lint-all` with an index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
