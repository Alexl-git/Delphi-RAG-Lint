; Exception text returned to the caller of a web endpoint leaks internals (CWE-209).
; E.Message / E.StackTrace / E.ToString (E the variable of an `on E:` handler) assigned to
; a Response/Res .Content / .ContentText or passed to .Send( / .SendJSON( / .Json(.
; ShowMessage / MessageDlg / Log calls are desktop practice and stay silent.
((assignment
   lhs: (exprDot lhs: (identifier) @resp rhs: (identifier) @prop)
   rhs: (exprDot lhs: (identifier) @exc rhs: (identifier) @member)) @warn
  (#match? @resp "(?i)(response|res)$")
  (#any-of? @prop "Content" "ContentText")
  (#any-of? @member "Message" "StackTrace" "ToString")
  (#in? @warn "exceptionHandler"))
((exprCall
   entity: (exprDot rhs: (identifier) @fn)
   args: (exprArgs . (exprDot lhs: (identifier) @exc rhs: (identifier) @member))) @warn
  (#any-of? @fn "Send" "SendJSON" "Json")
  (#any-of? @member "Message" "StackTrace" "ToString")
  (#in? @warn "exceptionHandler"))
