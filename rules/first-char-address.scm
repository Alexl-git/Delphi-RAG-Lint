; @S[1] / @S[Low(S)] on a variable DECLARED as a long string (string, UnicodeString, AnsiString,
; WideString, RawByteString, UTF8String). For an empty string the index is out of range: a range
; check error under {$R+}, nil or garbage without it. PChar(S) / Pointer(S) are the safe forms.
; A ShortString (fixed storage) and an untyped / undeclared operand stay SILENT. No autofix: Pointer(S)
; returns nil for '' where @S[1] returned a (garbage) address, so callers may behave differently.
((exprUnary
   operator: (kAt)
   operand: (exprSubscript
     entity: (identifier) @s
     args: (exprArgs . (literalNumber) @one .))) @warn
 (#eq? @one "1")
 (#declared-type? @s "^(?i)(System\.)?(string|UnicodeString|AnsiString|WideString|RawByteString|UTF8String)$"))

((exprUnary
   operator: (kAt)
   operand: (exprSubscript
     entity: (identifier) @s
     args: (exprArgs . (exprCall entity: (identifier) @low args: (exprArgs . (identifier) @s2 .)) .))) @warn
 (#match? @low "^(?i)Low$")
 (#eq? @s @s2)
 (#declared-type? @s "^(?i)(System\.)?(string|UnicodeString|AnsiString|WideString|RawByteString|UTF8String)$"))
