; Pos(Sub, S) and its relatives (PosEx, AnsiPos, StartsText/StartsStr/EndsText/EndsStr and the Ansi
; spellings) take the searched-for part FIRST and the text to search SECOND. A string literal in the
; second slot with a non-literal first argument is the reverse of the intent: Pos(Zeile, ';') asks
; "where is Zeile inside ';'", which is 0 unless Zeile is exactly ';'.
; Fires when the second argument is a ONE-character literal (nobody searches a variable inside one
; character), or a longer literal while the first argument is a declared string. A longer literal
; with an untyped first argument (Pos(Ch, 'aeiou') is a legitimate membership test) stays quiet.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (_) @sub . (literalString) @text)) @warn
  (#match? @fn "(?i)^(Pos|PosEx|AnsiPos|StartsText|StartsStr|EndsText|EndsStr|AnsiStartsText|AnsiStartsStr|AnsiEndsText|AnsiEndsStr)$")
  (#not-match? @sub "^[#']")
  (#match? @text "^'(''|[^'])'$"))
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (identifier) @sub . (literalString) @text)) @warn
  (#match? @fn "(?i)^(Pos|PosEx|AnsiPos|StartsText|StartsStr|EndsText|EndsStr|AnsiStartsText|AnsiStartsStr|AnsiEndsText|AnsiEndsStr)$")
  (#match? @text "^'.{2,}'$")
  (#declared-type? @sub "^(string|String|System.string|UnicodeString|AnsiString)$"))
