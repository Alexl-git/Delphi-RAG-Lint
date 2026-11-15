; for-loop bounds that run one step past the valid index range (companion of off-by-one-count,
; which covers 'for I := 0 to X.Count' / 'to Length(X)'):
;   * 'to High(X) + 1' / 'to X.Count + 1' / 'to Length(X) + 1'
;   * 'for I := Low(X) to Length(X)' and 'for I := Low(X) to X.Count'
;   * 'for I := X.Count downto 0' / 'for I := Length(X) downto 0' (counting down FROM the count)
((for
   start: (assignment rhs: (_) @s)
   end: (exprBinary) @warn)
  (#match? @warn "(?i)^(High\\s*\\(\\s*[\\w.]+\\s*\\)|Length\\s*\\(\\s*[\\w.]+\\s*\\)|[A-Za-z_][\\w.]*\\.Count)\\s*\\+\\s*[1-9]$")
  (#match? @s "^0$|(?i)^Low\\s*\\("))
((for
   start: (assignment rhs: (exprCall entity: (identifier) @lo))
   end: (exprCall entity: (identifier) @f) @warn)
  (#match? @lo "(?i)^Low$")
  (#match? @f "(?i)^Length$"))
((for
   start: (assignment rhs: (exprDot rhs: (identifier) @p1))
   (kDownto)
   end: (literalNumber) @e) @warn
  (#eq? @p1 "Count")
  (#match? @e "^0$"))
((for
   start: (assignment rhs: (exprCall entity: (identifier) @f2 args: (exprArgs (_))))
   (kDownto)
   end: (literalNumber) @e2) @warn
  (#match? @f2 "(?i)^Length$")
  (#match? @e2 "^0$"))
