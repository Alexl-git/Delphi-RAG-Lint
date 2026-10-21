---
id: uses-comma-last
title: Comma-last uses layout
summary: Broken uses clause style: off = comma-first (diff-friendly), on = comma-last.
group: uses-clauses
order: 20
default: "false"
ini: UsesCommaLast
since: "1.0.0.0"
status: "stable"
---

# Comma-last uses layout

Style of the BROKEN (multi-line) uses clause. Only affects the
broken form; the inline single-line form is unchanged.
  false (default) -- comma-FIRST     true -- comma-LAST
    uses                               uses
      System.SysUtils                    System.SysUtils,
    , System.Classes                     System.Classes;
    ;
Comma-first (default) keeps diffs clean when units are added or
removed (each line is a complete row including its comma).

## Related

- [Break uses one-per-line](uses-always-break.md) - Always break uses clauses one unit per line.
