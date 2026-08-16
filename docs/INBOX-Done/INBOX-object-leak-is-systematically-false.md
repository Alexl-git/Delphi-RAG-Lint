> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16. The surviving cause -- "a tree cursor whose nodes escape via the returned root" -- is now detected: `Cur := TNode.Create(..., Cur)` passes the assignment TARGET as an argument to its own constructor, so the node links itself into a structure reachable from the returned root. Needed in BOTH TEscape.Transfer AND the FlowChecks replay -- the lattice computes block state but the replay records the reportable site, so fixing only the lattice changed nothing observable. YADF object-leak 1 -> 0. Guarded by tests\autotest\run_object_leak_self_linked.ps1 (3/3) with a genuine leak as control. Narrow on purpose: fires only when the target itself is among the arguments, so A := T.Create(B) is untouched.

# `object-leak` is systematically false -- 8 of 8 sampled, two distinct causes

> **RE-MEASURED 2026-08-14 (session 19). CAUSE A IS FIXED; the spread below is
> stale by an order of magnitude, and this rule is NO LONGER the largest obstacle
> to zero.**
>
> | project | note's figure | now |
> |---|---|---|
> | YADF | 3 | **1** |
> | YADFOT | 7 | **1** |
> | YADFSetup | 7 | **1** |
>
> Cause A (the guard is on the next line) was fixed by `968e7ce` -- "an enclosing
> try..EXCEPT hid the try..FINALLY that frees" -- which turns out to have been the
> dominant shape exactly as this note predicted. 25 findings -> 3.
>
> **All three survivors are the SAME finding**, in a unit shared by the three
> projects, so it is ONE defect counted three times:
>
> ```
> YADF.Groups.pas:174:66  [info] object-leak: Object "cur" may be leaked
> ```
>
> **And it is a THIRD cause, not A and not B.** Neither of this note's two causes
> covers it:
>
> ```pascal
> ptUses, ptContains, ptRequires:
>   if Cur.Kind <> gkUses then Cur := TGroup.Create(gkUses, i, K, Cur);
> ...
> Root.CloseIdx := ATokens.Count - 1;
> Result := Root;      { the whole tree is returned }
> ```
>
> `Cur` is a CURSOR INTO A TREE. Each `TGroup.Create` takes the current node as
> its PARENT (last argument), so the new object is linked into a structure whose
> root is the return value -- the caller owns the tree. `Cur` is also reassigned
> from `Cur.Parent` on the way back up, so it is not an owning variable at all.
>
> Call this **Cause C -- ownership transferred by being linked into a structure
> that escapes.** It is an escape-analysis question, not a syntactic one, and the
> escape analysis already in `FlowChecks` (`EscAna`) evidently does not follow a
> reference handed to a CONSTRUCTOR ARGUMENT of an object that itself escapes.
>
> **Deliberately NOT fixed now, and this is a judgement call worth stating:** it
> is one `info`-severity finding, in one unit, and a correct fix is
> escape-through-constructor-argument analysis -- a real piece of work. The cheap
> heuristics all fail: "near a `try`" is Cause A's fix and does not apply, and
> "assigned more than once" or "also passed as an argument" would silence genuine
> leaks. Cause B (owned `TComponent`) no longer appears in any of the three
> projects, so it cannot be confirmed as live either -- do not build the ancestry
> machinery for it until a real instance is in hand.
>
> The suggested-guard fixture at the bottom is still worth having, and its last
> case -- a GENUINE leak that must still fire -- is the important one, because the
> cheap fix for every one of these causes is to stop reporting.

Filed 2026-08-13 during the YADF and DataCopy LoopZero runs. This rule is the
single largest obstacle left to a true zero, and it is not the code's fault.

Prior art agrees: an earlier session recorded "0/12 object-leaks real" when it
sampled the category. Nothing has changed since.

## Current spread

| Project | `object-leak` |
|---|---|
| YADF.dproj | 3 |
| YADFOT.dproj | 7 |
| YADFSetup.dproj | 7 |
| DataCopy.dproj | 8 |

8 sampled across YADF and DataCopy. **8 false.**

## Cause A -- the very next statement is `try`

The dominant shape. The rule reports a leak on the construction line while the
guard is on the line immediately below it.

    YADF.Tokens.pas:266     Lex:= TmwPasLex.Create;
                            try ... finally Lex.Free; end;

    YadfMain.pas:1014       OutVal:= TList<string>.Create;
                            try ...

    uFileUtils.pas:1691     LStream:= TFileStream.Create(pTo, fmCreate);
                            try ...

    DPPRoutines.pas:569     DestFile:= TStreamWriter.Create(CSVFileName, True, TEncoding.ASCII);
                            try ...

A variant, also reported, is the construct-inside-try-except that cleans up and
re-raises -- textbook, and the opposite of a leak:

    DPPRoutines.pas:527     SourceStream:= TFileStream.Create(HFile);
                            except CloseHandle(HFile); raise; end;

    YADF.Tokens.pas:309     except Result.Free; raise; end;

## Cause B -- VCL ownership

    uMainZeissCopy.pas:2346  LTimer:= TTimer.Create(LDlg);

`LDlg` is the Owner. A `TComponent` constructed with a non-nil Owner is freed by
that Owner -- freeing it explicitly is the bug, not omitting the free. The rule
has no notion of ownership transfer, so every owned component reads as a leak.
This is pervasive in VCL code and is why the two form-heavy projects (YADFOT,
YADFSetup) sit at 7 each.

## Why it must not be `allow`ed

The standard is explicit: never allow a false positive -- it records something
untrue about the code, permanently, with a hash on it, in every project carrying
the pattern. So these 25 findings are simply stuck until the rule is fixed. They
are the reason YADF cannot reach zero today.

## What a fix needs

* **Cause A** is syntactic and should be cheap: after the assignment statement,
  look at the next sibling statement. If it is a `try` whose `finally` (or whose
  `except`) frees or re-raises, the object is protected. Watch the multi-Create
  case (`CSVRoutines.pas:268` constructs three objects in a row before one shared
  `try`) -- protection covers every object constructed between the last statement
  and the `try`, not just the closest one.
* **Cause B** needs the type: is the constructed type a `TComponent` descendant,
  and is argument 0 a non-nil expression? The store has ancestry
  (`ResolveAncestry` populates it), so this is answerable with the project DB --
  the same store-backed-supersedes-syntactic pattern used for
  `string-equality-comparison`.

## Suggested guard

A fixture with all five shapes -- next-statement `try`, try/except+re-raise,
multi-Create before one `try`, owned `TComponent`, and a GENUINE leak that must
still fire. The last one matters most: the cheap fix for this rule is to stop
reporting near a `try`, which would silence real leaks too.
