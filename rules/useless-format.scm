; Format('%s', [X]) with exactly one bracketed element: the call only converts
; X to a string. The element text is restricted to a bracket pair without a
; top-level comma, so Format('%s', [A, B]) (arg-count mismatch) never matches.
; Brackets are written as character classes -- escaped \[ \] inside a class do
; not survive the engine's predicate regex handling.
; Known FP shape: X is a Variant/number where Format performs the conversion.
((exprCall
  entity: (identifier) @fn
  args: (exprArgs
    . (literalString) @fmt
    . (_) @arr)) @warn
  (#match? @fn "(?i)^Format$")
  (#eq? @fmt "'%s'")
  (#match? @arr "^[[][^],[]*[]]$"))
