; `X.Create(..)` as a bare statement on a declared local or parameter calls the constructor as an
; ordinary method on the existing (usually still nil, or already live) instance: nothing is
; allocated, the instance's state is re-initialised or the call hits nil. The author meant
; `X := TFoo.Create(..)`. Receiver decided on its DECLARED type, so a type name (TFoo.Create)
; and a field receiver stay SILENT (known gap: a field is not seen by declared-type?).
; `inherited Create` is its own node kind and never matches.
; A metaclass receiver (`K: TComponentClass`; `K.Create`) does allocate: #not-metaclass-receiver?
; stays silent on it (1.45; before, every metaclass local and, with O2, every metaclass field fired).
((statement
  (exprCall
    entity: (exprDot
      lhs: (identifier) @recv
      rhs: (identifier) @m)) @warn)
 (#eq? @m "Create")
 (#declared-type? @recv ".+")
 (#not-metaclass-receiver? @recv))
; Argument-less form: `X.Create;` parses as a bare member access, not a call.
((statement
  (exprDot
    lhs: (identifier) @recv
    rhs: (identifier) @m) @warn)
 (#eq? @m "Create")
 (#declared-type? @recv ".+")
 (#not-metaclass-receiver? @recv))
