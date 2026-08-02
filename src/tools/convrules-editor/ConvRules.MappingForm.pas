unit ConvRules.MappingForm;

{ Modal editor for ONE named #mapping -- the conditional "this enum VALUE means these
  target properties take these values" rule the plain #link grid cannot express.

  Built entirely in code (no .dfm), plain VCL, matching the rest of this editor.

  The window is deliberately THIN. Everything it knows how to do lives in
  ConvRules.Mappings: MappingCasesOf folds the flat node list into one case per enum
  member for display, BuildMappingNodes unfolds the cases back into one node per
  physical line, and ValidateMappings decides what is wrong. Severity -- which issues
  block OK and which are only shown -- is NOT decided here: MappingIssueIsWarning is
  the single source of that rule, so the window and the validator cannot drift apart. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Grids,
  ConvRules.Model, ConvRules.Engine, ConvRules.Mappings;

type
  /// <summary>The modal editor for one named #mapping.</summary>
  /// <remarks>Prefer the EditMapping class function over constructing this directly --
  /// the constructor builds an EMPTY window that knows neither the mapping's name nor
  /// the block it is validated against.</remarks>
  TMappingForm = class(TForm)
  private
    FName       : string;
    FEngine     : TEngineAdapter;        // borrowed; may be nil (members then fall back)
    FToTree     : TProptree;             // the applying block's To tree, for validation
    FBlockToType: string;                // the applying block's To class, for validation
    FSeed       : TArray<TRuleNode>;     // borrowed entry nodes; read once, never retained
    FMembers    : TArray<string>;        // source enum members as last resolved
    FCases      : TArray<TMappingCase>;  // one per FMemberList row, #else last
    FSeedSig    : string;                // canonical text at entry (see Signature)
    FLoading    : Boolean;               // suppress edit handlers while filling controls

    FEdFromType : TEdit;
    FEdToTypes  : TEdit;
    FEdWhenFrom : TEdit;
    FMemberList : TListBox;
    FGrid       : TStringGrid;
    FIssues     : TMemo;
    FStatus     : TStatusBar;
    FBtnOk      : TButton;

    procedure BuildUI;
    { Re-resolve the source enum's members and refold the cases onto them. AFromCurrent
      False reads the entry nodes (first load); True re-reads the window's own state, so
      a member list that changes under the user keeps every assignment already made. }
    procedure LoadMembers(AFromCurrent: Boolean);
    procedure RefreshMemberList;
    procedure RefreshCaseGrid;
    procedure MemberSelected(Sender: TObject);
    procedure GridEdited(Sender: TObject; ACol, ARow: Longint; const AText: string);
    procedure DoAddTarget(Sender: TObject);
    procedure DoRemoveTarget(Sender: TObject);
    procedure DoReloadMembers(Sender: TObject);
    procedure DeclChanged(Sender: TObject);
    { Index into FCases of the selected member row; -1 when nothing is selected. }
    function  CurrentCase: Integer;
    { The To-class list, split from the comma-separated edit box. }
    function  ToTypeList: TArray<string>;
    { The window's state as fresh nodes. THE CALLER OWNS THEM. }
    function  BuildNodes: TArray<TRuleNode>;
    { The canonical text of BuildNodes -- the one comparison that tells an edit from a
      look, so an untouched mapping is never rewritten (and never reformatted). }
    function  Signature: string;
    { Re-run ValidateMappings over the current state and re-gate OK. }
    procedure Revalidate;
  public
    /// <summary>Creates the (empty) window and builds its controls in code.</summary>
    /// <param name="AOwner">Owner form; also the modal parent EditMapping centres on.</param>
    constructor Create(AOwner: TComponent); override;

    /// <summary>Edit one named #mapping modally.</summary>
    /// <param name="AOwner">Owner for the modal window.</param>
    /// <param name="AName">The mapping's name. It is not editable in the window -- the
    ///   caller chose it, and renaming would orphan every #apply that names it.</param>
    /// <param name="ANodes">IN: the mapping's CURRENT nodes, borrowed and never freed
    ///   here. OUT (only when the result is True): freshly created replacement nodes for
    ///   the WHOLE mapping, which THE CALLER NOW OWNS and must free or hand to a
    ///   TRuleBook. Left untouched when the result is False.</param>
    /// <param name="AEngine">Adapter used to resolve the source enum's members. May be
    ///   nil; the member list then falls back to the values existing #when lines name.</param>
    /// <param name="AToTree">Property tree of the applying block's To class, used to
    ///   check that every target path exists and is writable. An empty tree skips those
    ///   checks rather than reporting every target as missing.</param>
    /// <param name="ABlockToType">Fully-qualified To type of the applying block, checked
    ///   against the mapping's declared targets. '' skips that check.</param>
    /// <returns>True when the user pressed OK AND the mapping actually changed. A no-op
    ///   OK returns False, so an untouched #mapping line is never rewritten and keeps
    ///   its byte-for-byte round-trip.</returns>
    /// <remarks>Errors block OK and warnings do not; both classifications come from
    ///   MappingIssueIsWarning. A missing source enum type also blocks, because without
    ///   it there is no declaration line and every #apply naming the mapping would be
    ///   undefined.</remarks>
    class function EditMapping(AOwner: TComponent; const AName: string;
      var ANodes: TArray<TRuleNode>; AEngine: TEngineAdapter; const AToTree: TProptree;
      const ABlockToType: string): Boolean;
  end;

implementation

uses
  Vcl.Graphics;

const
  { Column layout of the ToPath|Value grid. }
  COL_PATH  = 0;
  COL_VALUE = 1;

  { What the member list shows for the #else branch. Bracketed so it can never collide
    with a real identifier. }
  ELSE_ROW = '(#else)';

constructor TMappingForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BuildUI;
end;

procedure TMappingForm.BuildUI;
var
  Top   : TPanel;
  Bottom: TPanel;
  Btn   : TButton;
begin
  Caption     := 'Mapping';
  Width       := 940;
  Height      := 620;
  Position    := poOwnerFormCenter;
  BorderStyle := bsSizeable;

  Top := TPanel.Create(Self);
  Top.Parent := Self; Top.Align := alTop; Top.Height := 68; Top.BevelOuter := bvNone;

  var L: TLabel := TLabel.Create(Self);
  L.Parent := Top; L.SetBounds(8, 11, 110, 15);
  L.Caption := 'Source enum type:';
  FEdFromType := TEdit.Create(Self);
  FEdFromType.Parent := Top; FEdFromType.SetBounds(124, 8, 300, 23);
  FEdFromType.Hint := 'The enum the #when values come from, e.g. XYZ.TXYZButtonStyle';
  FEdFromType.ShowHint := True;
  FEdFromType.OnChange := DeclChanged;

  Btn := TButton.Create(Self);
  Btn.Parent := Top; Btn.SetBounds(430, 7, 110, 25);
  Btn.Caption := 'Load members';
  Btn.Hint := 'Re-resolve the source enum and refresh the member list (keeps every '
    + 'assignment already made)';
  Btn.ShowHint := True;
  Btn.OnClick := DoReloadMembers;

  L := TLabel.Create(Self);
  L.Parent := Top; L.SetBounds(556, 11, 90, 15);
  L.Caption := 'From property:';
  FEdWhenFrom := TEdit.Create(Self);
  FEdWhenFrom.Parent := Top; FEdWhenFrom.SetBounds(652, 8, 260, 23);
  FEdWhenFrom.Hint := 'The source property every #when reads, e.g. Style';
  FEdWhenFrom.ShowHint := True;
  FEdWhenFrom.OnChange := DeclChanged;

  L := TLabel.Create(Self);
  L.Parent := Top; L.SetBounds(8, 41, 110, 15);
  L.Caption := 'Target classes:';
  FEdToTypes := TEdit.Create(Self);
  FEdToTypes.Parent := Top; FEdToTypes.SetBounds(124, 38, 788, 23);
  FEdToTypes.Hint := 'Comma-separated classes this mapping may be applied to';
  FEdToTypes.ShowHint := True;
  FEdToTypes.OnChange := DeclChanged;

  // Three alBottom bands, wanted in this order top-down: issue list, button row, status
  // bar hard against the window's bottom edge. Parent ORDER does not decide that -- VCL
  // stacks same-aligned siblings by their Top at alignment time -- so each band's Top is
  // staged with an ascending sentinel BEFORE it is aligned, and the real bounds are
  // overwritten immediately afterwards. (Same trick, and same reason, as the main
  // window's toolbar PARK constant.) Left to chance the status bar lands above the
  // buttons, where it reads as a stray label rather than a status line.
  FIssues := TMemo.Create(Self);
  FIssues.Top        := 10000;
  FIssues.Parent     := Self;
  FIssues.Align      := alBottom;
  FIssues.Height     := 96;
  FIssues.ReadOnly   := True;
  FIssues.WordWrap   := False;
  FIssues.ScrollBars := ssBoth;
  FIssues.Font.Name  := 'Consolas';
  FIssues.Font.Size  := 9;

  Bottom := TPanel.Create(Self);
  Bottom.Top := 20000;
  Bottom.Parent := Self; Bottom.Align := alBottom; Bottom.Height := 36;
  Bottom.BevelOuter := bvNone;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.SetBounds(8, 5, 100, 25);
  Btn.Caption := '+ Add target'; Btn.OnClick := DoAddTarget;
  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.SetBounds(114, 5, 100, 25);
  Btn.Caption := 'Remove'; Btn.OnClick := DoRemoveTarget;

  FBtnOk := TButton.Create(Self);
  FBtnOk.Parent := Bottom; FBtnOk.SetBounds(700, 5, 90, 25);
  FBtnOk.Caption := 'OK'; FBtnOk.ModalResult := mrOk; FBtnOk.Default := True;
  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.SetBounds(798, 5, 90, 25);
  Btn.Caption := 'Cancel'; Btn.ModalResult := mrCancel; Btn.Cancel := True;

  FStatus := TStatusBar.Create(Self);
  FStatus.Top         := 30000;
  FStatus.Parent      := Self;
  FStatus.SimplePanel := True;

  FMemberList := TListBox.Create(Self);
  FMemberList.Parent  := Self;
  FMemberList.Align   := alLeft;
  FMemberList.Width   := 240;
  FMemberList.OnClick := MemberSelected;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent    := Self;
  FGrid.Align     := alClient;
  FGrid.ColCount  := 2;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount  := 2;
  FGrid.Options   := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine,
                      goColSizing, goEditing, goTabs];
  FGrid.ColWidths[COL_PATH]  := 360;
  FGrid.ColWidths[COL_VALUE] := 280;
  FGrid.Cells[COL_PATH,  0]  := 'To path';
  FGrid.Cells[COL_VALUE, 0]  := 'Value';
  FGrid.OnSetEditText := GridEdited;

  // TLabel is a TGraphicControl, so no style hook reaches it: without Transparent it
  // fills its rectangle with the light clBtnFace its parent's PROPERTY resolves to
  // while the caption is painted styled, which is white-on-white under the dark style.
  // Same sweep, and same reason, as the main window's.
  for var i := 0 to ComponentCount - 1 do
    if Components[i] is TLabel then TLabel(Components[i]).Transparent := True;
end;

function TMappingForm.CurrentCase: Integer;
begin
  Result := FMemberList.ItemIndex;
  if (Result < 0) or (Result > High(FCases)) then Result := -1;
end;

function TMappingForm.ToTypeList: TArray<string>;
var
  S   : string;
  Part: string;
begin
  Result := nil;
  for S in Trim(FEdToTypes.Text).Split([',']) do
  begin
    Part := Trim(S);
    if Part <> '' then Result := Result + [Part];
  end;
end;

function TMappingForm.BuildNodes: TArray<TRuleNode>;
begin
  Result := BuildMappingNodes(FName, Trim(FEdFromType.Text), ToTypeList,
    Trim(FEdWhenFrom.Text), FCases);
end;

function TMappingForm.Signature: string;
var
  Own: TObjectList<TRuleNode>;
  N  : TRuleNode;
  L  : TStringList;
begin
  Own := TObjectList<TRuleNode>.Create(True);
  L   := TStringList.Create;
  try
    Own.AddRange(BuildNodes);
    for N in Own do
      L.Add(N.Emit);
    Result := L.Text;
  finally
    L.Free;
    Own.Free;
  end;
end;

procedure TMappingForm.LoadMembers(AFromCurrent: Boolean);
var
  Members: TArray<string>;
  Err    : string;
  Source : TArray<TRuleNode>;
  Own    : TObjectList<TRuleNode>;
begin
  Members := nil;
  if (FEngine <> nil) and (Trim(FEdFromType.Text) <> '') then
    if not FEngine.EnumMembersOf(Trim(FEdFromType.Text), Members, Err) then
      Members := nil;

  Own := TObjectList<TRuleNode>.Create(True);
  try
    if AFromCurrent then
    begin
      // Round-tripping the window's own state through nodes is what lets the refold
      // reuse MappingCasesOf instead of a second, divergent merge rule.
      Own.AddRange(BuildNodes);
      Source := Own.ToArray;
    end
    else
      Source := FSeed;

    // Fallback: method-pointer types are not indexed at all and some enums resolve
    // ambiguously. For those the values the author already wrote are the only members
    // known -- without this the list would be EMPTY for mappings that already work.
    if Length(Members) = 0 then
      Members := MappingWhenValues(Source, FName);

    FMembers := Members;
    FCases   := MappingCasesOf(Source, FName, Members);
  finally
    Own.Free;
  end;

  RefreshMemberList;
end;

procedure TMappingForm.RefreshMemberList;
var
  Keep: Integer;
  Item: TMappingCase;
  Text: string;
begin
  Keep := FMemberList.ItemIndex;
  FMemberList.Items.BeginUpdate;
  try
    FMemberList.Items.Clear;
    for Item in FCases do
    begin
      if Item.IsElse then Text := ELSE_ROW else Text := Item.Member;
      // The count is the only cue that a member is already mapped; without it the user
      // has to click every row to find out.
      if Length(Item.Sets) > 0 then
        Text := Text + '   (' + IntToStr(Length(Item.Sets)) + ')';
      FMemberList.Items.Add(Text);
    end;
  finally
    FMemberList.Items.EndUpdate;
  end;
  if (Keep >= 0) and (Keep < FMemberList.Items.Count) then FMemberList.ItemIndex := Keep
  else if FMemberList.Items.Count > 0 then FMemberList.ItemIndex := 0;
  RefreshCaseGrid;
end;

procedure TMappingForm.RefreshCaseGrid;
var
  c, r: Integer;
begin
  FLoading := True;
  try
    c := CurrentCase;
    if c < 0 then
      FGrid.RowCount := 2
    else
      // Always one blank row past the last pair, so typing a new target needs no button.
      FGrid.RowCount := Length(FCases[c].Sets) + 2;
    for r := 1 to FGrid.RowCount - 1 do
    begin
      FGrid.Cells[COL_PATH,  r] := '';
      FGrid.Cells[COL_VALUE, r] := '';
    end;
    if c >= 0 then
      for r := 0 to High(FCases[c].Sets) do
      begin
        FGrid.Cells[COL_PATH,  r + 1] := FCases[c].Sets[r].ToPath;
        FGrid.Cells[COL_VALUE, r + 1] := FCases[c].Sets[r].Value;
      end;
  finally
    FLoading := False;
  end;
end;

{ Moving to another member is the moment the per-member counts are re-read: refreshing
  them on every keystroke would rebuild the list under the cell editor, and leaving them
  alone would show a stale count for the member just edited. RefreshMemberList restores
  the selection and refills the grid for it. }
procedure TMappingForm.MemberSelected(Sender: TObject);
begin
  RefreshMemberList;
end;

procedure TMappingForm.GridEdited(Sender: TObject; ACol, ARow: Longint;
  const AText: string);
var
  c, i: Integer;
begin
  if FLoading then Exit;
  c := CurrentCase;
  if (c < 0) or (ARow < 1) then Exit;
  i := ARow - 1;
  // The grid always shows one row past the data, so typing into it grows the case --
  // "+ Add target" is a convenience, not the only way in.
  if i >= Length(FCases[c].Sets) then
    SetLength(FCases[c].Sets, i + 1);
  if ACol = COL_PATH then FCases[c].Sets[i].ToPath := Trim(AText)
  else                    FCases[c].Sets[i].Value  := Trim(AText);
  Revalidate;
end;

procedure TMappingForm.DoAddTarget(Sender: TObject);
var
  c: Integer;
begin
  c := CurrentCase;
  if c < 0 then Exit;
  SetLength(FCases[c].Sets, Length(FCases[c].Sets) + 1);
  RefreshCaseGrid;
  FGrid.Row := Length(FCases[c].Sets);
  FGrid.Col := COL_PATH;
  Revalidate;
end;

procedure TMappingForm.DoRemoveTarget(Sender: TObject);
var
  c, i, j: Integer;
begin
  c := CurrentCase;
  if c < 0 then Exit;
  i := FGrid.Row - 1;
  if (i < 0) or (i > High(FCases[c].Sets)) then
  begin
    FStatus.SimpleText := 'Pick a target row to remove.';
    Exit;
  end;
  for j := i to High(FCases[c].Sets) - 1 do
    FCases[c].Sets[j] := FCases[c].Sets[j + 1];
  SetLength(FCases[c].Sets, Length(FCases[c].Sets) - 1);
  RefreshMemberList;
  Revalidate;
end;

procedure TMappingForm.DoReloadMembers(Sender: TObject);
begin
  LoadMembers(True);
  Revalidate;
end;

{ OnChange for the three declaration boxes. The source enum type is NOT re-resolved
  here: EnumMembersOf spawns the drag-lint exe, and doing that per keystroke would
  stall the window. "Load members" is the explicit trigger. }
procedure TMappingForm.DeclChanged(Sender: TObject);
begin
  if FLoading then Exit;
  Revalidate;
end;

procedure TMappingForm.Revalidate;
var
  Own   : TObjectList<TRuleNode>;
  Nodes : TArray<TRuleNode>;
  Issues: TArray<TMappingIssue>;
  Issue : TMappingIssue;
  Errors: Integer;
begin
  Errors := 0;
  Own := TObjectList<TRuleNode>.Create(True);
  try
    Nodes := BuildNodes;
    Own.AddRange(Nodes);
    Issues := ValidateMappings(Nodes, FToTree, FMembers, FBlockToType);

    FIssues.Lines.BeginUpdate;
    try
      FIssues.Lines.Clear;
      for Issue in Issues do
        // Severity is READ, never re-derived: MappingIssueIsWarning is the one place
        // the warning/error split is written down.
        if MappingIssueIsWarning(Issue.Kind) then
          FIssues.Lines.Add('WARNING  ' + Issue.MapName + ': ' + Issue.Detail)
        else
        begin
          Inc(Errors);
          FIssues.Lines.Add('ERROR    ' + Issue.MapName + ': ' + Issue.Detail);
        end;
      if Length(Issues) = 0 then
        FIssues.Lines.Add('No issues.');
    finally
      FIssues.Lines.EndUpdate;
    end;
  finally
    Own.Free;
  end;

  // A missing source enum type is not an issue KIND -- it means no declaration line is
  // emitted at all, so every #apply naming this mapping would be undefined. It is a
  // required field, gated here; every other block/allow decision above came from
  // MappingIssueIsWarning.
  if Trim(FEdFromType.Text) = '' then
  begin
    FBtnOk.Enabled     := False;
    FStatus.SimpleText := 'A source enum type is required before this mapping can be saved.';
    Exit;
  end;

  FBtnOk.Enabled := Errors = 0;
  if Length(Issues) = 0 then
    FStatus.SimpleText := 'No issues.'
  else
  begin
    FStatus.SimpleText := Format('%d error(s), %d warning(s).',
      [Errors, Length(Issues) - Errors]);
    // Say why OK is still available only when a warning is actually the reason.
    if (Errors = 0) and (Length(Issues) > 0) then
      FStatus.SimpleText := FStatus.SimpleText + ' Warnings do not block OK.';
  end;
end;

class function TMappingForm.EditMapping(AOwner: TComponent; const AName: string;
  var ANodes: TArray<TRuleNode>; AEngine: TEngineAdapter; const AToTree: TProptree;
  const ABlockToType: string): Boolean;
var
  F   : TMappingForm;
  Decl: TRuleNode;
begin
  Result := False;
  F := TMappingForm.Create(AOwner);
  try
    F.FName        := AName;
    F.FEngine      := AEngine;
    F.FToTree      := AToTree;
    F.FBlockToType := ABlockToType;
    F.FSeed        := ANodes;
    F.Caption      := 'Mapping -- ' + AName;

    F.FLoading := True;
    try
      Decl := MappingDeclaration(ANodes, AName);
      if Decl <> nil then
      begin
        F.FEdFromType.Text := Decl.MapFromType;
        F.FEdToTypes.Text  := string.Join(', ', Decl.MapToTypes);
      end
      else if ABlockToType <> '' then
        // A brand-new mapping is being authored from inside a block; that block's To
        // class is the only target we can honestly guess, and guessing it wrong is
        // reported by mikToTypeNotDeclared rather than hidden.
        F.FEdToTypes.Text := ABlockToType;
      F.FEdWhenFrom.Text := MappingWhenFrom(ANodes, AName);
    finally
      F.FLoading := False;
    end;

    F.LoadMembers(False);
    F.FSeedSig := F.Signature;
    F.Revalidate;

    if (F.ShowModal = mrOk) and (F.Signature <> F.FSeedSig) then
    begin
      ANodes := F.BuildNodes;   // ownership passes to the caller
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

end.
