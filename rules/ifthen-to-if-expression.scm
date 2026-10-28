; Delphi 13: `if C then X := A else X := B;` assigns the same target on both
; branches and can be the single statement `X := if C then A else B;`.
; Both branches must be a plain assignment to textually identical targets;
; a branch that does anything else (Exit, a call, another target) is skipped.
; Coexists with ifthen-both-branches (which flags the IfThen() function call).
; Second arm: X := IfThen(C, A, B) with BOTH branches inert literals is the same thing in
; call form. IfThen evaluates both arguments, an if-expression only one, so the swap is only
; equivalent without side effects: a non-literal branch is left to ifthen-both-branches
; (disjoint by construction: that rule skips the both-literal call).
((ifElse
  then: (assignment lhs: (_) @l1)
  else: (assignment lhs: (_) @l2)) @warn
  (#eq? @l1 @l2))

((assignment
  rhs: (exprCall
    entity: (identifier) @fn
    args: (exprArgs
      (_)
      (_) @b1
      (_) @b2))) @warn
  (#eq? @fn "IfThen")
  (#match? @b1 "(?i)^('.*'|-?[0-9]+(\\.[0-9]+)?|True|False|nil)$")
  (#match? @b2 "(?i)^('.*'|-?[0-9]+(\\.[0-9]+)?|True|False|nil)$"))
