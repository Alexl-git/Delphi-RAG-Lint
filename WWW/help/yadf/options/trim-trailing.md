---
id: trim-trailing
title: Trim trailing spaces
summary: Trim trailing whitespace from every output line.
group: reflow-whitespace
order: 20
default: "true"
ini: TrimTrailing
cli: --trim-trailing
since: "1.0.0.0"
status: "stable"
---

# Trim trailing spaces

Strip trailing whitespace from every emitted line. Strongly
recommended on; turning it off is mostly for diff debugging.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
