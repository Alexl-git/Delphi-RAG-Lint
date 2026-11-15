; SELECT * (or SELECT alias.*) in an SQL string literal: the column list is whatever the table
; has today, so a later ALTER TABLE changes the result set, the memory per row and every
; field index that was counted by position. Name the columns.
; Judged are whole literals only, in the places where SQL text is set or passed:
;   <q>.SQL.Text := '...'          <x>.CommandText := '...'
;   <q>.SQL.Add('...') / Append    <x>.Open / ExecSQL / Execute / ExecuteDirect('...')
; A concatenation (the exprBinary) is not a literalString and is not judged; COUNT(*) and
; a multiplication (price * qty) are not a star column: the star must be a whole select-list
; item, followed by a comma, FROM or the end of the literal.
; (a) <query>.SQL.Text := '...'   and   <x>.CommandText := '...'
((assignment
  lhs: (exprDot
    lhs: (exprDot rhs: (identifier) @p)
    rhs: (identifier) @q)
  rhs: (literalString) @sql) @warn
 (#eq? @p "SQL")
 (#eq? @q "Text")
 (#match? @sql "(?is)\\bselect\\b(?:[^']*?[\\s,])?(?:\\w+\\.)?\\*\\s*(?:,|from\\b|'$)"))
((assignment
  lhs: (exprDot rhs: (identifier) @q)
  rhs: (literalString) @sql) @warn
 (#eq? @q "CommandText")
 (#match? @sql "(?is)\\bselect\\b(?:[^']*?[\\s,])?(?:\\w+\\.)?\\*\\s*(?:,|from\\b|'$)"))
; (b) <query>.SQL.Add('...') / Append('...')
((exprCall
  entity: (exprDot
    lhs: (exprDot rhs: (identifier) @p)
    rhs: (identifier) @m)
  args: (exprArgs . (literalString) @sql)) @warn
 (#eq? @p "SQL")
 (#any-of? @m "Add" "Append")
 (#match? @sql "(?is)\\bselect\\b(?:[^']*?[\\s,])?(?:\\w+\\.)?\\*\\s*(?:,|from\\b|'$)"))
; (c) <x>.Open / ExecSQL / Execute / ExecuteDirect('...')
((exprCall
  entity: (exprDot rhs: (identifier) @m)
  args: (exprArgs . (literalString) @sql)) @warn
 (#any-of? @m "Open" "ExecSQL" "Execute" "ExecuteDirect" "OpenSQL")
 (#match? @sql "(?is)\\bselect\\b(?:[^']*?[\\s,])?(?:\\w+\\.)?\\*\\s*(?:,|from\\b|'$)"))
