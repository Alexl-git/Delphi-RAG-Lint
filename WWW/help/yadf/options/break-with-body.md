---
id: break-with-body
title: Break with body onto its own line
summary: Put the body of a single-line with..do on its own indented line. Off by default.
group: reflow-whitespace
order: 100
default: "false"
ini: BreakWithBody
since: "1.0.0.0"
status: "stable"
---

# Break with body onto its own line

Force the body of a single-line with..do statement onto its own indented line. Same guard rails as BreakLoopBody (begin/nested-header/comment bodies left alone). Off by default.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
