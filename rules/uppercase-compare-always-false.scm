; UpperCase(X) compared against a literal that CONTAINS A LOWERCASE letter (or
; LowerCase(X) against one containing an uppercase letter). The left side can
; only ever produce a string in one case, so the two operands can NEVER be equal:
; '=' is unconditionally False and '<>' unconditionally True, whatever X holds.
;
; This is a live defect wearing a style rule's clothes -- it was previously
; reported by uppercase-compare at [warning] with a "use SameText" suggestion,
; which reads as a tidiness nit and buries the fact that the branch is dead. It
; is split out here at [error] severity so it cannot be skimmed past.
;
; The fix is NOT simply SameText: that would change behaviour from
; never-matching to sometimes-matching, which is the right outcome but is a
; semantic change and must be seen as one. Upcasing (or downcasing) the literal
; to agree with the conversion preserves the author's evident intent and makes
; the comparison capable of being true.

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq)]
  rhs: (literalString) @lit) @warn
  (#match? @fn "(?i)^(ansi)?uppercase$")
  (#match? @lit "[a-z]"))

((exprBinary
  lhs: (exprCall entity: (identifier) @fn)
  operator: [(kEq) (kNeq)]
  rhs: (literalString) @lit) @warn
  (#match? @fn "(?i)^(ansi)?lowercase$")
  (#match? @lit "[A-Z]"))
