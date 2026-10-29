; `X.Create(..)` as a bare statement on a declared local or parameter calls the constructor as an
; ordinary method on the existing (usually still nil, or already live) instance: nothing is
; allocated, the instance's state is re-initialised or the call hits nil. The author meant
; `X := TFoo.Create(..)`. Receiver decided on its DECLARED type, so a type name (TFoo.Create)
; and a field receiver stay SILENT (known gap: a field is not seen by declared-type?).
; `inherited Create` is its own node kind and never matches.
((statement
  (exprCall
    entity: (exprDot
      lhs: (identifier) @recv
      rhs: (identifier) @m)) @warn)
 (#eq? @m "Create")
 (#declared-type? @recv ".+"))
; Argument-less form: `X.Create;` parses as a bare member access, not a call.
((statement
  (exprDot
    lhs: (identifier) @recv
    rhs: (identifier) @m) @warn)
 (#eq? @m "Create")
 (#declared-type? @recv ".+"))
