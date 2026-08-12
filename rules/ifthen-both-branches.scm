; SysUtils.IfThen evaluates ALL arguments before calling -- unlike if/then/else.
; Side-effecting expressions (function calls, DB reads) in either branch always execute.
; Replace with a real if/then/else when branches have side effects.
;
; Task 9b narrowing: does NOT fire when BOTH the then- and else-branch are
; provably inert literals (string/number/True/False/nil) -- a literal cannot
; have a side effect, so the rule's whole rationale is inapplicable there
; (YADF.Options.pas:850,879 -- both IfThen(bVal, 'true', 'false')). Deliberately
; conservative: a plain IDENTIFIER argument is still treated as non-inert and
; keeps firing, because Delphi allows a parenless call ('IfThen(B, X, Y)' could
; be reading two variables OR calling two parameterless functions) and this
; rule has no type information to tell those apart -- see
; docs/INBOX-parenless-constructor-call-is-member-access.md for the same
; ambiguity biting a different rule.
;
; The tree-sitter query language has no way to negate a node's TYPE directly
; (only #eq?/#not-eq?/#match?/#not-match?/#any-of?/#not-any-of? on captured
; TEXT are supported -- see rules/README.md). The two patterns below combine
; positional captures of the 2nd/3rd call arguments with #match?/#not-match?
; regexes tested against each capture's OWN already-isolated text (not the
; whole argument-list text, which would be a fragile hand-rolled parse) to
; express "at least one branch is not a literal":
;   Pattern A -- the then-branch (@b1) is not a literal (regardless of @b2):
;                covers "both non-literal" and "only b1 non-literal".
;   Pattern B -- @b1 IS a literal but the else-branch (@b2) is not: the
;                remaining "only b2 non-literal" case. Requiring @b1 literal
;                here makes B disjoint from A by construction, so a call with
;                BOTH branches non-literal is reported once, not twice.
(
  (exprCall
    entity: (identifier) @fn
    args: (exprArgs
      (_)
      (_) @b1
      (_) @b2)) @warn
  (#eq? @fn "IfThen")
  (#not-match? @b1 "(?i)^('.*'|-?[0-9]+(\\.[0-9]+)?|True|False|nil)$")
)

(
  (exprCall
    entity: (identifier) @fn
    args: (exprArgs
      (_)
      (_) @b1
      (_) @b2)) @warn
  (#eq? @fn "IfThen")
  (#match?     @b1 "(?i)^('.*'|-?[0-9]+(\\.[0-9]+)?|True|False|nil)$")
  (#not-match? @b2 "(?i)^('.*'|-?[0-9]+(\\.[0-9]+)?|True|False|nil)$")
)
