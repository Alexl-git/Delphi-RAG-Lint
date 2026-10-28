; Pos(Sub, S) compared with 0 (> 0, <> 0, = 0) is a Contains test; Pos(..) = 1
; is a StartsStr/StartsWith test. Only the plain Pos name is matched.
; Known FP shape: Pos with a 3rd (offset) argument, Pos on non-strings.
; Fix patterns (autofix wave A1) come FIRST: the first pattern to match a node supplies the
; finding and its fix. Pos(Sub, S) -> S.Contains(Sub), only when S is a plain identifier
; declared string / UnicodeString (no helper on ShortString / PChar / AnsiString). The
; = 1 -> StartsWith variant is NOT shipped: see the A1 report (StartsWith(Value) was not
; proven case-sensitive on Delphi 13 here), it stays a report-only finding.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (_) @sub . (identifier) @s .))
  operator: (kGt)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#declared-type? @s "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (_) @sub2 . (identifier) @s2 .))
  operator: (kNeq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#declared-type? @s2 "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (_) @sub3 . (identifier) @s3 .))
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#declared-type? @s3 "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kGt) (kNeq) (kEq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "1"))
