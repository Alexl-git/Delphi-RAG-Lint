; '=' compares strings case-sensitively in Delphi; SameText is usually intended
; for case-insensitive comparison.
; HEURISTIC GUARD (v0.64.1): skip when EITHER operand is an obvious non-string
; literal -- a numeric integer/float/hex, nil, True, or False. When either
; operand matches, the expression is almost certainly not a string comparison.
; Full type-aware detection waits on the v0.65 type resolver.
; Implementation: match the @warn (full exprBinary text, e.g. "A = 42") and
; use not-match? on the whole expression text to exclude cases where the RHS or
; LHS is a standalone numeric/nil/bool token. The regex checks for a bare literal
; at the END of the expression (rhs) or at the START before '=' (lhs).
; "Bare" means surrounded only by spaces and/or the = sign, not inside a call.
((exprBinary
  operator: (_) @op) @warn
  (#eq? @op "=")
  (#not-match? @warn "= *(0|[1-9][0-9]*|[0-9]+[.][0-9]+|[$][0-9A-Fa-f]+|nil|Nil|NIL|true|True|TRUE|false|False|FALSE|-[0-9]+) *$")
  (#not-match? @warn "^ *(0|[1-9][0-9]*|[0-9]+[.][0-9]+|[$][0-9A-Fa-f]+|nil|Nil|NIL|true|True|TRUE|false|False|FALSE|-[0-9]+) *= ")
  ; v0.65.x: also skip when an operand is a quoted string/char literal with NO
  ; alphabetic characters (e.g. '+', '-', '0', '-.', #13). Case-insensitivity is
  ; irrelevant for such constants, so suggesting SameText is noise.
  (#not-match? @warn "= *('[^a-zA-Z']*'|#[0-9]+|#[$][0-9A-Fa-f]+) *$")
  (#not-match? @warn "^ *('[^a-zA-Z']*'|#[0-9]+|#[$][0-9A-Fa-f]+) *= ")
  ; v0.67: skip non-string TField / numeric accessors (.AsInteger / .AsLargeInt /
  ; .AsFloat / .AsBoolean ...) and enum-valued .State -- these are integer/enum
  ; comparisons, not case-sensitivity concerns. Full type-aware detection runs on
  ; the store path (check-ast --db / lint-all --db); this guards the no-store path.
  (#not-match? @warn "(?i)[.]As(Integer|Int64|LargeInt|Float|Boolean|Currency|DateTime|Extended|Single|Word|SmallInt|Byte|Cardinal|BCD|Bytes|Variant)")
  (#not-match? @warn "(?i)[.]State([^A-Za-z]|$)"))
