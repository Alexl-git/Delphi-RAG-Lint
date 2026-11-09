; Conditions that are always-constant -- dead code or logic error.
; while True is intentional (event loop) and is NOT flagged.
; An if WITH an else is its own node, ifElse (grammar v1.4.4 also moved every
; statement if..else with call / Exit branches there, which used to be
; statement(exprIf)); it was never matched, so `if True then A else B` was
; silent. Lane 149-GA grammar-shape audit.
[(if condition: (kTrue) @warn)
 (if condition: (kFalse) @warn)
 (ifElse condition: (kTrue) @warn)
 (ifElse condition: (kFalse) @warn)
 (while condition: (kFalse) @warn)]
