; Comments containing TODO/FIXME/HACK/XXX/BUG markers flag work items
; that should be tracked in an issue tracker, not left in source.
;
; THE WORD BOUNDARIES ARE load-bearing. Without them "BUG" matches inside
; DEBUG -- so `{$IFDEF DEBUG}` commentary, `// DEBUG_MODE ...`, and every
; identifier of the form BUG_SOMETHING (test-case names are the common case)
; were reported as untracked work items. Measured on YADF 2026-08-13.
; `_` is a word character, which is what makes \b do the right thing for both
; DEBUG_MODE (no boundary before BUG) and BUG_DROPPED_INCLUDE (none after).
;
; The trailing \b also drops the plural "TODOs", which in practice only ever
; appears in prose ABOUT markers rather than in a marker itself -- YADF, whose
; job is emitting `// TODO -oYADF` into other people's code, is full of it.
((comment) @warn
  (#match? @warn "\\b(TODO|FIXME|HACK|XXX|BUG)\\b"))
