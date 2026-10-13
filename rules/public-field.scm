; A public data field on a class breaks encapsulation -- expose it through a
; property instead. Only 'public' sections are flagged; 'published' component
; fields on form classes are intentionally excluded to avoid noise.
;
; RECORDS are excluded (2026-10-13, ORM3 BASICS.PAS TMousePos): a record is a
; value type whose fields ARE its surface. The grammar parses record, class and
; object bodies all as declClass, so the only way to tell them apart here is the
; node's leading keyword -- hence the #not-match? on the whole declClass text.
; Legacy 'object' types stay flagged; they are class-like.
; Pinned by tests\autotest\run_public_field_records.ps1.
((declClass
  (declSection
    (kPublic)
    (declField name: (identifier) @warn))) @cls
  (#not-match? @cls "(?i)^(packed\\s+)?record\\b"))
