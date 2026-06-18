# BACKLOG: ghost-compile Phase 2 -- overlay unsaved DFMs

Status: **designed, not implemented** (needs the live IDE to test). Captured 2026-06-18.

## Why

ghost-compile overlays unsaved `.pas` buffers so compiler errors appear without
saving (multi-unit, shipped in `84d677a`). But a form's `.dfm` can be edited
without saving too -- e.g. the user deletes a `TEdit` in the designer. If code
still references that field, the compiler should flag it. Today the overlay uses
the on-disk (stale) `.dfm`, so that error is missed until save.

## Engine side -- ALREADY DONE

`ghost-check --overlays <manifest>` already accepts ANY real path, including a
`.dfm`. `DoGhostCheck` only resolves/deletes a `.dcu` for `.pas` entries; a `.dfm`
entry is overlaid + restored like any file. **Caveat:** overlaying a changed
`.dfm` whose owning `.pas` is unchanged will NOT force the `.pas` to recompile
(its mtime is untouched), so the new `.dfm` isn't picked up. Fix when implementing:
for every overlaid `.dfm`, also force the owning `<base>.pas` to recompile -- add
a synthetic overlay of the owning `.pas` (buffer = its current disk/buffer bytes)
so its mtime gets stamped + its `.dcu` dropped. (i.e. when the plugin emits a
`.dfm` overlay it should also emit the owning `.pas` overlay.)

## Plugin side -- TO DO (in DragLint.Plugin.Editor.pas, CollectUnsavedOverlays)

For each open module, also handle its form editor:

```pascal
// Ed := Modu.GetModuleFileEditor(FE);
if Supports(Ed, IOTAFormEditor, FormEd) then
begin
  DfmPath := FormEd.FileName;                 // the .dfm path
  DfmText := GetFormDfmText(FormEd);          // helper below, fully guarded
  if (DfmText <> '') and FormIsModified(...) then
    ... stage DfmText to a temp .dfm + add 'DfmPath'<TAB>temp to the manifest,
        AND ensure the owning .pas is also in the manifest (see engine caveat) ...
end;
```

`GetFormDfmText` -- stream the in-memory form to TEXT dfm:

```pascal
// uses System.Classes (TStreamAdapter, ObjectBinaryToText), ActiveX (IStream)
function GetFormDfmText(const AForm: IOTAFormEditor): string;
var Bin, Txt: TMemoryStream; Adapter: IStream; B: TBytes;
begin
  Result := '';
  Bin := TMemoryStream.Create; Txt := TMemoryStream.Create;
  try
    try
      Adapter := TStreamAdapter.Create(Bin, soReference);
      AForm.GetFormResource(Adapter);          // IOTAFormEditor.GetFormResource(IStream) -- ToolsAPI ~line 2908
      Bin.Position := 0;
      if Bin.Size > 0 then
      begin
        ObjectBinaryToText(Bin, Txt);          // binary form -> text .dfm
        Txt.Position := 0;
        SetLength(B, Txt.Size); if Txt.Size > 0 then Txt.ReadBuffer(B[0], Txt.Size);
        Result := TEncoding.ANSI.GetString(B);
      end;
    except Result := ''; end;                   // degrade to .pas-only on any failure
  finally Bin.Free; Txt.Free; end;
end;
```

## The two open problems (why it's not shipped yet)

1. **Reliable "is the form modified?"** `IOTAModule.Modified` is NOT exposed on
   the interface `IOTAModuleServices.Modules[]` returns in RAD 37 (compile error
   E2003 'Modified' -- that's why the `.pas` path uses a byte-diff instead).
   For `.dfm`, a byte-diff is unreliable: `ObjectBinaryToText` emits a CANONICAL
   text form that won't match the hand/IDE-saved `.dfm` even when unmodified, so
   it would re-overlay every open form every ghost-check (mass recompiles).
   Need a real modified flag first. Candidates to try IN the IDE:
   - `IOTAEditBuffer.IsModified` (ToolsAPI ~line 7515) via a source editor's
     edit view: `Src.GetEditView(0).Buffer.IsModified` (guard EditViewCount > 0).
   - The form designer: `IOTAFormEditor` -> `IDesigner` (DesignIntf) IsModified.
   - A cast of the module to whichever interface version DOES expose `Modified`.
2. **Untestable without the running IDE.** Form streaming + the modified flag
   must be exercised live. Implement behind heavy try/except so any failure
   degrades cleanly to the proven `.pas`-only overlay (never crash the IDE).

## When picking this up

Do it WITH the IDE open: solve (1) first (find the modified flag that compiles +
works), then add the `.dfm` + owning-`.pas` overlays, then verify deleting a
`TEdit` used in code surfaces the compile error and the `.dfm`/`.pas` are restored
exactly (byte + tick-exact), `_D-RAG` left clean.
