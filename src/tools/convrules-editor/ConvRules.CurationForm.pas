unit ConvRules.CurationForm;

{ Modal rule-book / catalog curation window -- opened on request from the main form,
  not present otherwise.

  Shows a WORKING SET (several files loaded together, because one conversion may need
  several interdependent books) and, below it, every block across the set with a file
  column and a checkbox. The toolbar acts on the checked blocks: split out, copy out,
  delete, merge another file in, or compose the whole set into one file for the engine.

  Every write goes through ConvRules.WorkingSet.WriteTextWithBackup and moves VERBATIM
  block text -- never the main form's canonical re-emitter, so a block that was merely
  moved comes back byte-identical. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  ConvRules.BlockFile, ConvRules.BlockOps, ConvRules.WorkingSet;

type
  /// <summary>The modal curation window.</summary>
  TCurationForm = class(TForm)
  private
    FSet     : TWorkingSet;
    FFiles   : TListBox;      // working set, top to bottom = composition precedence
    FBlocks  : TListView;     // vsReport + Checkboxes: File | Kind | Block | Lines
    FStatus  : TStatusBar;
    FBtnSplit, FBtnCopy, FBtnDelete, FBtnMerge, FBtnCompose: TButton;
    FTouched : TDictionary<string, Boolean>;   // paths this session wrote

    procedure BuildUI;
    procedure RefreshFiles;
    procedure RefreshBlocks;
    procedure UpdateEnabled;
    function  CheckedIndexes(out AFileIdx: Integer): TArray<Integer>;
    procedure BlocksChange(Sender: TObject; Item: TListItem; Change: TItemChange);
    procedure FFilesClick(Sender: TObject);
    procedure DoAddFile(Sender: TObject);
    procedure DoRemoveFile(Sender: TObject);
    procedure DoMoveUp(Sender: TObject);
    procedure DoMoveDown(Sender: TObject);
    procedure DoSplit(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoDelete(Sender: TObject);
    procedure DoMerge(Sender: TObject);
    procedure DoCompose(Sender: TObject);
    function  SaveSet(AIndex: Integer): Boolean;
    function  AskTargetFile(const ADefault: string): string;
    function  WriteBlocksTo(const APath: string; const ABlocks: TRuleBlocks;
      out ABackup, ANote: string): Boolean;
  public
    /// <summary>Creates the form and its (initially empty) working set. Prefer
    /// Execute over calling this directly.</summary>
    constructor Create(AOwner: TComponent); override;
    /// <summary>Frees the working set and the touched-paths tracker.</summary>
    destructor Destroy; override;
    /// <summary>Show the modal curation window seeded with AInitialPath (may be '').</summary>
    /// <returns>AInitialPath when that file was modified and the caller must reload
    /// it, otherwise ''.</returns>
    class function Execute(AOwner: TComponent; const AInitialPath: string): string;
  end;

implementation

{ The key FTouched stores a written path under: ONE canonical, case-folded spelling
  per file, so 'C:\b\x.rules' and 'C:\b\sub\..\x.rules' are the same entry and the
  main form's "reload me" signal cannot be missed by a second spelling. }
function TouchKey(const APath: string): string;
begin
  Result := LowerCase(NormalizedPath(APath));
end;

{ A simple modal report window: a read-only, non-wrapping memo listing ALines, plus
  a Close button. Unit-level (not a class) -- nothing else needs to create or
  address it, and it has no state of its own. }
procedure ShowReport(AOwner: TComponent; const ACaption: string;
  const ALines: TArray<string>);
var
  F   : TForm;
  Memo: TMemo;
  Btn : TButton;
  S   : string;
begin
  F := TForm.CreateNew(AOwner);
  try
    F.Caption     := ACaption;
    F.Width       := 760;
    F.Height      := 480;
    F.Position    := poOwnerFormCenter;
    F.BorderStyle := bsSizeable;

    Btn := TButton.Create(F);
    Btn.Parent := F; Btn.Align := alBottom;
    Btn.Caption := 'Close'; Btn.ModalResult := mrOk;

    Memo := TMemo.Create(F);
    Memo.Parent     := F;
    Memo.Align      := alClient;
    Memo.ReadOnly   := True;
    Memo.ScrollBars := ssBoth;
    Memo.WordWrap   := False;
    Memo.Font.Name  := 'Consolas';
    Memo.Font.Size  := 9;
    for S in ALines do
      Memo.Lines.Add(S);

    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ Ask which side wins for each conflicting target. One row per conflict; checked =
  take the incoming link, unchecked (default) = keep what the target already has.
  Returns False on Cancel -- the caller then abandons the merge entirely (criterion
  6: nothing is written until every conflict is resolved). }
function AskResolutions(AOwner: TComponent; const APlan: TMergePlan;
  const AIncomingName: string; out ARes: TArray<TMergeResolution>): Boolean;
var
  F   : TForm;
  LV  : TListView;
  Btm : TPanel;
  BtnOK, BtnCancel: TButton;
  It  : TMergeItem;
  Row : TListItem;
  i   : Integer;
begin
  Result := False;
  ARes   := nil;
  F := TForm.CreateNew(AOwner);
  try
    F.Caption     := 'Resolve conflicts -- ' + AIncomingName;
    F.Width       := 820;
    F.Height      := 420;
    F.Position    := poOwnerFormCenter;
    F.BorderStyle := bsSizeable;

    Btm := TPanel.Create(F);
    Btm.Parent := F; Btm.Align := alBottom; Btm.Height := 40; Btm.BevelOuter := bvNone;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := Btm; BtnOK.SetBounds(8, 6, 90, 25);
    BtnOK.Caption := 'OK'; BtnOK.ModalResult := mrOk; BtnOK.Default := True;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := Btm; BtnCancel.SetBounds(104, 6, 90, 25);
    BtnCancel.Caption := 'Cancel'; BtnCancel.ModalResult := mrCancel; BtnCancel.Cancel := True;

    LV := TListView.Create(F);
    LV.Parent := F; LV.Align := alClient;
    LV.ViewStyle  := vsReport;
    LV.Checkboxes := True;
    LV.RowSelect  := True;
    LV.ReadOnly   := True;
    LV.Columns.Add.Caption := 'Target';          LV.Columns[0].Width := 240;
    LV.Columns.Add.Caption := 'Keep (existing)';  LV.Columns[1].Width := 260;
    LV.Columns.Add.Caption := 'Take (incoming)';  LV.Columns[2].Width := 260;

    // One row per maConflict item, IN PLAN ORDER -- this order is what ApplyMerge's
    // "indexed by conflict ordinal" means, so a row's position IS its ordinal.
    for i := 0 to High(APlan.Items) do
    begin
      It := APlan.Items[i];
      if It.Action <> maConflict then Continue;
      Row := LV.Items.Add;
      Row.Caption := It.ToPath;
      Row.SubItems.Add(Format('%s <- %s', [It.ToPath, It.ExistingFrom]));
      Row.SubItems.Add(Format('%s <- %s', [It.ToPath, It.IncomingFrom]));
    end;

    if F.ShowModal <> mrOk then Exit;

    SetLength(ARes, LV.Items.Count);
    for i := 0 to LV.Items.Count - 1 do
      if LV.Items[i].Checked then ARes[i] := mrTakeIncoming
      else ARes[i] := mrKeepExisting;
    Result := True;
  finally
    F.Free;
  end;
end;

{ TCurationForm }

constructor TCurationForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FSet     := TWorkingSet.Create;
  FTouched := TDictionary<string, Boolean>.Create;
  BuildUI;
end;

destructor TCurationForm.Destroy;
begin
  FTouched.Free;
  FSet.Free;
  inherited;
end;

class function TCurationForm.Execute(AOwner: TComponent;
  const AInitialPath: string): string;
var
  F: TCurationForm;
begin
  Result := '';
  F := TCurationForm.Create(AOwner);
  try
    if (AInitialPath <> '') and TFile.Exists(AInitialPath) then
    begin
      F.FSet.AddFile(AInitialPath);
      F.RefreshFiles;
      if F.FFiles.Items.Count > 0 then F.FFiles.ItemIndex := 0;
      F.RefreshBlocks;
    end;
    F.UpdateEnabled;
    F.ShowModal;
    if (AInitialPath <> '') and F.FTouched.ContainsKey(TouchKey(AInitialPath)) then
      Result := AInitialPath;
  finally
    F.Free;
  end;
end;

procedure TCurationForm.BuildUI;
var
  Top: TPanel;
begin
  Caption     := 'Curate rule-books';
  Width       := 1100;
  Height      := 640;
  Position    := poOwnerFormCenter;
  BorderStyle := bsSizeable;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  FStatus.SimpleText  := 'Add the rule-books that belong to this conversion.';

  Top := TPanel.Create(Self);
  Top.Parent := Self; Top.Align := alTop; Top.Height := 72; Top.BevelOuter := bvNone;

  // row 1 -- working-set management
  var B: TButton := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(8, 6, 90, 25);
  B.Caption := 'Add file...'; B.OnClick := DoAddFile;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(104, 6, 80, 25);
  B.Caption := 'Remove'; B.OnClick := DoRemoveFile;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(190, 6, 80, 25);
  B.Caption := 'Move up'; B.OnClick := DoMoveUp;
  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(276, 6, 90, 25);
  B.Caption := 'Move down'; B.OnClick := DoMoveDown;
  var L: TLabel := TLabel.Create(Self);
  L.Parent := Top; L.SetBounds(376, 11, 600, 15);
  L.Caption := 'Order = composition precedence: the file nearest the top wins every '
    + 'link collision.';

  // row 2 -- block operations
  FBtnSplit := TButton.Create(Self);
  FBtnSplit.Parent := Top; FBtnSplit.SetBounds(8, 38, 90, 25);
  FBtnSplit.Caption := 'Split...'; FBtnSplit.OnClick := DoSplit;
  FBtnSplit.Hint := 'Move the checked blocks OUT of this file into another';
  FBtnSplit.ShowHint := True;

  FBtnCopy := TButton.Create(Self);
  FBtnCopy.Parent := Top; FBtnCopy.SetBounds(104, 38, 90, 25);
  FBtnCopy.Caption := 'Copy...'; FBtnCopy.OnClick := DoCopy;
  FBtnCopy.Hint := 'Copy the checked blocks into another file; this file is unchanged';
  FBtnCopy.ShowHint := True;

  FBtnDelete := TButton.Create(Self);
  FBtnDelete.Parent := Top; FBtnDelete.SetBounds(200, 38, 90, 25);
  FBtnDelete.Caption := 'Delete'; FBtnDelete.OnClick := DoDelete;

  FBtnMerge := TButton.Create(Self);
  FBtnMerge.Parent := Top; FBtnMerge.SetBounds(306, 38, 110, 25);
  FBtnMerge.Caption := 'Merge from...'; FBtnMerge.OnClick := DoMerge;

  FBtnCompose := TButton.Create(Self);
  FBtnCompose.Parent := Top; FBtnCompose.SetBounds(422, 38, 110, 25);
  FBtnCompose.Caption := 'Compose...'; FBtnCompose.OnClick := DoCompose;
  FBtnCompose.Hint := 'Fold the whole working set into ONE .rules file for --rules';
  FBtnCompose.ShowHint := True;

  B := TButton.Create(Self);
  B.Parent := Top; B.SetBounds(548, 38, 80, 25);
  B.Caption := 'Close'; B.ModalResult := mrOk;

  FFiles := TListBox.Create(Self);
  FFiles.Parent := Self; FFiles.Align := alTop; FFiles.Height := 96;
  FFiles.OnClick := FFilesClick;

  FBlocks := TListView.Create(Self);
  FBlocks.Parent := Self; FBlocks.Align := alClient;
  FBlocks.ViewStyle  := vsReport;
  FBlocks.Checkboxes := True;
  FBlocks.RowSelect  := True;
  FBlocks.ReadOnly   := True;
  FBlocks.OnChange   := BlocksChange;
  FBlocks.Columns.Add.Caption := 'File';    FBlocks.Columns[0].Width := 200;
  FBlocks.Columns.Add.Caption := 'Kind';    FBlocks.Columns[1].Width := 70;
  FBlocks.Columns.Add.Caption := 'Block';   FBlocks.Columns[2].Width := 620;
  FBlocks.Columns.Add.Caption := 'Lines';   FBlocks.Columns[3].Width := 80;
end;

procedure TCurationForm.RefreshFiles;
var
  i, Keep: Integer;
begin
  Keep := FFiles.ItemIndex;
  FFiles.Items.BeginUpdate;
  try
    FFiles.Items.Clear;
    for i := 0 to FSet.Count - 1 do
      FFiles.Items.Add(Format('%d. %s   [%s]',
        [i + 1, ExtractFileName(FSet.Item(i).Path), FSet.Item(i).Path]));
  finally
    FFiles.Items.EndUpdate;
  end;
  if (Keep >= 0) and (Keep < FFiles.Items.Count) then FFiles.ItemIndex := Keep
  else if FFiles.Items.Count > 0 then FFiles.ItemIndex := 0;
end;

{ The grid shows the SELECTED file's blocks, so row index = block index. }
procedure TCurationForm.RefreshBlocks;
const
  KIND_NAME: array[TRuleBlockKind] of string = ('header', 'convert', 'cast', 'enum');
var
  fi, i: Integer;
  F    : TWorkingFile;
  It   : TListItem;
begin
  FBlocks.Items.BeginUpdate;
  try
    FBlocks.Items.Clear;
    fi := FFiles.ItemIndex;
    // Out-of-range (e.g. the working set just emptied) leaves the grid blank --
    // fall through to UpdateEnabled below either way, not an early Exit, so
    // enablement always tracks the CURRENT selection.
    if (fi >= 0) and (fi < FSet.Count) then
    begin
      F := FSet.Item(fi);
      for i := 0 to High(F.Blocks) do
      begin
        It := FBlocks.Items.Add;
        It.Caption := ExtractFileName(F.Path);
        It.SubItems.Add(KIND_NAME[F.Blocks[i].Kind]);
        It.SubItems.Add(BlockLabel(F.Blocks[i]));
        It.SubItems.Add(Format('%d-%d', [F.Blocks[i].StartLine, F.Blocks[i].EndLine]));
      end;
    end;
  finally
    FBlocks.Items.EndUpdate;
  end;
  UpdateEnabled;
end;

function TCurationForm.CheckedIndexes(out AFileIdx: Integer): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer;
begin
  AFileIdx := FFiles.ItemIndex;
  List := TList<Integer>.Create;
  try
    for i := 0 to FBlocks.Items.Count - 1 do
      if FBlocks.Items[i].Checked then List.Add(i);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ Acceptance criterion 12: the block commands act on a selection, so an empty
  selection disables them. CanOperateOn is the single shared rule. }
procedure TCurationForm.UpdateEnabled;
var
  fi : Integer;
  Sel: TArray<Integer>;
begin
  Sel := CheckedIndexes(fi);
  FBtnSplit.Enabled   := CanOperateOn(Sel) and (fi >= 0);
  FBtnCopy.Enabled    := FBtnSplit.Enabled;
  FBtnDelete.Enabled  := FBtnSplit.Enabled;
  FBtnMerge.Enabled   := (fi >= 0);
  FBtnCompose.Enabled := FSet.Count > 0;
end;

procedure TCurationForm.BlocksChange(Sender: TObject; Item: TListItem;
  Change: TItemChange);
begin
  if Change = ctState then UpdateEnabled;
end;

procedure TCurationForm.FFilesClick(Sender: TObject);
begin
  RefreshBlocks;
end;

procedure TCurationForm.DoAddFile(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib|'
      + 'reFind rules (*.txt)|*.txt|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    if FSet.IndexOfPath(Dlg.FileName) >= 0 then
    begin
      FStatus.SimpleText := 'Already in the working set: ' + ExtractFileName(Dlg.FileName);
      Exit;
    end;
    FSet.AddFile(Dlg.FileName);
    RefreshFiles;
    FFiles.ItemIndex := FSet.Count - 1;
    RefreshBlocks;
    FStatus.SimpleText := 'Added ' + ExtractFileName(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TCurationForm.DoRemoveFile(Sender: TObject);
begin
  if FFiles.ItemIndex < 0 then Exit;
  FSet.Remove(FFiles.ItemIndex);   // closes it here; the file on disk is untouched
  RefreshFiles;
  RefreshBlocks;
end;

procedure TCurationForm.DoMoveUp(Sender: TObject);
var
  i: Integer;
begin
  i := FFiles.ItemIndex;
  if i <= 0 then Exit;
  FSet.MoveUp(i);
  RefreshFiles;
  FFiles.ItemIndex := i - 1;
  RefreshBlocks;
end;

procedure TCurationForm.DoMoveDown(Sender: TObject);
var
  i: Integer;
begin
  i := FFiles.ItemIndex;
  if (i < 0) or (i >= FSet.Count - 1) then Exit;
  FSet.MoveDown(i);
  RefreshFiles;
  FFiles.ItemIndex := i + 1;
  RefreshBlocks;
end;

function TCurationForm.AskTargetFile(const ADefault: string): string;
var
  Dlg: TSaveDialog;
begin
  Result := '';
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter     := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib';
    Dlg.DefaultExt := Copy(ExtractFileExt(ADefault), 2, MaxInt);
    Dlg.FileName   := ADefault;
    Dlg.Options    := Dlg.Options - [ofOverwritePrompt];  // we back up, never clobber
    if Dlg.Execute then Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

{ Write ABlocks into APath, APPENDING when the file already exists. A split/copy is a
  MOVE of verbatim text, not a merge -- no link reconciliation happens here.

  ANote is what the caller must tell the user about the TARGET, because the target
  dialog deliberately has no overwrite prompt (we back up instead of clobbering) and
  so an append into an existing book has no other signal: whether the file was new or
  appended to, and whether the append duplicated a header the target already had.

  When APath is ALSO in the working set its entry is re-synced from the exact text
  written -- otherwise that entry keeps its pre-write blocks, the grid hides the
  change, Compose folds the stale model, and the next save of that entry writes the
  stale model back over what was just moved in. }
function TCurationForm.WriteBlocksTo(const APath: string;
  const ABlocks: TRuleBlocks; out ABackup, ANote: string): Boolean;
var
  Existing: TRuleBlocks;
  NewText : string;
  Dups    : TArray<string>;
  Existed : Boolean;
begin
  Result  := False;
  ABackup := '';
  ANote   := '';
  try
    Existed := TFile.Exists(APath);
    if Existed then
      Existing := SplitBlocksFor(APath, TFile.ReadAllText(APath, TEncoding.ASCII))
    else
      Existing := nil;
    NewText := JoinBlocks(ConcatBlocks(Existing, ABlocks));
    WriteTextWithBackup(APath, NewText, ABackup);
    FTouched.AddOrSetValue(TouchKey(APath), True);

    if FSet.SyncFromText(APath, NewText) >= 0 then
    begin
      RefreshFiles;
      RefreshBlocks;
    end;

    if Existed then
    begin
      ANote := 'appended to the existing file';
      Dups  := DuplicateHeaders(Existing, ABlocks);
      if Length(Dups) > 0 then
        ANote := ANote + Format('; WARNING it already had %d of these header(s) (%s)'
          + ' -- it now holds two blocks for them',
          [Length(Dups), string.Join(', ', Dups)]);
    end
    else
      ANote := 'new file';
    Result := True;
  except
    on E: Exception do
      FStatus.SimpleText := 'Write failed, nothing changed: ' + E.Message;
  end;
end;

function TCurationForm.SaveSet(AIndex: Integer): Boolean;
var
  Bak: string;
begin
  Result := False;
  try
    Bak := FSet.SaveFile(AIndex);
    FTouched.AddOrSetValue(TouchKey(FSet.Item(AIndex).Path), True);
    FStatus.SimpleText := Format('Saved %s (backup %s)',
      [ExtractFileName(FSet.Item(AIndex).Path), ExtractFileName(Bak)]);
    Result := True;
  except
    on E: Exception do
      // The pure layer guarantees nothing was written when the backup failed.
      FStatus.SimpleText := 'Save failed, nothing changed: ' + E.Message;
  end;
end;

procedure TCurationForm.DoSplit(Sender: TObject);
var
  fi      : Integer;
  Sel     : TArray<Integer>;
  Orig    : TRuleBlocks;
  Rem, Mvd: TRuleBlocks;
  Target, Bak, Note: string;
  ErrMsg  : string;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  Target := AskTargetFile(ChangeFileExt(FSet.Item(fi).Path, '') + '-split'
    + ExtractFileExt(FSet.Item(fi).Path));
  if Target = '' then Exit;
  // Compare CANONICAL paths -- a second spelling of this same file would otherwise
  // slip past the guard and the source would be written twice, losing the blocks.
  if SameText(NormalizedPath(Target), NormalizedPath(FSet.Item(fi).Path)) then
  begin
    FStatus.SimpleText := 'Split target must be a different file.';
    Exit;
  end;
  Orig := FSet.Item(fi).Blocks;   // pre-split content, restored below if the source save fails
  SplitOut(Orig, Sel, Rem, Mvd);
  if not WriteBlocksTo(Target, Mvd, Bak, Note) then Exit;   // source untouched on failure
  FSet.SetBlocks(fi, Rem);
  if SaveSet(fi) then
  begin
    RefreshBlocks;
    FStatus.SimpleText := Format('Moved %d block(s) to %s (%s)',
      [Length(Mvd), ExtractFileName(Target), Note]);
  end
  else
  begin
    // The target above already got the moved blocks written -- a source save
    // failure here means they now exist in BOTH files, not that "nothing
    // changed". Put the in-memory model back in sync with what disk still
    // holds (the pure layer guarantees the source file itself was left
    // untouched by the failed save) rather than showing a split the source
    // never actually persisted. Preserve SaveSet's own error text too.
    ErrMsg := FStatus.SimpleText;
    FSet.SetBlocks(fi, Orig);
    RefreshBlocks;
    FStatus.SimpleText := Format('Wrote %d block(s) to %s, but %s could not be '
      + 'saved -- they now exist in BOTH files. %s',
      [Length(Mvd), ExtractFileName(Target), ExtractFileName(FSet.Item(fi).Path), ErrMsg]);
  end;
end;

procedure TCurationForm.DoCopy(Sender: TObject);
var
  fi  : Integer;
  Sel : TArray<Integer>;
  Cpy : TRuleBlocks;
  Target, Bak, Note: string;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  Target := AskTargetFile(ChangeFileExt(FSet.Item(fi).Path, '') + '-copy'
    + ExtractFileExt(FSet.Item(fi).Path));
  if Target = '' then Exit;
  Cpy := CopyOut(FSet.Item(fi).Blocks, Sel);
  if not WriteBlocksTo(Target, Cpy, Bak, Note) then Exit;
  // criterion 4: the source file is NOT written
  FStatus.SimpleText := Format('Copied %d block(s) to %s (%s; source unchanged)',
    [Length(Cpy), ExtractFileName(Target), Note]);
end;

procedure TCurationForm.DoDelete(Sender: TObject);
var
  fi : Integer;
  Sel: TArray<Integer>;
  Orig: TRuleBlocks;
  ErrMsg: string;
begin
  Sel := CheckedIndexes(fi);
  if not CanOperateOn(Sel) or (fi < 0) then Exit;
  if MessageDlg(Format('Delete %d block(s) from %s?'#13#10
    + 'A backup is written first.', [Length(Sel), ExtractFileName(FSet.Item(fi).Path)]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Orig := FSet.Item(fi).Blocks;   // restored below if the save fails
  FSet.SetBlocks(fi, DeleteBlocks(Orig, Sel));
  if SaveSet(fi) then
    RefreshBlocks
  else
  begin
    // The pure layer guarantees the file on disk was left untouched, so the model
    // must go back to matching it. Otherwise the grid shows the deletion as done
    // and a LATER successful save silently persists a deletion that was reported
    // as failed. Preserve SaveSet's own error text.
    ErrMsg := FStatus.SimpleText;
    FSet.SetBlocks(fi, Orig);
    RefreshBlocks;
    FStatus.SimpleText := ErrMsg;
  end;
end;

procedure TCurationForm.DoMerge(Sender: TObject);
var
  fi   : Integer;
  Dlg  : TOpenDialog;
  Plan : TMergePlan;
  Res  : TArray<TMergeResolution>;
  InPath: string;
  Orig : TRuleBlocks;
  ErrMsg: string;
begin
  fi := FFiles.ItemIndex;
  if fi < 0 then Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Conversion rules (*.rules)|*.rules|Cast library (*.castlib)|*.castlib|'
      + 'reFind rules (*.txt)|*.txt|All files (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then Exit;
    InPath := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  // Guard 1 -- can this TARGET be merged into at all? The reason is not grammar
  // detection, it is what a catalog block's RawText holds: SplitCastLibBlocks
  // attaches the closing 'end' line to its block, and AppendLinesToBlock appends at
  // the very END of RawText, so an incoming 'accepts TIcon' lands AFTER 'end',
  // outside the body -- and the merge report says it succeeded. This is invisible to
  // guard 2 below, because castlib -> castlib is the SAME grammar on both sides.
  // See GrammarAcceptsMerge; teaching the appender to insert before 'end' is a
  // feature, not this guard's job.
  if not GrammarAcceptsMerge(GrammarOf(FSet.Item(fi).Path)) then
  begin
    FStatus.SimpleText := Format('Merge refused: %s is a %s. Merging appends lines at'
      + ' the END of a block, which for a cast/enum block is AFTER its ''end'' line'
      + ' -- outside the body. Appending into a cast/enum block is not supported.',
      [ExtractFileName(FSet.Item(fi).Path),
       GrammarName(GrammarOf(FSet.Item(fi).Path))]);
    Exit;
  end;

  // Guard 2 -- the merger only implements the .rules grammar: it matches blocks by
  // header, so it would append every line of a reFind .txt into a .rules preamble
  // and would treat a catalog's blocks as unmatched .rules blocks. A cross-grammar
  // merge is refused, not silently mis-applied.
  if GrammarOf(InPath) <> GrammarOf(FSet.Item(fi).Path) then
  begin
    FStatus.SimpleText := Format('Merge refused: %s is a %s file but %s is a %s file'
      + ' -- merging across grammars would corrupt the target.',
      [ExtractFileName(InPath), GrammarName(GrammarOf(InPath)),
       ExtractFileName(FSet.Item(fi).Path), GrammarName(GrammarOf(FSet.Item(fi).Path))]);
    Exit;
  end;

  Plan := PlanMerge(FSet.Item(fi).Blocks,
    SplitBlocksFor(InPath, TFile.ReadAllText(InPath, TEncoding.ASCII)));

  Res := nil;
  if Plan.ConflictCount > 0 then
    // criterion 6: nothing is written until the conflicts are resolved
    if not AskResolutions(Self, Plan, ExtractFileName(InPath), Res) then
    begin
      FStatus.SimpleText := 'Merge cancelled -- nothing was written.';
      Exit;
    end;

  Orig := FSet.Item(fi).Blocks;   // restored below if the save fails
  FSet.SetBlocks(fi, ApplyMerge(Plan, Res));
  if not SaveSet(fi) then
  begin
    // Nothing reached disk, so the model must not keep the merged content: leaving
    // it would let a LATER successful save persist a merge the user was told had
    // failed and never saw a report for. Preserve SaveSet's own error text.
    ErrMsg := FStatus.SimpleText;
    FSet.SetBlocks(fi, Orig);
    RefreshBlocks;
    FStatus.SimpleText := ErrMsg;
    Exit;
  end;
  RefreshBlocks;
  ShowReport(Self, 'Merge report -- ' + ExtractFileName(InPath),
    MergeReportLines(Plan, Res, ExtractFileName(InPath)));
end;

procedure TCurationForm.DoCompose(Sender: TObject);
var
  Rep : TComposeReport;
  Text: string;
  Target, Bak: string;
  Head: TArray<string>;
begin
  if FSet.Count = 0 then Exit;
  // Compose folds the whole set with the .rules merge semantics and writes ONE
  // .rules file. A catalog in the set would have its 'cast ... end' blocks appended
  // whole (a block of another Kind never matches a #convert header), producing
  // invalid DSL for --rules. Refuse rather than emit it.
  if FSet.MixedGrammars then
  begin
    FStatus.SimpleText := 'Compose refused: the working set mixes conversion rules '
      + 'and cast catalogs. Compose writes ONE .rules file and only speaks the rules '
      + 'grammar -- remove the catalog file(s) from the set first.';
    Exit;
  end;
  // An ALL-catalog set is not "mixed", so the check above does not reach it, yet
  // Compose folds every later file INTO Item(0) with the same appending merge -- a
  // line landing after a cast block's 'end' -- and would then write the result to a
  // .rules file for --rules. Refuse on the accumulating file's grammar.
  if not GrammarAcceptsMerge(GrammarOf(FSet.Item(0).Path)) then
  begin
    FStatus.SimpleText := Format('Compose refused: %s is a %s. Compose folds the set '
      + 'into ONE .rules file by appending into the FIRST file''s blocks, which for a '
      + 'cast/enum block would land after its ''end'' line.',
      [ExtractFileName(FSet.Item(0).Path), GrammarName(GrammarOf(FSet.Item(0).Path))]);
    Exit;
  end;
  Text   := FSet.ComposeAll(Rep);
  Target := AskTargetFile(ChangeFileExt(FSet.Item(0).Path, '') + '.composed.rules');
  if Target = '' then Exit;
  try
    WriteTextWithBackup(Target, Text, Bak);
    FTouched.AddOrSetValue(TouchKey(Target), True);
    // The compose target may itself be a member of the set -- re-sync it from the
    // exact text written, or that entry keeps its pre-compose blocks and the next
    // save of it writes them back over the composed file.
    if FSet.SyncFromText(Target, Text) >= 0 then
    begin
      RefreshFiles;
      RefreshBlocks;
    end;
  except
    on E: Exception do
    begin
      FStatus.SimpleText := 'Compose failed, nothing changed: ' + E.Message;
      Exit;
    end;
  end;
  FStatus.SimpleText := Format('Composed %d file(s) into %s -- %d collision(s) '
    + 'resolved by precedence, %d block(s) appended',
    [FSet.Count, ExtractFileName(Target), Rep.ResolvedCount, Rep.AppendedCount]);
  SetLength(Head, 1);
  Head[0] := Format('%d collision(s) resolved by precedence, %d block(s) appended.'
    + ' Pass this file to --rules.', [Rep.ResolvedCount, Rep.AppendedCount]);
  ShowReport(Self, 'Compose report -- ' + ExtractFileName(Target), Head + Rep.Lines);
end;

end.
