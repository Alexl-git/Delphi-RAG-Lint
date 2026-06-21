; A public data field on a class breaks encapsulation -- expose it through a
; property instead. Only 'public' sections are flagged; 'published' component
; fields on form classes are intentionally excluded to avoid noise.
((declClass
  (declSection
    (kPublic)
    (declField name: (identifier) @warn))))
