; A case branch with a label but no statement (e.g. '1: ;') does nothing -- a
; forgotten implementation, or an intentional no-op that should carry a comment.
; The '.' anchor asserts the caseLabel is the branch's last child (no body).
((caseCase
  (caseLabel) @warn
  .))
