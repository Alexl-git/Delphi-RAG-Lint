; Obsolete RTL routines -- prefer modern encoding/conversion equivalents.
; OemToAnsi/AnsiToOem: use TEncoding. StrPas: use string() cast directly.
((exprCall entity: (identifier) @fn) @warn
 (#any-of? @fn "OemToAnsi" "AnsiToOem" "StrPas"))
