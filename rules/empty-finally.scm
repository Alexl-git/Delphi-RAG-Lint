; An empty 'finally' block does nothing -- usually a forgotten cleanup or a
; copy-paste skeleton. Detected structurally: the 'finally' keyword (kFinally)
; is immediately followed by 'end' (kEnd); the '.' anchor asserts the block is empty.
((try
  (kFinally) @warn
  .
  (kEnd)))
