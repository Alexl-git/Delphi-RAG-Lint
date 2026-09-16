; A hardcoded IPv4 address ties the code to one host/network. Read it from
; configuration.
;
; A DOTTED-QUAD VERSION IS NOT AN ADDRESS (2026-09-16). Four dot-separated
; integers in 0..255 is the shape of an IPv4 literal AND the shape of a great
; many version constants, and the VALUE cannot tell them apart -- but the
; declaration's NAME can. `YADF_MIN_VERSION = '1.0.6.6'` was reported as an
; address, and a rule that is wrong in a whole CATEGORY (every version const a
; codebase has) teaches people to skim it, which is the trust the lint-clean
; standard exists to protect. So: a literal inside a declConst whose name
; carries VERSION / VER (as a token or a suffix) is excluded; a const with a
; host-like name (SERVER_IP) still fires, and so does every non-const site.
; Pinned by tests\lint\hardcoded-ip-address.pas lines 7/8 (silent) vs 10 (fires).
;
; #not-in? is drag-lint's own predicate (DRagLint.Lint.QueryRules): "no
; ancestor of this node type whose name: field matches the regex". It walks
; parents, so it needs no knowledge of the syntactic context the literal sits
; in. Put it last: it runs only for matches that passed the cheaper #match?.
((literalString) @warn
  (#match? @warn "^'([0-9]{1,3}\\.){3}[0-9]{1,3}")
  (#not-in? @warn "declConst" "(?i)(version|(^|_)ver(_|$)|ver$)"))