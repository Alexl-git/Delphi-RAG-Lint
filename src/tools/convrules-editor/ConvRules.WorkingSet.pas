unit ConvRules.WorkingSet;

{ The ordered set of rule-book / catalog files the curation form has open, plus the
  only file-system writes in the curation path.

  Order IS composition precedence: Compose folds the set top to bottom and the
  EARLIER file wins every link collision, so moving a file up promotes its choices.

  VCL-free, so the ordering and composition logic is unit-tested headlessly.
  BackupPath is shared with the main form's Save, so a curation write and a normal
  Save rotate backups identically; WriteTextWithBackup is used by the curation path
  only (the main form does its own copy-then-write around its canonical re-emitter). }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  { HEADERLESS_KINDS is deliberately SHARED, not copied: the "a preamble or
    trailer is never selectable" rule is enforced here, in CanOperateOn and in
    SelectForCompose, and a second spelling of the set is exactly how those
    three drift apart. }
  ConvRules.BlockFile,  // dl:unit ConvRules.BlockFile accepted
  ConvRules.BlockOps;

type
  /// <summary>One loaded file: where it came from and its verbatim blocks.</summary>
  TWorkingFile = record
    Path  : string;
    Blocks: TRuleBlocks;
    /// <summary>Rule-block indexes chosen for the next selective Compose;
    /// nil = nothing chosen in this file.</summary>
    /// <remarks>POSITIONAL, so it is reset by every operation that changes
    /// Blocks -- a stale index would silently name a different rule.</remarks>
    Selected: TArray<Integer>;
  end;

  /// <summary>Ordered list of loaded files. Position = composition precedence.</summary>
  TWorkingSet = class
  private
    FFiles: TList<TWorkingFile>;
  public
    /// <summary>Creates an empty working set (no files loaded).</summary>
    constructor Create;
    /// <summary>Frees the working set and its loaded blocks.</summary>
    destructor Destroy; override;

    /// <summary>Add already-read text under APath (the grammar follows APath's
    /// extension). Used by the tests and by AddFile.</summary>
    procedure AddText(const APath, AText: string);
    /// <summary>Read APath from disk and add it. Raises if the file is unreadable.</summary>
    procedure AddFile(const APath: string);
    /// <summary>Drop the entry at AIndex from the set. Out-of-range is a no-op;
    /// this never touches disk.</summary>
    procedure Remove(AIndex: Integer);
    /// <summary>Swap with the previous entry (raise this file's precedence). No-op at 0.</summary>
    procedure MoveUp(AIndex: Integer);
    /// <summary>Swap with the next entry. No-op at the end.</summary>
    procedure MoveDown(AIndex: Integer);

    /// <summary>Number of files currently loaded.</summary>
    function  Count: Integer;
    /// <summary>The file at AIndex, in composition-precedence order.</summary>
    function  Item(AIndex: Integer): TWorkingFile;
    /// <summary>Replace one file's blocks after a curation operation.</summary>
    procedure SetBlocks(AIndex: Integer; const ABlocks: TRuleBlocks);
    /// <summary>Index of the entry whose Path matches, or -1. Paths are compared
    /// case-insensitively AND after normalisation, so a second spelling of one file
    /// still finds it.</summary>
    function  IndexOfPath(const APath: string): Integer;

    /// <summary>Re-split ATextWritten into the entry that owns APath, so the
    /// in-memory blocks match what was just written to disk.</summary>
    /// <param name="APath">The file just written; any spelling of it.</param>
    /// <param name="ATextWritten">The EXACT text written, so model and disk agree.</param>
    /// <returns>The index re-synced, or -1 when APath is not in the set (then
    /// nothing happened).</returns>
    /// <remarks>Call after EVERY write that may land on a file which is also loaded
    /// here -- a split/copy target, a compose target. Without it that entry keeps
    /// its pre-write blocks: the grid hides the change, Compose folds the stale
    /// model (so the file handed to --rules omits the moved rule), and the next save
    /// of that entry writes the stale model back over what was just moved in.</remarks>
    function  SyncFromText(const APath, ATextWritten: string): Integer;

    /// <summary>True when the set holds more than one grammar (a .castlib beside
    /// .rules files).</summary>
    /// <remarks>Compose only implements the .rules grammar and writes ONE .rules
    /// file, so a mixed set must be refused: cast/enum blocks never match a #convert
    /// header and would be appended whole, producing invalid DSL for --rules.</remarks>
    function  MixedGrammars: Boolean;

    /// <summary>Compose every loaded file, in order, into one .rules text.</summary>
    function  ComposeAll(out AReport: TComposeReport): string;

    /// <summary>Replace one file's selection.</summary>
    /// <param name="AIndex">File index; out of range is a no-op.</param>
    /// <param name="ASelected">Rule-block indexes. Normalised against that
    /// file's blocks: out-of-range and HEADERLESS indexes are dropped, the rest
    /// sorted and de-duplicated.</param>
    procedure SetSelected(AIndex: Integer; const ASelected: TArray<Integer>);
    /// <summary>The file's current selection.</summary>
    /// <param name="AIndex">File index; out of range yields nil.</param>
    /// <returns>Its rule-block indexes, ascending.</returns>
    function  Selected(AIndex: Integer): TArray<Integer>;
    /// <summary>True when any file has a non-empty selection.</summary>
    /// <returns>Whether ComposeSelected would compose a SUBSET.</returns>
    function  AnySelected: Boolean;
    /// <summary>Empty every file's selection.</summary>
    procedure ClearSelection;
    /// <summary>Add, to every file's selection, the blocks converting any of
    /// ATypeNames -- typically the component types found on an examined form.</summary>
    /// <param name="ATypeNames">Type names, bare or qualified.</param>
    /// <returns>How many blocks became selected that were not already, so a
    /// second call with the same types returns 0.</returns>
    /// <remarks>Unions into the existing selection rather than replacing it: it
    /// is one contributing SOURCE, alongside the grid's checkboxes and (once the
    /// engine deploys #tag) by-tag.</remarks>
    function  SelectByTypes(const ATypeNames: TArray<string>): Integer;
    /// <summary>Add, to every file's selection, the rules carrying ATag.</summary>
    /// <param name="ATag">A tag name; '' selects nothing.</param>
    /// <returns>How many blocks became selected that were not already.</returns>
    /// <remarks>The third selection source, and deliberately the SAME shape as
    /// SelectByTypes: it unions rather than replaces, so tags, types and hand
    /// ticks compose instead of overwriting one another.</remarks>
    function  SelectByTag(const ATag: string): Integer;
    /// <summary>Compose the set honouring each file's selection.</summary>
    /// <param name="AReport">Receives the compose report, preceded by one
    /// SelectionReportLine per file when a selection is active.</param>
    /// <returns>The composed text.</returns>
    /// <remarks>When NOTHING is selected anywhere this is exactly ComposeAll --
    /// nothing checked means the whole set, which is what the Compose button did
    /// before selections existed. Otherwise each file contributes
    /// SelectForCompose(Blocks, Selected): its headerless blocks always, its
    /// checked rules as well. A file with no selection AND no headerless blocks
    /// therefore contributes nothing at all.</remarks>
    function  ComposeSelected(out AReport: TComposeReport): string;
    /// <summary>Write one entry back to its own path, backing it up first.</summary>
    /// <returns>The backup path written ('' when the file did not exist yet).</returns>
    function  SaveFile(AIndex: Integer): string;
  end;

