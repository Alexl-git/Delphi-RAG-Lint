; 'with A, B do' compounds the scope ambiguity of a single 'with': a bare name
; in the body may resolve to a member of A or B (or an outer scope), and which it
; binds to changes silently if either type later gains a same-named member.
; Matches a 'with' that lists two or more entities.
((with
  entity: (_)
  entity: (_)) @warn)
