; if K = 1 then .. else if K = 2 then .. else if K = 3 then ..
; Three or more links comparing the SAME plain name with an ordinal-looking constant (number, #code,
; hex, or an identifier that is not a string/boolean literal). Such a chain is a case statement.
; Reported once, at the head of the chain (see exclude_if_preceded_by in the sidecar).
((ifElse
   condition: (exprBinary lhs: (_) @v1) @c1
   else: (ifElse
     condition: (exprBinary lhs: (_) @v2) @c2
     else: (ifElse
       condition: (exprBinary lhs: (_) @v3) @c3))) @warn
  (#match? @c1 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#match? @c2 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#match? @c3 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#eq? @v1 @v2) (#eq? @v2 @v3))
((ifElse
   condition: (exprBinary lhs: (_) @v1) @c1
   else: (ifElse
     condition: (exprBinary lhs: (_) @v2) @c2
     else: (if
       condition: (exprBinary lhs: (_) @v3) @c3))) @warn
  (#match? @c1 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#match? @c2 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#match? @c3 "^[A-Za-z_][\\w.]*\\s*=\\s*([0-9$#]|[A-Za-z_])")
  (#eq? @v1 @v2) (#eq? @v2 @v3))
