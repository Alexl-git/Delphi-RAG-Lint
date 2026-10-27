; A directive that turns off range or overflow checking ({$R-}, {$Q-},
; {$RANGECHECKS OFF}, {$OVERFLOWCHECKS OFF}) should say WHY. The rule fires
; unless a comment ends the text just before the directive (a // line, a
; (* *) block or a { } comment that is not itself a directive) -- see
; exclude_if_preceded_by in the sidecar. Known FP shape: a comment on the
; SAME line after the directive does not count. OFF by default.
((pp) @warn
  (#match? @warn "(?i)^\\{\\$\\s*((R|Q)-|(RANGECHECKS|OVERFLOWCHECKS)\\s+OFF)"))
