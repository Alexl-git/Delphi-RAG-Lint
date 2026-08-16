> # CLOSED 2026-08-16 (session 22) -- FIXED IN Loader2019, on owner instruction.
>
> Owner: *"If the fix is only to free the INI file object then do it."* Done --
> `FreeAndNil(INIFile);` added immediately before the `Exit;` on the
> `INIFile.FileName = ''` path in `TfrmLoader2019_Main.FormCreate`
> (`C:\Projects\Loader2019\Loader2019.Main.pas`).
>
> Verified: after reindexing that file, `lint Loader2019.Main.pas` reports **no
> `object-leak` findings at all** (it reported `object-leak: Object "inifile"
> may be leaked` at `:3121` immediately before).
>
> **The bare free was chosen over `try..finally` deliberately** -- the note
> offered both, and wrapping would have re-indented ~210 lines of an external
> project for a leak that costs one `TmeminiFile` at shutdown (WM_QUIT is already
> posted). A comment at the site warns the next person that a new early return
> between the create and the free reintroduces the leak, which is the one thing
> the bare free does not protect against.
>
> Note this leaves the SEPARATE `unprotected-object-free` warning standing at
> `:3150` -- that rule wants the `try..finally` and is not what this note was
> about. Closing it is a distinct decision about the same routine.
>
> Edit made in `C:\Projects\Loader2019`, which is OUTSIDE this repo and is not
> committed here.

# INBOX -- Loader2019: `INIFile` leaks on the early-exit path in `FormCreate`

> **RE-MEASURED 2026-08-16 -- still fires, still a true positive.** The next-session
> plan asked for a re-check against this session's object-leak fixes (self-linking
> construction, `Result.`/`Self.` writes). Those did not touch it:
>
> ```
> Loader2019.Main.pas:3121:5  [info] object-leak: Object "inifile" may be leaked:
>   created but not freed or transferred on some path.
> ```
>
> DB `C:\Projects\Loader2019\_D-RAG\Loader2025.sqlite` indexed 2026-08-16 06:17,
> source last modified 2026-05-26 -- fresh, so the finding is authoritative.
> Source re-read: the leak is exactly as described, and the earlier `Exit` at
> `:3131` is BEFORE the `Create` at `:3121`, so only the `:3142` path leaks.
>
> **This is not drag-lint debt.** It is a correct finding about an external
> project. Closing it here requires an edit to `C:\Projects\Loader2019`, which is
> the owner's call -- not made.

Found 2026-08-07 by drag-lint, while measuring the blast radius of the B9 CFG fix
(`exit` now diverts). Not a drag-lint defect -- a real defect in Loader2019 that the
tool could not see before, recorded here so it is not lost with the measurement.

## The leak

`C:\Projects\Loader2019\Loader2019.Main.pas`, `TfrmLoader2019_Main.FormCreate`:

- `INIFile: TmeminiFile` is a **local** variable (declared :3040).
- created at **:3121** -- `INIFile:= TmeminiFile.Create(AFileName);`
- freed at **:3335** -- `INIFile.Free;`, near the end of the routine.
- but **:3142** returns between the two:

```pascal
  if INIFile.FileName = '' then
  begin
    CodeSite.SendError('Start 5');
    MessageBeep(mb_IconHand);
    MessageDlg('Unable to Open "' + INIFILENAME + '" file.' + ... , mtError, [MBOK], 0);
    PostMessage(Application.Handle, WM_QUIT, 16, 16);
    Exit;                       <-- INIFile is never freed on this path
  end;
```

The `PostMessage(WM_QUIT)` means the app is on its way down, so the practical cost is one
leaked `TmeminiFile` at shutdown rather than a growing leak. It is still worth fixing: the
routine already owns the object and already frees it on the normal path, so the guard is
simply missing its half.

Suggested fix -- wrap the creation in `try..finally`, which is what the rest of the routine's
shape already implies. A bare `FreeAndNil(INIFile)` before the `Exit;` would also do it but
leaves the same trap for the next early return added to this routine.

## Why it was invisible until now

`drag-lint`'s CFG never modelled `exit;` as diverting (B9 -- a `statement` node's text
carries its semicolon, so the test `'exit;' = 'exit'` was always false). The exit fell
through to the code below it, which includes the `INIFile.Free`, so every early return looked
like it freed the object. Fixing the divert made `object-leak` see the real path.

This was the ONLY new finding across three corpora when B9 was measured (DataCopy 473 -> 465,
TableTools unchanged, Loader2019 3367 -> 3366), and every other change was a false positive
being removed.
