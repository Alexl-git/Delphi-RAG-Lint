; Application.Terminate in a UNIT may end the application from code no caller can see.
; The main program (root `program`) is exempt via require_ancestor "unit".
((statement
   (exprDot
     lhs: (identifier) @a
     rhs: (identifier) @m)) @warn
 (#eq? @a "Application")
 (#eq? @m "Terminate"))
