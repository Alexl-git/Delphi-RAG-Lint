; XML external entity processing switched on (CWE-611): MSXML resolveExternals := True,
; ProhibitDTD := False, or setProperty('ProhibitDTD', False). The safe values are silent.
; The sidecar "fix" flips each literal (risky: enabling DTD/externals may be relied on).
((assignment
   lhs: (exprDot) @rext
   rhs: (kTrue) @val) @warn
  (#match? @rext "(?i)\.resolveExternals$"))
((assignment
   lhs: (exprDot) @dtd
   rhs: (kFalse) @val) @warn
  (#match? @dtd "(?i)\.ProhibitDTD$"))
((exprCall
   entity: (exprDot lhs: (_) @objp rhs: (identifier) @fn)
   args: (exprArgs . (literalString) @name . (kFalse) .)) @warn
  (#eq? @fn "setProperty")
  (#eq? @name "'ProhibitDTD'"))