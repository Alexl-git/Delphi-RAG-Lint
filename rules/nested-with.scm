; Nested with statements multiply the scope-ambiguity problem
; exponentially. Prefer explicit qualified access.
((with
  body: (with) @inner) @outer)
