; A generic interface (IFoo<T>) with a GUID: every instantiation IFoo<Integer>, IFoo<string> ... shares
; the one GUID, so Supports / QueryInterface cannot tell them apart and returns the wrong
; instantiation. Remove the GUID from the generic declaration (the compiler then derives distinct
; type identities) or use a non-generic base interface that carries the GUID.
((declType
  name: (genericTpl)
  (declIntf guid: (guid))) @warn)