/// <summary>PURE: the next unused backup name for APath -- '<file>.bak', then
/// '.bak.2', '.bak.3' ... so a short history is kept and nothing is overwritten.</summary>
/// <remarks>The search STOPS at '.bak.99' and returns that name even when it is
/// already taken. It is not reused: the copy onto an existing file then fails, and
/// WriteTextWithBackup aborts the whole write. That is deliberate -- a full backup
/// history must fail loudly rather than silently overwrite the 99th backup.</remarks>
function BackupPath(const APath: string): string;

/// <summary>APath in a comparable form -- absolute, with '.', '..' and mixed
/// separators resolved -- so two spellings of one file compare equal.</summary>
/// <returns>'' for '', otherwise the resolved path; APath unchanged when the OS
/// cannot resolve it (a malformed path must not make a comparison raise).</returns>
/// <remarks>Not pure: a relative APath resolves against the process's current
/// directory. Every path comparison in the curation path goes through this --
/// IndexOfPath, the split-target guard and the written-paths tracker -- because a
/// second spelling of one file would otherwise defeat all three.</remarks>
function NormalizedPath(const APath: string): string;

/// <summary>Back APath up, then overwrite it with AText as ASCII. Line terminators
/// come from AText itself and are never normalised.</summary>
/// <param name="ABackup">The backup written, or '' when APath did not exist.</param>
/// <exception cref="EInOutError">Raised when the backup copy fails -- APath is then
/// left completely untouched (acceptance criterion 14).</exception>
procedure WriteTextWithBackup(const APath, AText: string; out ABackup: string);

