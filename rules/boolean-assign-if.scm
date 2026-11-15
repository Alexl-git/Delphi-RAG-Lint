; if Cond then V := True else V := False (and the negated form) for a target V other than Result.
; The Result form belongs to boolean-result-returned-directly. Equivalent to V := Cond.
; Not reported when Cond is not a boolean-typed expression is not decidable here; the branches
; assigning the literals True/False already prove V is Boolean.
((ifElse
  condition: (_) @c1
  then: (assignment lhs: (_) @t1 rhs: (kTrue))
  else: (assignment lhs: (_) @t2 rhs: (kFalse))) @warn
 (#eq? @t1 @t2)
 (#not-eq? @t1 "Result"))
((ifElse
  condition: (_) @c2
  then: (assignment lhs: (_) @t3 rhs: (kFalse))
  else: (assignment lhs: (_) @t4 rhs: (kTrue))) @warn
 (#eq? @t3 @t4)
 (#not-eq? @t3 "Result"))
