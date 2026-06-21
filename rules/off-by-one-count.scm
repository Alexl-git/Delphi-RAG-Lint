; 'for I := 0 to X.Count do' iterates one element too far: Count is the element
; count, so the last valid 0-based index is Count - 1. Same for Length(X).
; Restricted to a literal '0' start to keep false positives near zero
; (1-based 'for I := 1 to Count' is correct and is NOT flagged).
((for
  start: (assignment rhs: (literalNumber) @s)
  end: (exprDot rhs: (identifier) @p) @warn)
  (#eq? @s "0")
  (#eq? @p "Count"))
((for
  start: (assignment rhs: (literalNumber) @s2)
  end: (exprCall entity: (identifier) @f) @warn)
  (#eq? @s2 "0")
  (#eq? @f "Length"))
