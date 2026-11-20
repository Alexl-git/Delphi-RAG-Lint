; String positions are 1-based. Two off-by-one shapes from 0-based habits:
;  (a) Copy(S, 0, N) and Delete(S, 0, N): the index argument is the literal 0 (before the first
;      character); Insert(Sub, S, 0) likewise.
;  (b) Pos(Sub, S) = -1 / <> -1 / > -1 ... : Pos returns 0, never -1, for "not found", so the
;      comparison has a fixed answer. (IndexOf-style calls DO return -1 and are not matched.)
; The constant-index check of the compiler-style rule constant-index-out-of-range covers S[0]; this
; rule covers the routine-call forms, with its own message.
; 1.52.1 (self-LoopZero, 21 FPs): Copy/Delete/Insert have dynamic-array overloads that are 0-based
; (`Copy(Names, 0, N)`, `Insert(Head, Units, 0)`). The string operand must be an identifier whose
; DECLARED (or oracle-known) type is a string type; a TArray / TBytes or any operand whose type
; cannot be seen (a call, a member access) stays silent.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (identifier) @s . (literalNumber) @idx)) @warn
  (#match? @fn "(?i)^(Copy|Delete)$")
  (#eq? @idx "0")
  (#declared-type? @s "^(?i)(System\.)?(string|UnicodeString|AnsiString|WideString|RawByteString|UTF8String|ShortString|string\[\d+\])$"))
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (_) . (identifier) @s . (literalNumber) @idx)) @warn
  (#match? @fn "(?i)^Insert$")
  (#eq? @idx "0")
  (#declared-type? @s "^(?i)(System\.)?(string|UnicodeString|AnsiString|WideString|RawByteString|UTF8String|ShortString|string\[\d+\])$"))
((exprBinary
   lhs: (exprCall entity: (identifier) @fn)
   operator: [(kEq) (kNeq) (kGt) (kLt) (kGte) (kLte)]
   rhs: (_) @n) @warn
  (#match? @fn "(?i)^(Pos|PosEx|AnsiPos)$")
  (#match? @n "^-\\s*1$"))
