; if S = 'a' then .. else if S = 'b' then .. else if S = 'c' then ..
; Three or more links comparing the SAME plain name with string literals. Reported once, at the head
; of the chain (a link that itself follows "else" is skipped via exclude_if_preceded_by).
((ifElse
   condition: (exprBinary lhs: (_) @v1 rhs: (_) @r1) @c1
   else: (ifElse
     condition: (exprBinary lhs: (_) @v2 rhs: (_) @r2) @c2
     else: (ifElse
       condition: (exprBinary lhs: (_) @v3 rhs: (_) @r3) @c3))) @warn
  (#match? @c1 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#match? @c2 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#match? @c3 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#eq? @v1 @v2) (#eq? @v2 @v3))
((ifElse
   condition: (exprBinary lhs: (_) @v1 rhs: (_) @r1) @c1
   else: (ifElse
     condition: (exprBinary lhs: (_) @v2 rhs: (_) @r2) @c2
     else: (if
       condition: (exprBinary lhs: (_) @v3 rhs: (_) @r3) @c3))) @warn
  (#match? @c1 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#match? @c2 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#match? @c3 "^[A-Za-z_][\\w.]*\\s*=\\s*[']")
  (#eq? @v1 @v2) (#eq? @v2 @v3))