implementation

function BackupPath(const APath: string): string;
var
  n: Integer;
begin
  Result := APath + '.bak';
  n := 2;
  while TFile.Exists(Result) do
  begin
    Result := APath + '.bak.' + IntToStr(n);
    Inc(n);
    if n > 99 then Break; // cap
  end;
end;

function NormalizedPath(const APath: string): string;
begin
  if APath = '' then Exit('');
  try
    Result := TPath.GetFullPath(APath);
  except
    Result := APath;   // unresolvable (bad characters, too long) -- compare as given
  end;
end;

procedure WriteTextWithBackup(const APath, AText: string; out ABackup: string);
begin
  ABackup := '';
  if TFile.Exists(APath) then
  begin
    ABackup := BackupPath(APath);
    try
      TFile.Copy(APath, ABackup);
    except
      on E: Exception do
      begin
        ABackup := '';
        raise EInOutError.CreateFmt('backup of %s failed: %s -- nothing was written',
          [APath, E.Message]);
      end;
    end;
  end;
  TFile.WriteAllText(APath, AText, TEncoding.ASCII);
end;

{ TWorkingSet }

constructor TWorkingSet.Create;
begin
  inherited Create;
  FFiles := TList<TWorkingFile>.Create;
end;

destructor TWorkingSet.Destroy;
begin
  FFiles.Free;
  inherited;
end;

procedure TWorkingSet.AddText(const APath, AText: string);
var
  F: TWorkingFile;
begin
  F.Path   := APath;
  F.Blocks := SplitBlocksFor(APath, AText);
  FFiles.Add(F);
end;

procedure TWorkingSet.AddFile(const APath: string);
begin
  AddText(APath, TFile.ReadAllText(APath, TEncoding.ASCII));
end;

procedure TWorkingSet.Remove(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FFiles.Count) then FFiles.Delete(AIndex);
end;

procedure TWorkingSet.MoveUp(AIndex: Integer);
begin
  if (AIndex > 0) and (AIndex < FFiles.Count) then FFiles.Exchange(AIndex, AIndex - 1);
end;

procedure TWorkingSet.MoveDown(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FFiles.Count - 1) then FFiles.Exchange(AIndex, AIndex + 1);
end;

function TWorkingSet.Count: Integer;
begin
  Result := FFiles.Count;
end;

function TWorkingSet.Item(AIndex: Integer): TWorkingFile;
begin
  Result := FFiles[AIndex];
end;

procedure TWorkingSet.SetBlocks(AIndex: Integer; const ABlocks: TRuleBlocks);
var
  F: TWorkingFile;
begin
  F := FFiles[AIndex];
  F.Blocks := ABlocks;
  { Selection indexes are POSITIONAL, and every caller of SetBlocks -- split,
    delete, merge, SyncFromText -- has just changed the block list. Keeping the
    old indexes would silently point them at different rules, so the selection
    is dropped rather than guessed at. This is the ONE place that owns the reset:
    do not add a second path that assigns Blocks directly. }
  F.Selected := nil;
  FFiles[AIndex] := F;
end;

function TWorkingSet.IndexOfPath(const APath: string): Integer;
var
  i   : Integer;
  Want: string;
begin
  Want := NormalizedPath(APath);
  for i := 0 to FFiles.Count - 1 do
    if SameText(NormalizedPath(FFiles[i].Path), Want) then Exit(i);
  Result := -1;
end;

function TWorkingSet.SyncFromText(const APath, ATextWritten: string): Integer;
begin
  Result := IndexOfPath(APath);
  // Split with the STORED path's grammar: it is the same file, but the stored
  // spelling is the one the rest of the set was built from.
  if Result >= 0 then
    SetBlocks(Result, SplitBlocksFor(FFiles[Result].Path, ATextWritten));
end;

function TWorkingSet.MixedGrammars: Boolean;
var
  i: Integer;
  G: TRuleGrammar;
begin
  Result := False;
  if FFiles.Count = 0 then Exit;
  G := GrammarOf(FFiles[0].Path);
  for i := 1 to FFiles.Count - 1 do
    if GrammarOf(FFiles[i].Path) <> G then Exit(True);
end;

function TWorkingSet.ComposeAll(out AReport: TComposeReport): string;
var
  Inputs: TArray<TComposeInput>;
  i     : Integer;
