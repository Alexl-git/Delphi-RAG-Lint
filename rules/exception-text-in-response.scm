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
; O2 (1.45): the receiver is a server response by its DECLARED or indexed TYPE, whatever it is
; called (Indy AResponseInfo is matched by name already; FReply / Out are not). #declared-type?
; reads a parameter or local from the source and a field or global from the index; without the
; index the field case stays silent as before. The name test is repeated negated so a receiver
; both named and typed as a response is reported once.
((assignment
   lhs: (exprDot lhs: (identifier) @resp rhs: (identifier) @prop)
   rhs: (exprDot lhs: (identifier) @exc rhs: (identifier) @member)) @warn
  (#not-match? @resp "(?i)(response|res)$")
  (#declared-type? @resp "^(TIdHTTPResponseInfo|TWebResponse|TCustomWebResponse|THorseResponse|THTTPResponse)$")
  (#any-of? @prop "Content" "ContentText")
  (#any-of? @member "Message" "StackTrace" "ToString")
  (#in? @warn "exceptionHandler"))
((exprCall
   entity: (exprDot rhs: (identifier) @fn)
   args: (exprArgs . (exprDot lhs: (identifier) @exc rhs: (identifier) @member))) @warn
  (#any-of? @fn "Send" "SendJSON" "Json")
  (#any-of? @member "Message" "StackTrace" "ToString")
  (#in? @warn "exceptionHandler"))
