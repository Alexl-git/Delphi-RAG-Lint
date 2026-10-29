; An interface without a GUID cannot be queried with Supports / QueryInterface / `as` (the compiler
; has no IID to ask for), and COM / RTTI-based lookup silently fails. Judged per declaration:
; a declIntf node whose `guid` field is absent. A dispinterface carries kDispInterface instead of
; kInterface and is skipped. A GENERIC interface (IFoo<T>) is skipped as well: a GUID on it is the
; separate guid-on-generic-interface finding, so the two rules never ask for opposite things.
((declType
  name: (identifier)
  (declIntf
    !guid
    (kInterface)) @warn))
