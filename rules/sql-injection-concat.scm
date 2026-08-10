; SQL built by concatenating a string literal that contains a SQL keyword with a
; variable is a classic injection vector (CWE-89). Use a parameterized query
; (ParamByName / FDQuery params) instead of '+' string building.
; Heuristic: a '+' whose left operand is a SQL-looking string literal and whose
; right operand is a bare identifier (a value spliced straight into the SQL).
;
; TIGHTENED 2026-08-10 -- AN IDENTIFIER POSITION HAS NO PARAMETERIZED FORM.
; When the literal ends with an opening identifier quote -- '"' (SQL standard),
; '[' (T-SQL) or a backtick (MySQL) -- what follows is a TABLE OR COLUMN NAME,
; and no database lets you bind one as a parameter:
;
;   QCount.SQL.Text := 'SELECT COUNT(*) FROM "' + T + '"';
;
; The rule's own advice ("use a parameterized query") is impossible there, so
; firing teaches the reader that the rule can be ignored. Both of this rule's
; hits on drag-lint's own source were exactly this shape, iterating the index's
; own table list.
;
; This does NOT weaken the real case: a value spliced into WHERE/VALUES/SET
; follows a comparison, a comma or a space -- never an identifier quote -- so
; every genuine injection shape still fires.
((exprBinary
  lhs: (literalString) @sql
  operator: (kAdd)
  rhs: (identifier)) @warn
  (#match? @sql "(?i)(select | from | where |insert |update |delete |values | set )")
  (#not-match? @sql "[\"\\[`]\\s*'$"))
