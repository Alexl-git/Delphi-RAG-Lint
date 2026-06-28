; if Cond then Result := True else Result := False
; Equivalent to: Result := Cond. Write it directly.
((ifElse
  then: (assignment lhs: (identifier) @r1 rhs: (kTrue))
  else: (assignment lhs: (identifier) @r2 rhs: (kFalse))) @warn
 (#eq? @r1 "Result")
 (#eq? @r2 "Result"))

; if Cond then Result := False else Result := True (negated form)
; Equivalent to: Result := not Cond.
((ifElse
  then: (assignment lhs: (identifier) @r3 rhs: (kFalse))
  else: (assignment lhs: (identifier) @r4 rhs: (kTrue))) @warn
 (#eq? @r3 "Result")
 (#eq? @r4 "Result"))