begin
  SetLength(Inputs, FFiles.Count);
  for i := 0 to FFiles.Count - 1 do
  begin
    Inputs[i].Path   := FFiles[i].Path;
    Inputs[i].Blocks := FFiles[i].Blocks;
  end;
  Result := Compose(Inputs, AReport);
end;

procedure TWorkingSet.SetSelected(AIndex: Integer; const ASelected: TArray<Integer>);
var
  F   : TWorkingFile;
  Keep: TList<Integer>;
  i   : Integer;
begin
  if (AIndex < 0) or (AIndex >= FFiles.Count) then Exit;
  F    := FFiles[AIndex];
  Keep := TList<Integer>.Create;
  try
    { UnionSelections normalises (in range, sorted, de-duplicated); the headerless
      filter is this unit's own -- a preamble or trailer travels regardless, so
      recording it as CHOSEN would double-count it in every report. }
    for i in UnionSelections(F.Blocks, ASelected, nil) do
      if not (F.Blocks[i].Kind in HEADERLESS_KINDS) then
        Keep.Add(i);
    F.Selected      := Keep.ToArray;
    FFiles[AIndex]  := F;
  finally
    Keep.Free;
  end;
end;

function TWorkingSet.Selected(AIndex: Integer): TArray<Integer>;
begin
  if (AIndex < 0) or (AIndex >= FFiles.Count) then Exit(nil);
  Result := FFiles[AIndex].Selected;
end;

function TWorkingSet.AnySelected: Boolean;
var
  i: Integer;
begin
  for i := 0 to FFiles.Count - 1 do
    if Length(FFiles[i].Selected) > 0 then Exit(True);
  Result := False;
end;

procedure TWorkingSet.ClearSelection;
var
  i: Integer;
  F: TWorkingFile;
begin
  for i := 0 to FFiles.Count - 1 do
  begin
    F := FFiles[i];
    F.Selected := nil;
    FFiles[i]  := F;
  end;
end;

function TWorkingSet.SelectByTypes(const ATypeNames: TArray<string>): Integer;
var
  i, Before: Integer;
  F        : TWorkingFile;
begin
  Result := 0;
  for i := 0 to FFiles.Count - 1 do
  begin
    F      := FFiles[i];
    Before := Length(F.Selected);
    { UNION, never replace: by-type is one contributing source alongside the
      grid's checkboxes, so it must not discard what the user ticked by hand. }
    SetSelected(i, UnionSelections(F.Blocks, F.Selected,
      BlocksConvertingTypes(F.Blocks, ATypeNames)));
    Inc(Result, Length(FFiles[i].Selected) - Before);
  end;
end;

function TWorkingSet.SelectByTag(const ATag: string): Integer;
var
  i, Before: Integer;
  F        : TWorkingFile;
begin
  Result := 0;
  for i := 0 to FFiles.Count - 1 do
  begin
    F      := FFiles[i];
    Before := Length(F.Selected);
    SetSelected(i, UnionSelections(F.Blocks, F.Selected,
      BlocksWithTag(F.Blocks, ATag)));
    Inc(Result, Length(FFiles[i].Selected) - Before);
  end;
end;

function TWorkingSet.ComposeSelected(out AReport: TComposeReport): string;
var
  Inputs: TArray<TComposeInput>;
  Head  : TArray<string>;
  i     : Integer;
begin
  { Nothing checked anywhere means the WHOLE set -- the convention the Compose
    button had before selections existed, kept so the old behaviour is reachable
    without a mode switch. }
  if not AnySelected then Exit(ComposeAll(AReport));

  SetLength(Inputs, FFiles.Count);
  Head := ['Selective compose -- only the checked rules, plus every file''s '
    + 'header and trailer:'];
  for i := 0 to FFiles.Count - 1 do
  begin
    Inputs[i].Path   := FFiles[i].Path;
    Inputs[i].Blocks := SelectForCompose(FFiles[i].Blocks, FFiles[i].Selected);
    Head := Head + [SelectionReportLine(FFiles[i].Path, FFiles[i].Blocks,
      FFiles[i].Selected)];
  end;
  Result        := Compose(Inputs, AReport);
  AReport.Lines := Head + AReport.Lines;
end;

function TWorkingSet.SaveFile(AIndex: Integer): string;
begin
  WriteTextWithBackup(FFiles[AIndex].Path, JoinBlocks(FFiles[AIndex].Blocks), Result);
end;

end.
