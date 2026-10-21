---
id: reflow-lines
title: Reflow long lines
summary: Reflow lines that exceed the max line length. Off = long lines are left as-is.
group: reflow-whitespace
order: 10
default: "true"
ini: ReflowLines
since: "1.0.0.0"
status: "stable"
---

# Reflow long lines

When true, drop user line breaks where structurally non-essential
and re-flow content to fill MaxLen. When false, original line
breaks are preserved (only re-indented/aligned).

## Related

- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
