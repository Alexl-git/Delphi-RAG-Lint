; An empty 'except' block silently swallows every exception.
; Detected structurally: inside a 'try', the 'except' keyword (kExcept) is
; immediately followed by 'end' (kEnd) -- the '.' anchor asserts no handler or
; statements sit between them, so the except section is empty.
((try
  (kExcept) @warn
  .
  (kEnd)))
