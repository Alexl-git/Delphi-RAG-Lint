; PChar(C) / PWideChar(W) / PAnsiChar(A) on a variable DECLARED Char, WideChar or AnsiChar.
; The cast turns the character code into an address (#65 -> $00000041), so the API reads from
; a wild pointer; a one-character string was meant: PChar(string(C)).
; dcc32 / dcc64 report nothing for this cast (checked with -W+ -H+, wave v151 lane MEM).
; Decides on the DECLARED type of the operand; a field, a with-member or a function result stays SILENT.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (identifier) @c .)) @warn
 (#match? @fn "^(?i)(System\.)?(PChar|PWideChar|PAnsiChar)$")
 (#declared-type? @c "^(?i)(System\.)?(Char|WideChar|AnsiChar)$"))
