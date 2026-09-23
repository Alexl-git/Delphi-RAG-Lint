# Effect Summary Legend

The purity analysis writes a short token string for every routine it judges --
`symbol_facts.effect_summary` in the index. It is what `hover --format json`
returns as `effect_summary`, what [`ask effects`](ask-effects) draws token by
token, and what the lint rules `discarded-effect-free-result`,
`query-name-with-effect` and `assert-with-side-effect` read. This page is the
key to it.

## The tokens

| Token | Meaning |
|---|---|
| `g` | Touches state beyond the routine: writes a global or unit-level variable, uses an external resource (file system, registry, network, a transaction verb), or runs SQL -- a SQL READ counts too. |
| `h` | Frees heap storage it did not allocate -- `Dispose` / `FreeMem`, directly or through a callee that does. |
| `s` | Writes fields of its own instance (`Self`), directly or through a method of its own that does. |
| `p<k>` | Writes through parameter `k`: a `var`/`out` parameter, or a field of an object passed in. `k` is **0-based**, counted over the routine's declared parameters (`p0` is the first). One token per parameter. |
| `?` | Something could not be bound or classified -- an unresolved callee, a receiver the analysis could not place, a capped parameter list, or a stored token this build does not recognise. `?` is an ADMISSION, not an effect: it means "not proven", never "has an effect". |

Tokens are comma-joined in a fixed order -- `g`, `h`, `s`, then each `p<k>`
in ascending `k`, then `?` -- so `g,p0,p3,?` is a routine that writes global
state, writes through its first and fourth parameters, and also calls
something the analysis could not see into. Readers ignore blanks around a
token and its case.

## Empty is not the same as NULL

| Stored value | `effect_free` | Means |
|---|---|---|
| `''` (empty string) | `1` | **Proven effect-free.** Nothing to name. Hover and the `document` block show this as **Effect-free (proven)**. |
| one or more tokens | `0` | Not proven effect-free; the tokens say why. `effect_witness` names the FIRST blocker in words, e.g. `writes through parameter #1 (AReason)` -- the `#k` there uses the same 0-based numbering as `p<k>`. |
| NULL | NULL | **Not analysed.** The `purity` resolve stage has not run on this index yet, or the routine's file was re-indexed since. Absence of a verdict is ignorance, never a clean bill. |

A symbol that is not a routine with a body (a type, a field, a declaration
without an implementation) has no `symbol_facts` row at all.

## Where each reader sees it

* **Hover** -- the text card prints only **Effect-free (proven)**, and only for a
  proven routine; the JSON form (`hover --format json`) carries `effect_free`,
  `effect_summary` and `effect_witness` for every analysed routine. See
  [Hover at Cursor](Hover-at-Cursor).
* **`document` / autodoc block** -- carries the same **Effect-free (proven)**
  marker and nothing otherwise; the tokens are not written into source.
* **`ask effects`** -- charts the tokens, naming each `p<k>` from the signature.
* **SQL** -- `drag-lint sql --db <db> --query "SELECT ... FROM symbol_facts"`;
  the column contract is in `docs/INDEX-SCHEMA.md`, section 2.15.

The source of truth is `TEffectSummary.Encode` / `Decode` in
`src/analysis/DRagLint.Analysis.Purity.pas`; if this page and that code ever
disagree, the code wins and this page is the bug.
