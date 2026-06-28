; SysUtils.IfThen evaluates ALL arguments before calling -- unlike if/then/else.
; Side-effecting expressions (function calls, DB reads) in either branch always execute.
; Replace with a real if/then/else when branches have side effects.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "IfThen"))
