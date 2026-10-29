; An UPDATE or DELETE statement held in ONE string literal with no WHERE touches every row of the
; table. Only a whole literal is judged: a concatenation (the exprBinary) is not a literalString, and
; SQL.Add('DELETE FROM T') followed by SQL.Add('WHERE ...') is never flagged because the text is
; assembled across calls. A deliberate full-table delete is legitimate - say so with dl:ok.
; (a) <query>.SQL.Text := '...'   and   <x>.CommandText := '...'
((assignment
  lhs: (exprDot
    lhs: (exprDot rhs: (identifier) @p)
    rhs: (identifier) @q)
  rhs: (literalString) @sql) @warn
 (#eq? @p "SQL")
 (#eq? @q "Text")
 (#match? @sql "(?is)^'\\s*(update|delete)\\b")
 (#not-match? @sql "(?i)\\bwhere\\b"))
((assignment
  lhs: (exprDot rhs: (identifier) @q)
  rhs: (literalString) @sql) @warn
 (#eq? @q "CommandText")
 (#match? @sql "(?is)^'\\s*(update|delete)\\b")
 (#not-match? @sql "(?i)\\bwhere\\b"))
; (b) <x>.ExecSQL('...') / Execute('...') / ExecuteDirect('...')
((exprCall
  entity: (exprDot rhs: (identifier) @m)
  args: (exprArgs . (literalString) @sql)) @warn
 (#any-of? @m "ExecSQL" "Execute" "ExecuteDirect")
 (#match? @sql "(?is)^'\\s*(update|delete)\\b")
 (#not-match? @sql "(?i)\\bwhere\\b"))
