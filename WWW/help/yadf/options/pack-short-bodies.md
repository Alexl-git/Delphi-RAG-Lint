---
id: pack-short-bodies
title: Pack short bodies & case arms
summary: Pull a short loop/if body or case arm onto one line when reflowing. Off by default.
group: reflow-whitespace
order: 70
default: "false"
ini: PackShortBodies
since: "1.0.0.0"
status: "stable"
---

# Pack short bodies & case arms

When reflowing, pull a SHORT body onto one line: a loop/if header keeps its simple statement ("for I := 0 to N do Inc(X);", "if X then DoIt;") and a case arm collapses onto its label ("0: DoZero;"). Off by default -- every body/arm stays on its own line. A nested control header (if/case/begin...) is never half-merged onto a do/then/label either way.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
