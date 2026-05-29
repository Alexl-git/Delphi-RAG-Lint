; 'with' makes symbol scope ambiguous: any name lookup inside the body
; may silently resolve to a field of the with-target rather than the
; outer scope. Prefer explicit qualified access.
((with) @warn)
