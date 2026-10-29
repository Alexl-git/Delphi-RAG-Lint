# Gap-wave lint rules

The 1.37.0 release adds about 50 lint rules in nine groups: security `.scm` rules, shape rules, memory and overflow checks, ownership and lifetime checks, nil and bounds checks, exception and thread checks, declaration parity, project-wide DFM / virtual-method rules, and FixInsight parity.

## Running it from the CLI
```
drag-lint rules                     (the whole catalog)
drag-lint rules --category bug-patterns
drag-lint rules --json              (id, category, severity, enabled, fixable, compliance)
drag-lint lint <file> --rule <id>   (naming an OFF rule opts it in for the run)
```
The catalog is the authority for what each rule is and whether it is on by default; opt-in rules (for example `uses-movable-to-implementation`) are OFF. Most of the new rules have an auto-fix (see Fix-it); their CWE / CERT / MISRA ids are in compliance-labels.

## Reaching it in the IDE
The rules appear in the Lint Options dialog (drag-lint-Options) with a toggle each.

## What it needs
Nothing beyond the engine; project-wide rules fire only in `lint-all` with an index.
