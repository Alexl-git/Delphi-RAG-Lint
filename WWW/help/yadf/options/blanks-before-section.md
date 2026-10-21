---
id: blanks-before-section
title: Blanks before section
summary: Blank lines forced before each interface section. 0 = no change.
group: reflow-whitespace
order: 40
default: "0"
ini: BlanksBeforeSection
cli: --blanks-before-section
since: "1.0.0.0"
status: "stable"
---

# Blanks before section

Minimum blank lines before each `interface` / `implementation` /
`initialization` / `finalization` keyword.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
