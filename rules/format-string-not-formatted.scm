; Format/WideFormat whose first argument is a plain string literal containing
; no '%' at all: nothing is ever formatted, the call is dead weight and any
; argument array is silently ignored (the runtime does not complain). Usually a
; leftover from an edited message or a forgotten specifier. Plain string
; literal only: a concatenation or a variable is not inspected (known FP
; shape, skipped on purpose). An escaped '%%' contains '%', so it is NOT
; reported -- it is still a format string.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (literalString) @fmt)) @warn
  (#match? @fn "(?i)^(Wide)?Format$")
  (#not-match? @fmt "%"))
