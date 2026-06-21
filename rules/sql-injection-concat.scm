; SQL built by concatenating a string literal that contains a SQL keyword with a
; variable is a classic injection vector (CWE-89). Use a parameterized query
; (ParamByName / FDQuery params) instead of '+' string building.
; Heuristic: a '+' whose left operand is a SQL-looking string literal and whose
; right operand is a bare identifier (a value spliced straight into the SQL).
((exprBinary
  lhs: (literalString) @sql
  operator: (kAdd)
  rhs: (identifier)) @warn
  (#match? @sql "(?i)(select | from | where |insert |update |delete |values | set )"))
