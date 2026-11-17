; Items/Lines/Nodes.Add inside a loop repaints a visual list on every call.
; v152 NOISE2 (YADF NOTE-8): @ctl is the control expression (Cmb, Self.Cmb, Form.Lst), so the
; sidecar can drop a control constructed earlier in the same routine (Cmb := TComboBox.Create(..)):
; it is not on screen yet and an Add repaints nothing.
((exprCall
   entity: (exprDot
     lhs: (exprDot lhs: (_) @ctl rhs: (identifier) @list)
     rhs: (identifier) @verb)) @warn
  (#match? @list "^(?i)(Items|Lines|Nodes|Strings)$")
  (#match? @verb "^(?i)(Add|AddObject|Append|Insert)$"))