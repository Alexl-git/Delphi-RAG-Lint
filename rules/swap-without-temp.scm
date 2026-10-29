; `A := B; B := A;` -- a swap attempted without a temporary. After the first
; statement A already holds B's value, so the second assigns B to itself and
; the old A is lost. Reported on the second statement. Needs two ADJACENT
; sibling statements (the anchor between the patterns); an expression on the
; right-hand side (`B := A + 1`, intentional copy-then-derive) is not matched.
(
  (assignment lhs: (_) @a rhs: (_) @b)
  .
  (assignment lhs: (_) @c rhs: (_) @d) @warn
  (#eq? @a @d)
  (#eq? @b @c)
)
