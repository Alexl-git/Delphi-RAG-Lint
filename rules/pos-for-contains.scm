; Pos(Sub, S) compared with 0 (> 0, <> 0, = 0) is a Contains test; Pos(..) = 1
; is a StartsStr/StartsWith test. Only the plain Pos name is matched.
; A 3-argument Pos (offset, PosEx semantics) is NOT a Contains test: every pattern below pins the argument count with an optional trailing capture that must be empty.
; Known FP shape: Pos on non-strings.
; Fix patterns (autofix wave A1) come FIRST: the first pattern to match a node supplies the
; finding and its fix. Pos(Sub, S) -> S.Contains(Sub) (= 0 -> not S.Contains(Sub)), only when
;   * Sub is a NON-EMPTY string literal (v1523 FIXER-2): Pos('', S) = 0 but S.Contains('') is
;     True, so a variable or empty needle is NOT the same test and stays report-only. Before
;     1.52.3 the fixer rewrote exactly those and declined the literal ones below;
;   * S is a string the helper exists for (no helper on ShortString / PChar / AnsiString):
;     a plain identifier declared string / UnicodeString (s), a member access whose member
;     is declared so -- through the index's type oracle when --db is given (m), or a call of
;     the SysUtils string routines LowerCase / UpperCase / Trim / TrimLeft / TrimRight (c).
; The = 1 -> StartsWith variant is NOT shipped: see the A1 report (StartsWith(Value) was not
; proven case-sensitive on Delphi 13 here), it stays a report-only finding.
((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @sub . (identifier) @s (_)? @x1))
  operator: [(kGt) (kNeq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @x1 "")
  (#not-match? @sub "^''$")
  (#declared-type? @s "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @sub3 . (identifier) @s3 (_)? @x3))
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @x3 "")
  (#not-match? @sub3 "^''$")
  (#declared-type? @s3 "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @subm . (exprDot rhs: (identifier) @mm) @m (_)? @xm))
  operator: [(kGt) (kNeq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @xm "")
  (#not-match? @subm "^''$")
  (#declared-type? @mm "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @subm3 . (exprDot rhs: (identifier) @mm3) @m3 (_)? @xm3))
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @xm3 "")
  (#not-match? @subm3 "^''$")
  (#declared-type? @mm3 "^(string|String|System.string|UnicodeString)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @subc . (exprCall entity: (identifier) @fc args: (exprArgs . (_) .)) @c (_)? @xc))
  operator: [(kGt) (kNeq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @xc "")
  (#not-match? @subc "^''$")
  (#match? @fc "(?i)^(LowerCase|UpperCase|Trim|TrimLeft|TrimRight)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (literalString) @subc3 . (exprCall entity: (identifier) @fc3 args: (exprArgs . (_) .)) @c3 (_)? @xc3))
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @xc3 "")
  (#not-match? @subc3 "^''$")
  (#match? @fc3 "(?i)^(LowerCase|UpperCase|Trim|TrimLeft|TrimRight)$"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (_) . (_) (_)? @x))
  operator: [(kGt) (kNeq) (kEq)]
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "0")
  (#eq? @x ""))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn
    args: (exprArgs . (_) . (_) (_)? @x))
  operator: (kEq)
  rhs: (literalNumber) @n) @warn
  (#match? @fn "(?i)^Pos$")
  (#eq? @n "1")
  (#eq? @x ""))
