; '=' compares strings case-sensitively in Delphi; SameText is usually intended
; for case-insensitive comparison.
; LIMITATION: this rule fires on ALL '=' binary expressions, not just string
; comparisons. Precise type-aware detection waits on v0.19+ type-resolution
; being plumbed into the lint engine.
((exprBinary
  operator: (_) @op) @warn
  (#eq? @op "="))
