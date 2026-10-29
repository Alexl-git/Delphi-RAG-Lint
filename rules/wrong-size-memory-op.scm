; A byte count handed to a raw memory routine that does not match the buffer it describes.
; (a) FillChar(P^, SizeOf(P), ..): the pointer VARIABLE is measured, not what it points to. @warn is the
;     SizeOf call, so the autofix rewrites just SizeOf(P) to SizeOf(P^).
; (b) Move / CopyMemory / Stream.Write(S[..], Length(S)) over a string: Length counts characters, not
;     bytes -- the character-size factor is missing. A product (Length(S) * 2) is an exprBinary, so it
;     never matches. @warn is the Length call (autofix: Length(S) * SizeOf(Char)).
; (c) FillChar(V, SizeOf(V), ..) over a managed/reference variable (string, dynamic array, interface)
;     wipes the pointer without releasing it. No autofix.
; Decides on the DECLARED type of the buffer; a field, a unit global or an undeclared operand stays SILENT.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     . (exprUnary operand: (identifier) @p operator: (kHat))
     . (exprCall entity: (identifier) @sz args: (exprArgs (identifier) @p2) @szargs) @warn))
 (#any-of? @fn "FillChar" "ZeroMemory")
 (#eq? @sz "SizeOf")
 (#eq? @p @p2))

((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     . (exprSubscript entity: (identifier) @s)
     . (_)
     . (exprCall entity: (identifier) @len args: (exprArgs (identifier) @s2)) @warn))
 (#eq? @fn "Move")
 (#eq? @len "Length")
 (#eq? @s @s2)
 (#declared-type? @s "^(System\\.)?([Ss]tring|UnicodeString|WideString)$"))

((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     . (_)
     . (exprSubscript entity: (identifier) @s)
     . (exprCall entity: (identifier) @len args: (exprArgs (identifier) @s2)) @warn))
 (#any-of? @fn "CopyMemory" "MoveMemory")
 (#eq? @len "Length")
 (#eq? @s @s2)
 (#declared-type? @s "^(System\\.)?([Ss]tring|UnicodeString|WideString)$"))

((exprCall
   entity: (exprDot rhs: (identifier) @m)
   args: (exprArgs
     . (exprSubscript entity: (identifier) @s)
     . (exprCall entity: (identifier) @len args: (exprArgs (identifier) @s2)) @warn))
 (#any-of? @m "Write" "WriteBuffer")
 (#eq? @len "Length")
 (#eq? @s @s2)
 (#declared-type? @s "^(System\\.)?([Ss]tring|UnicodeString|WideString)$"))

((exprCall
   entity: (identifier) @fn
   args: (exprArgs
     . (identifier) @v
     . (exprCall entity: (identifier) @sz args: (exprArgs (identifier) @v2)) @warn))
 (#any-of? @fn "FillChar" "ZeroMemory")
 (#eq? @sz "SizeOf")
 (#eq? @v @v2)
 (#declared-type? @v "^(System\\.)?([Ss]tring|[A-Za-z]*String|TBytes|TArray<.*>|array of .*|(?-i:I[A-Z]\\w*))$"))