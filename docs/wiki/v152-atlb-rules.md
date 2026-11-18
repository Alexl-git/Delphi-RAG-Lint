# member-could-be-private and the refused component-create rule (lane ATLB, 1.52)

## member-could-be-private (hint, project-wide, default OFF)

A `public` member of a class that no file except the one declaring it references could be
`private`: Delphi's `private` is visible to the whole unit, so narrowing it breaks no caller the
index can see. The rule runs in `lint-all` only (it needs every file's references) and is OFF
by default until the false-positive measurement of the FPM lane; run it with
`drag-lint lint-all --db <db> --rule member-could-be-private`.

It stays silent whenever it cannot prove the narrowing safe:

| Case | Why silent |
|---|---|
| published member, or the unlabelled leading section of a class | streamed by the form loader / RTTI |
| virtual, dynamic, override, abstract, message, reintroduce, external routines | called through dispatch |
| constructors, destructors, members of a helper | called through the type name / not owned |
| the name is also declared by an interface of the class, or an interface ancestor does not resolve | interface implementation |
| the member carries an attribute (`[Attr]`) | RTTI may read it |
| no reference at all | dead code is the business of `unused-public-symbol` |
| the name is referenced from a second file (another unit, a form file) | used elsewhere |
| the unit lists more than one project in its `dl:shared` header | a sibling project's index is not open in the run |

The check is NAME keyed, like `unused-public-symbol`'s own-unit tier: a same-named reference in
another file keeps every member of that name silent. Known limit: a unit used by a second
project WITHOUT a `dl:shared` header is judged on this project's index alone.

## component-create-without-override: refused, covered by hides-ancestor-virtual

`constructor Create(AOwner: TComponent);` without `override` in a descendant is exactly dcc
W1010, already reported by `hides-ancestor-virtual`. No new id. The fixture
`tests\lint\hides-ancestor-virtual-component-ctor.pas` and `tests\autotest\run_v152_ATLB.ps1`
prove it fires on that shape (positive control: the rule disabled).

## debug-display-placeholder: not implemented

It cannot be checked with today's index (no attribute facts); see
`docs\INBOX-debug-display-placeholder-needs-index-fact.md`.
