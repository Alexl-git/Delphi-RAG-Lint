; 'if Assigned(X) then X.Free' (or FreeAndNil(X)) -- the Assigned guard is
; redundant: TObject.Free already checks Self for nil, and FreeAndNil tolerates a
; nil argument. Call X.Free / FreeAndNil(X) unconditionally. The guarded variable
; must equal the freed variable (so unrelated 'if Assigned(A) then B.Free' is safe).
((if
  condition: (exprCall
    entity: (identifier) @a
    args: (exprArgs (identifier) @v1))
  then: (statement
    (exprDot
      lhs: (identifier) @v2
      rhs: (identifier) @m))) @warn
  (#eq? @a "Assigned")
  (#eq? @m "Free")
  (#eq? @v1 @v2))
((if
  condition: (exprCall
    entity: (identifier) @a2
    args: (exprArgs (identifier) @w1))
  then: (statement
    (exprCall
      entity: (identifier) @fn
      args: (exprArgs (identifier) @w2)))) @warn
  (#eq? @a2 "Assigned")
  (#eq? @fn "FreeAndNil")
  (#eq? @w1 @w2))
