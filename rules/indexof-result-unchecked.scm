; An IndexOf / Pos result is -1 / 0 when the item is absent; used straight as an index it is a
; range error (or a silent wrong element for Pos-based string indexing). Fires when the index
; argument of a subscript / Delete / Exchange is itself an IndexOf-family call. The flow form
; (`I := L.IndexOf(S); L[I]` without a test) is a LATER rule.
; Subscript on the container: L[L.IndexOf(S)] and L.Strings[..] / .Items[..] / .Objects[..].
((exprSubscript
  args: (exprArgs
    (exprCall entity: (_) @fn))) @warn
 (#match? @fn "(^|\.)(IndexOf|IndexOfName|IndexOfObject|Pos|PosEx|LastIndexOf|FindIndex)$"))
; Delete / Exchange taking the index call as an argument.
((exprCall
  entity: (exprDot rhs: (identifier) @m)
  args: (exprArgs
    (exprCall entity: (_) @fn))) @warn
 (#any-of? @m "Delete" "Exchange")
 (#match? @fn "(^|\.)(IndexOf|IndexOfName|IndexOfObject|Pos|PosEx|LastIndexOf|FindIndex)$"))
