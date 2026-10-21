---
id: max-blank-lines
title: Max blank lines
summary: Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
group: reflow-whitespace
order: 30
default: "1"
ini: MaxBlankLines
cli: --max-blank-lines
since: "1.0.0.0"
status: "stable"
---

# Max blank lines

Cap on consecutive blank lines anywhere in the output. The blank-
line floor options below (BlanksBeforeSection/Method/Type) win
over this cap when they ask for more blanks than this allows.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
