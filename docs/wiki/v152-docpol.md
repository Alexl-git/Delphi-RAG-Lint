# Documentation policy: document all real code

The documentation rules read the symbol store, so they run under `drag-lint lint-all --db <db>` (and `lint` when the file is indexed).

## missing-doc (OFF by default; opt in with `"enabled": ["missing-doc"]`)

A public or published declaration needs a DocInsight doc comment. Since 1.52 the policy is: document ALL real code.

| Declaration | missing-doc |
|---|---|
| DFM-bound handler (`OnClick = Button1Click`) whose body has code | fires (reverses the 1.51.1 skip) |
| DFM-bound handler whose body is empty (only comments) | silent |
| getter / setter of a documented property, `override` | silent (unchanged from 1.51.1) |

## doc-placeholder (ON, hint)

A summary that is a template placeholder (`/// <summary>Summary here ...</summary>`) is not a description. It does not count as documented: the declaration gets a `doc-placeholder` finding. Replace the text with what the routine does.

## doc-malformed-summary (OFF, hint)

A summary that opens like a declaration (`/// <summary>procedure Foo(AValue: Integer);</summary>`) repeats the signature instead of describing the routine. Opt in with `"enabled": ["doc-malformed-summary"]`. Prose such as "Function that returns ..." is not matched.
