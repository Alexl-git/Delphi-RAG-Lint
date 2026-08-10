; A const initialised to a string literal whose name looks like a secret
; (password, token, api key, ...) bakes a credential into the binary (CWE-798).
; Load it from configuration / a secret store instead. Same rule id as the
; assignment form ('hardcoded-credential').
;
; TIGHTENED 2026-08-10 -- this rule was 4-for-4 FALSE POSITIVES on drag-lint's
; own source, and a security rule that is always wrong is worse than no rule:
; people learn to skip the category, including the day it is right.
;
; 1. BARE "token" IS GONE from the name pattern. In a parser/linter/compiler
;    codebase "token" is a LEXICAL token far more often than a credential --
;    it matched AUTO_TOKEN = 'drag-lint:auto' (a doc-comment marker) and
;    RECURSION_TOKEN = '$(DCC_Define)' (an MSBuild macro). The credential sense
;    is essentially always QUALIFIED, so auth/access/refresh/api/bearer/session
;    token still fire while the lexer's own vocabulary does not.
; 2. THE VALUE MUST NOT BE A BUILD MACRO ('$(...)') or a PLACEHOLDER (a literal
;    containing '...', as in usage text like "Password=..."). Neither can be a
;    secret: one is expanded by the build, the other is documentation.
;
; What still fires is unchanged in spirit: a real secret-named const holding a
; real literal -- pinned by tests\lint\hardcoded-credential-const.pas.
((declConst
  name: (identifier) @name
  defaultValue: (defaultValue (literalString) @val)) @warn
  (#match? @name "(?i)(password|passwd|pwd|secret|apikey|api_key|credential|(auth|access|refresh|bearer|session|api)_?token)")
  (#not-match? @val "^''$")
  (#not-match? @val "\\$\\(")
  (#not-match? @val "\\.\\.\\."))
