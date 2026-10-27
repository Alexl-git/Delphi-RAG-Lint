; Delphi 13: `if C then X := A else X := B;` assigns the same target on both
; branches and can be the single statement `X := if C then A else B;`.
; Both branches must be a plain assignment to textually identical targets;
; a branch that does anything else (Exit, a call, another target) is skipped.
; Coexists with ifthen-both-branches (which flags the IfThen() function call).
((ifElse
  then: (assignment lhs: (_) @l1)
  else: (assignment lhs: (_) @l2)) @warn
  (#eq? @l1 @l2))
