; {$R-} / {$Q-} (range / overflow checks off) and {$J+} (writeable typed constants) turn off
; safety nets for everything after them (CWE-190, weak). {$R+}, {$R *.dfm} are silent.
((pp) @warn
  (#match? @warn "(?i)^\\{\\$(R|Q|RANGECHECKS|OVERFLOWCHECKS)\\s*(-|\\s+OFF)\\}|^\\{\\$(J\\+|WRITEABLECONST\\s+ON)\\}"))
