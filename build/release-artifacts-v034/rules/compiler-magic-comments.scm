; Comments containing TODO/FIXME/HACK/XXX markers flag work items
; that should be tracked in an issue tracker, not left in source.
((comment) @warn
  (#match? @warn "TODO|FIXME|HACK|XXX"))
