; inherited-bare -- a BARE `inherited;` with no method name.
;
; v(ADP3 T4f, register K32). This query was, in full, `((inherited) @warn)`,
; which matches EVERY `inherited` node -- so `Result := inherited Fetch(pIndex);`
; raised the same finding as a genuinely bare `inherited;`, while the rule's own
; message (inherited-bare.json) and rules/README.md both said "bare".
;
; The grammar puts the method name INSIDE the node, so the captured TEXT is the
; discriminator: 'inherited' for the bare form, 'inherited Fetch(pIndex)' for the
; qualified one. Measured on a two-method fixture before the change (fires on
; both) and after (fires on the bare one only), plus a control predicate
; `(#match? @warn "F")` that fires on the QUALIFIED one ALONE -- which is what
; proves the node text really carries the name, rather than the rule having
; stopped firing for some other reason.
;
; The trailing `;?` is tolerated because whether the terminator falls inside the
; node is a grammar detail this rule should not depend on.
((inherited) @warn
  (#match? @warn "(?i)^inherited\s*;?\s*$"))
