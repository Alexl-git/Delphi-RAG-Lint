; (X >= A) and (X <= B), in either operand order and with the bound on either
; side of the comparison: (A <= X) and (X <= B). Inclusive bounds only --
; InRange is inclusive, so strict > / < pairs are not flagged. Both X captures
; must be the same text.
; Known FP shape: X of a type InRange has no overload for (Char, enum, string) -- the FIX patterns below therefore
; require X to be declared Integer-family / Int64 / Cardinal / NativeInt / Byte / Word / ShortInt / SmallInt / Single /
; Double / Extended / Currency; any other X stays report-only (the last four patterns);
; X with side effects (InRange evaluates it once).
; Fix patterns (autofix wave A1) come FIRST: the first pattern to match a node supplies the
; finding and its fix. Same four shapes, but X must be a plain identifier / field path
; (InRange evaluates X once, the original evaluates it twice -- identical only for a
; side-effect-free X) and the bounds are captured for the InRange(X, A, B) template.
((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kGte) rhs: (_) @lo1))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_) @hi1))) @warn
  (#eq? @x1 @x2)
  (#match? @x1 "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$")
  (#declared-type? @x1 "^(System\.)?(Integer|Int64|Cardinal|NativeInt|Byte|Word|ShortInt|SmallInt|Single|Double|Extended|Currency)$"))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_) @hi2))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kGte) rhs: (_) @lo2))) @warn
  (#eq? @x1 @x2)
  (#match? @x1 "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$")
  (#declared-type? @x1 "^(System\.)?(Integer|Int64|Cardinal|NativeInt|Byte|Word|ShortInt|SmallInt|Single|Double|Extended|Currency)$"))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @lo3 operator: (kLte) rhs: (_) @x1))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_) @hi3))) @warn
  (#eq? @x1 @x2)
  (#match? @x1 "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$")
  (#declared-type? @x1 "^(System\.)?(Integer|Int64|Cardinal|NativeInt|Byte|Word|ShortInt|SmallInt|Single|Double|Extended|Currency)$"))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_) @hi4))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @lo4 operator: (kLte) rhs: (_) @x2))) @warn
  (#eq? @x1 @x2)
  (#match? @x1 "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$")
  (#declared-type? @x1 "^(System\.)?(Integer|Int64|Cardinal|NativeInt|Byte|Word|ShortInt|SmallInt|Single|Double|Extended|Currency)$"))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kGte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kGte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) operator: (kLte) rhs: (_) @x1))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) @x2 operator: (kLte) rhs: (_)))) @warn
  (#eq? @x1 @x2))

((exprBinary
  lhs: (exprParens (exprBinary lhs: (_) @x1 operator: (kLte) rhs: (_)))
  operator: (kAnd)
  rhs: (exprParens (exprBinary lhs: (_) operator: (kLte) rhs: (_) @x2))) @warn
  (#eq? @x1 @x2))
