; Conditions that are always-constant -- dead code or logic error.
; while True is intentional (event loop) and is NOT flagged.
[(if condition: (kTrue) @warn)
 (if condition: (kFalse) @warn)
 (while condition: (kFalse) @warn)]
