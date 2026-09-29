unit ConvRules.UnitPicker;

{ Modal unit-name picker, used wherever the editor asks for a unit name
  (+ Use / + Unuse / + Swap on the Unit Rules tab, and the From Unit box).

  One name edit, one search field with a Wildcard / Regex switch, and two lists:
  project units on the left, the side's platform library on the right. Typing in
  either field narrows both lists after a short debounce. Double-click, Enter or
  Space on a list item returns that name; OK (or Enter in the name edit) returns
  the edit's text, so a unit that is not indexed yet can still be typed in.

  ExecuteMulti is the replacement picker behind #useswap: there a double-click,
  Enter or Space ADDS the unit to a Replacements list shown under the lists, with
  no confirmation, and OK returns the whole list. A chosen entry is removed by
  double-clicking it (or Delete).

  Every decision the form makes -- the filters, which library a platform shows,
  the "not in the Win64 library" note -- lives in ConvRules.UnitPick, which the
  model-test runner covers; this unit only renders and dispatches.

  VCL, code-built (no .dfm), on the create/ShowModal/free shape
  ConvRules.RuleChooser.pas uses. }

interface

uses
  System.SysUtils
  , System.Classes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , ConvRules.Platform
  , ConvRules.UnitPick
  ;

type
  /// <summary>Which side of a conversion the unit is being picked for. It
  /// selects the platform whose library the right-hand list shows.</summary>
  TUnitPickSide = (psFrom, psTo);

  /// <summary>Everything the picker lists. The caller loads and caches the
  /// lists (they come from the engine, several seconds per library); a list the
  /// chosen side's platform does not need may be left empty.</summary>
  TUnitPickSource = record
    /// <summary>Units of the project index.</summary>
    ProjectUnits: TArray<string>;
    /// <summary>Units of the Win32 library index.</summary>
    Win32Units  : TArray<string>;
    /// <summary>Units of the Win64 library index.</summary>
    Win64Units  : TArray<string>;
    /// <summary>The editor's FROM platform, shown in the header.</summary>
    FromPlatform: TConvPlatform;
    /// <summary>The editor's TO platform, shown in the header.</summary>
    ToPlatform  : TConvPlatform;
  end;

  /// <summary>The modal unit picker. Use Execute; do not create it directly.</summary>
  TUnitPickerForm = class(TForm)  // dl:ok god-class@1d00, high-response@1d00 -- REVIEWED 2026-09-24 a code-built modal form: the count is its control fields and event handlers; every decision it makes lives in ConvRules.UnitPick
    private
      FEdit     : TEdit         ;
      FSearch   : TEdit         ;
      FMode     : TComboBox     ;
      FLblPlat  : TLabel        ;
      FLblProj  : TLabel        ;
      FLblLib   : TLabel        ;
      FLblNote  : TLabel        ;
      FLeft     : TPanel        ;
      FLbProj   : TListBox      ;
      FLbLib    : TListBox      ;
      FTimer    : TTimer        ;
      FProj     : TArray<string>;
      FLib      : TArray<string>;
      FProjShown: TArray<string>;
      FLibShown : TArray<string>;
      FWin32    : TArray<string>;
      FWin64    : TArray<string>;
      FSidePlat : TConvPlatform ;
      FSilent   : Integer       ;
      FResult   : string        ;
      FMulti    : Boolean       ;
      FExclude  : string        ;
      FChosen   : TArray<string>;
      FChosenPnl: TPanel        ;
      FLbChosen : TListBox      ;
      procedure BuildUI;
      procedure BuildTop;
      procedure BuildLists;
      procedure BuildBottom;
      procedure Load(const ASource: TUnitPickSource; ASide: TUnitPickSide);
      procedure ApplyFilter;
      procedure RestartTimer(Sender: TObject);
      procedure TimerFired(Sender: TObject);
      procedure ProjData(Control: TWinControl; Index: Integer; var Data: string);
      procedure LibData(Control: TWinControl; Index: Integer; var Data: string);
      procedure ListClick(Sender: TObject);
      procedure ListDblClick(Sender: TObject);
      procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure ListKeyPress(Sender: TObject; var Key: Char);
      procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure EditKeyPress(Sender: TObject; var Key: Char);
      procedure OkClick(Sender: TObject);
      procedure FormResized(Sender: TObject);
      function ShownOf(AList: TListBox): TArray<string>;
      function CurrentFilter: TUnitFilter;
      procedure SetEditSilently(const AText: string);
      procedure ShowNote(const AUnit: string);
      procedure AcceptList(AList: TListBox);
      procedure AcceptEdit;
      procedure AddChosen(const AUnit: string);
      procedure ShowChosen;
      procedure RemoveChosen;
      procedure ChosenDblClick(Sender: TObject);
      procedure ChosenKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    public
      /// <summary>Creates the form. Prefer Execute over calling this directly.</summary>
      /// <param name="AOwner">Owning component.</param>
      constructor Create(AOwner: TComponent); override;
      /// <summary>Shows the modal picker and returns the chosen unit name.</summary>
      /// <param name="AOwner">Owning component (the form is centred on it).</param>
      /// <param name="ACaption">Window caption, e.g. 'Add unit (#use)'.</param>
      /// <param name="AInitial">Pre-filled name; it also pre-filters the lists.</param>
      /// <param name="ASide">Which platform's library the right list shows.</param>
      /// <param name="ASource">The lists to show; see TUnitPickSource.</param>
      /// <param name="AUnit">Receives the chosen name, trimmed; '' on cancel.</param>
      /// <returns>True when a non-empty name was accepted; False on Cancel / Esc.</returns>
      class function Execute(AOwner: TComponent; const ACaption, AInitial: string; ASide: TUnitPickSide; const ASource: TUnitPickSource; out AUnit: string): Boolean;
      /// <summary>Shows the modal picker in REPLACEMENT mode and returns every unit
      /// the user added: a double-click, Enter or Space on a list item adds it to the
      /// Replacements list without asking; OK also adds a name typed in the edit.</summary>
      /// <param name="AOwner">Owning component (the form is centred on it).</param>
      /// <param name="ACaption">Window caption, e.g. 'Replacements for Forms'.</param>
      /// <param name="AExclude">The OLD unit being replaced; it is never accepted as
      /// one of its own replacements (see AddPickedUnit).</param>
      /// <param name="ASide">Which platform's library the right list shows.</param>
      /// <param name="ASource">The lists to show; see TUnitPickSource.</param>
      /// <param name="AUnits">Receives the chosen names in pick order; nil on cancel.</param>
      /// <returns>True when OK was pressed with at least one unit chosen; False on
      /// Cancel / Esc.</returns>
      class function ExecuteMulti(AOwner: TComponent; const ACaption, AExclude: string; ASide: TUnitPickSide; const ASource: TUnitPickSource; out AUnits: TArray<string>): Boolean;
  end;

implementation

uses
  System.StrUtils
  , System.Math
  , Winapi.Windows
  ;

const
  FORM_WIDTH  = 760;
  FORM_HEIGHT = 540;
  TOP_H       = 96 ;
  BOTTOM_H    = 64 ;
  CHOSEN_H    = 120;
  MARGIN      = 8  ;
  LBL_W       = 56 ;
  FIELD_X     = MARGIN + LBL_W + MARGIN;
  ROW_PLAT_Y  = 8  ;
  ROW_EDIT_Y  = 32 ;
  ROW_SRCH_Y  = 62 ;
  LBL_DY      = 3  ;
  LBL_H       = 15 ;
  FIELD_H     = 23 ;
  MODE_W      = 150;
  BTN_W       = 90 ;
  BTN_H       = 25 ;
  BTN_TOP     = 30 ;
  NOTE_TOP    = 6  ;
  HALF        = 2  ;
  DEBOUNCE_MS = 250;
  MODE_WILDCARD_CAPTION = 'Wildcard (cx*)';
  MODE_REGEX_CAPTION    = 'Regex';

{ Display name for a platform in the header line. }
function PlatName(APlatform: TConvPlatform): string;
begin
  case APlatform of
    cpWin32: Result:= 'Win32';
    cpWin64: Result:= 'Win64';
    else
      Result:= 'Win32+Win64';
  end;
end;

constructor TUnitPickerForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BuildUI;
end;

procedure TUnitPickerForm.BuildUI;
begin
  Width      := FORM_WIDTH;
  Height     := FORM_HEIGHT;
  Position   := poOwnerFormCenter;
  BorderStyle:= bsSizeable;
  OnResize   := FormResized;

  FTimer:= TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval:= DEBOUNCE_MS;
  FTimer.OnTimer := TimerFired;

  BuildTop;
  BuildBottom;
  BuildLists;
end; // procedure

procedure TUnitPickerForm.BuildTop;
var
  Pnl    : TPanel;
  LblUnit: TLabel;
  LblSrch: TLabel;
begin
  Pnl:= TPanel.Create(Self);
  Pnl.Parent    := Self;
  Pnl.Align     := alTop;
  Pnl.Height    := TOP_H;
  Pnl.BevelOuter:= bvNone;

  FLblPlat:= TLabel.Create(Self);
  FLblPlat.Parent:= Pnl;
  FLblPlat.SetBounds(MARGIN, ROW_PLAT_Y, FORM_WIDTH - HALF * MARGIN, LBL_H);

  LblUnit:= TLabel.Create(Self);
  LblUnit.Parent := Pnl;
  LblUnit.SetBounds(MARGIN, ROW_EDIT_Y + LBL_DY, LBL_W, LBL_H);
  LblUnit.Caption:= 'Unit:';

  FEdit:= TEdit.Create(Self);
  FEdit.Parent    := Pnl;
  FEdit.SetBounds(FIELD_X, ROW_EDIT_Y, Pnl.Width - FIELD_X - MARGIN, FIELD_H);
  FEdit.Anchors   := [akLeft, akTop, akRight];
  FEdit.Hint      := 'The unit name. Typing narrows both lists (any part of the name, any case).';
  FEdit.ShowHint  := True;
  FEdit.OnChange  := RestartTimer;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnKeyPress:= EditKeyPress;

  LblSrch:= TLabel.Create(Self);
  LblSrch.Parent := Pnl;
  LblSrch.SetBounds(MARGIN, ROW_SRCH_Y + LBL_DY, LBL_W, LBL_H);
  LblSrch.Caption:= 'Search:';

  FSearch:= TEdit.Create(Self);
  FSearch.Parent  := Pnl;
  FSearch.SetBounds(FIELD_X, ROW_SRCH_Y, Pnl.Width - FIELD_X - MODE_W - HALF * MARGIN, FIELD_H);
  FSearch.Anchors := [akLeft, akTop, akRight];
  FSearch.Hint    := 'Narrows the lists further: a file-style mask (cx*, *Grid*) or a regular expression.';
  FSearch.ShowHint:= True;
  FSearch.OnChange:= RestartTimer;

  FMode:= TComboBox.Create(Self);
  FMode.Parent  := Pnl;
  FMode.SetBounds(Pnl.Width - MODE_W - MARGIN, ROW_SRCH_Y, MODE_W, FIELD_H);
  FMode.Anchors := [akTop, akRight];
  FMode.Style   := csDropDownList;
  // Item order matches TUnitSearchMode by ordinal (usmWildcard, usmRegex).
  FMode.Items.Add(MODE_WILDCARD_CAPTION);
  FMode.Items.Add(MODE_REGEX_CAPTION);
  FMode.ItemIndex:= Ord(usmWildcard);
  FMode.OnChange := RestartTimer;
end; // procedure

procedure TUnitPickerForm.BuildLists;
var
  Right: TPanel;
begin
  FLeft:= TPanel.Create(Self);
  FLeft.Parent    := Self;
  FLeft.Align     := alLeft;
  FLeft.Width     := ClientWidth div HALF;
  FLeft.BevelOuter:= bvNone;

  FLblProj:= TLabel.Create(Self);
  FLblProj.Parent:= FLeft;
  FLblProj.Align := alTop;

  FLbProj:= TListBox.Create(Self);
  FLbProj.Parent    := FLeft;
  FLbProj.Align     := alClient;
  FLbProj.Style     := lbVirtual;
  FLbProj.OnData    := ProjData;
  FLbProj.OnClick   := ListClick;
  FLbProj.OnDblClick:= ListDblClick;
  FLbProj.OnKeyDown := ListKeyDown;
  FLbProj.OnKeyPress:= ListKeyPress;

  Right:= TPanel.Create(Self);
  Right.Parent    := Self;
  Right.Align     := alClient;
  Right.BevelOuter:= bvNone;

  FLblLib:= TLabel.Create(Self);
  FLblLib.Parent:= Right;
  FLblLib.Align := alTop;

  FLbLib:= TListBox.Create(Self);
  FLbLib.Parent    := Right;
  FLbLib.Align     := alClient;
  FLbLib.Style     := lbVirtual;
  FLbLib.OnData    := LibData;
  FLbLib.OnClick   := ListClick;
  FLbLib.OnDblClick:= ListDblClick;
  FLbLib.OnKeyDown := ListKeyDown;
  FLbLib.OnKeyPress:= ListKeyPress;
end; // procedure

procedure TUnitPickerForm.BuildBottom;
var
  Btm      : TPanel ;
  BtnOk    : TButton;
  BtnCancel: TButton;
  LblChosen: TLabel ;
begin
  Btm:= TPanel.Create(Self);
  Btm.Parent    := Self;
  Btm.Align     := alBottom;
  Btm.Height    := BOTTOM_H;
  Btm.BevelOuter:= bvNone;

  FLblNote:= TLabel.Create(Self);
  FLblNote.Parent:= Btm;
  FLblNote.SetBounds(MARGIN, NOTE_TOP, Btm.Width - HALF * MARGIN, LBL_H);
  FLblNote.Anchors:= [akLeft, akTop, akRight];

  // OK is deliberately NOT Default: a Default button would swallow Enter in the
  // lists, where Enter must accept the highlighted ITEM, not the edit's text.
  BtnOk:= TButton.Create(Self);
  BtnOk.Parent := Btm;
  BtnOk.SetBounds(Btm.Width - HALF * (BTN_W + MARGIN), BTN_TOP, BTN_W, BTN_H);
  BtnOk.Anchors:= [akTop, akRight];
  BtnOk.Caption:= 'OK';
  BtnOk.OnClick:= OkClick;

  BtnCancel:= TButton.Create(Self);
  BtnCancel.Parent     := Btm;
  BtnCancel.SetBounds(Btm.Width - BTN_W - MARGIN, BTN_TOP, BTN_W, BTN_H);
  BtnCancel.Anchors    := [akTop, akRight];
  BtnCancel.Caption    := 'Cancel';
  BtnCancel.Cancel     := True;
  BtnCancel.ModalResult:= mrCancel;

  // The Replacements list: hidden in single mode, shown by ExecuteMulti above the
  // button row (created after Btm, so alBottom stacks it on top of Btm).
  FChosenPnl:= TPanel.Create(Self);
  FChosenPnl.Parent    := Self;
  FChosenPnl.Align     := alBottom;
  FChosenPnl.Height    := CHOSEN_H;
  FChosenPnl.BevelOuter:= bvNone;
  FChosenPnl.Visible   := False;

  LblChosen:= TLabel.Create(Self);
  LblChosen.Parent := FChosenPnl;
  LblChosen.Align  := alTop;
  LblChosen.Caption:= 'Replacements -- double-click a unit in the lists above to add it; double-click (or Delete) one here to remove it:';

  FLbChosen:= TListBox.Create(Self);
  FLbChosen.Parent    := FChosenPnl;
  FLbChosen.Align     := alClient;
  FLbChosen.OnDblClick:= ChosenDblClick;
  FLbChosen.OnKeyDown := ChosenKeyDown;
end; // procedure

procedure TUnitPickerForm.Load(const ASource: TUnitPickSource; ASide: TUnitPickSide);
var
  SideName: string;
begin
  FWin32:= ASource.Win32Units;
  FWin64:= ASource.Win64Units;
  FProj := ASource.ProjectUnits;
  if ASide = psFrom then
  begin
    FSidePlat:= ASource.FromPlatform;
    SideName := 'FROM';
  end
  else
  begin
    FSidePlat:= ASource.ToPlatform;
    SideName := 'TO';
  end;
  FLib:= LibraryUnitsFor(FSidePlat, FWin32, FWin64);
  FLblPlat.Caption:= Format('FROM: %s     TO: %s     --     picking a %s unit: the library list is %s',
    [PlatName(ASource.FromPlatform), PlatName(ASource.ToPlatform), SideName, PlatName(FSidePlat)]);
end; // procedure

function TUnitPickerForm.CurrentFilter: TUnitFilter;
begin
  Result.NameText:= Trim(FEdit.Text);
  Result.Search  := Trim(FSearch.Text);
  Result.Mode    := TUnitSearchMode(FMode.ItemIndex);
end;

procedure TUnitPickerForm.ApplyFilter;
var
  F: TUnitFilter;
begin
  FTimer.Enabled:= False;
  F:= CurrentFilter;
  FProjShown:= FilterUnits(FProj, F);
  FLibShown := FilterUnits(FLib , F);
  // Count reset also clears the selection: a filtered list must not keep
  // pointing at an index that now names a different unit.
  FLbProj.Count:= Length(FProjShown);
  FLbLib .Count:= Length(FLibShown );
  FLbProj.ItemIndex:= -1;
  FLbLib .ItemIndex:= -1;
  FLblProj.Caption:= Format('Project units (%d of %d)', [Length(FProjShown), Length(FProj)]);
  FLblLib .Caption:= Format('%s library units (%d of %d)', [PlatName(FSidePlat), Length(FLibShown), Length(FLib)]);
  ShowNote('');
end; // procedure

procedure TUnitPickerForm.RestartTimer(Sender: TObject);
begin
  if FSilent > 0 then
    Exit;
  FTimer.Enabled:= False;
  FTimer.Enabled:= True;
end;

procedure TUnitPickerForm.TimerFired(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TUnitPickerForm.ProjData(Control: TWinControl; Index: Integer; var Data: string);
begin
  Data:= FProjShown[Index];
end;

procedure TUnitPickerForm.LibData(Control: TWinControl; Index: Integer; var Data: string);
begin
  Data:= FLibShown[Index];
end;

function TUnitPickerForm.ShownOf(AList: TListBox): TArray<string>;
begin
  if AList = FLbProj then
    Result:= FProjShown
  else
    Result:= FLibShown;
end;

procedure TUnitPickerForm.SetEditSilently(const AText: string);
begin
  // Copying a picked name into the edit must not re-filter: the lists would
  // collapse to that one name under the user's cursor.
  Inc(FSilent);
  try
    FEdit.Text:= AText;
  finally
    Dec(FSilent);
  end; // try
end;

procedure TUnitPickerForm.ShowNote(const AUnit: string);
var
  F    : TUnitFilter;
  Parts: TArray<string>;
begin
  Parts:= nil;
  F:= CurrentFilter;
  if not IsValidUnitSearch(F.Search, F.Mode) then
    Parts:= Parts + ['Search: not a valid ' + IfThen(F.Mode = usmRegex, 'regular expression', 'mask') + ' -- ignored.'];
  // Only a side on BOTH platforms can pick a unit one of them lacks.
  if (AUnit <> '') and (FSidePlat = cpBoth) then
    Parts:= Parts + [PlatformGapNote(AUnit, FWin32, FWin64)];
  FLblNote.Caption:= Trim(string.Join('   ', Parts));
end;

procedure TUnitPickerForm.ListClick(Sender: TObject);
var
  LB   : TListBox;
  Other: TListBox;
  UnitName : string  ;
begin
  LB:= Sender as TListBox;
  if LB.ItemIndex < 0 then
    Exit;
  Other:= FLbLib;
  if LB = FLbLib then
    Other:= FLbProj;
  Other.ItemIndex:= -1; // one selection across both lists
  UnitName:= ShownOf(LB)[LB.ItemIndex];
  SetEditSilently(UnitName);
  ShowNote(UnitName);
end;

procedure TUnitPickerForm.ListDblClick(Sender: TObject);
begin
  AcceptList(Sender as TListBox);
end;

procedure TUnitPickerForm.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) or (Key = VK_SPACE) then
  begin
    Key:= 0;
    AcceptList(Sender as TListBox);
  end;
end;

procedure TUnitPickerForm.ListKeyPress(Sender: TObject; var Key: Char);
begin
  // Enter and Space are handled in ListKeyDown; eat their chars so the list's
  // incremental search does not also jump on them.
  if (Key = #13) or (Key = ' ') then
    Key:= #0;
end;

procedure TUnitPickerForm.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Target: TListBox;
begin
  if Key = VK_RETURN then
  begin
    Key:= 0;
    AcceptEdit;
  end
  else if Key = VK_DOWN then
  begin
    Key:= 0;
    if FTimer.Enabled then
      ApplyFilter; // a pending re-filter must land before the lists are entered
    Target:= FLbProj;
    if FLbProj.Count = 0 then
      Target:= FLbLib;
    if Target.Count = 0 then
      Exit;
    Target.SetFocus;
    Target.ItemIndex:= 0;
    ListClick(Target);
  end;
end;

procedure TUnitPickerForm.EditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
    Key:= #0; // handled in EditKeyDown; stops the edit's beep
end;

procedure TUnitPickerForm.OkClick(Sender: TObject);
begin
  if not FMulti then
  begin
    AcceptEdit;
    Exit;
  end;
  // A name typed (or single-clicked) but not yet added still counts on OK.
  FChosen:= AddPickedUnit(FChosen, FEdit.Text, FExclude);
  ShowChosen;
  if Length(FChosen) = 0 then
  begin
    FLblNote.Caption:= 'Pick at least one replacement: double-click a unit in the lists.';
    Exit;
  end;
  ModalResult:= mrOk;
end;

procedure TUnitPickerForm.FormResized(Sender: TObject);
begin
  if FLeft <> nil then
    FLeft.Width:= ClientWidth div HALF;
end;

procedure TUnitPickerForm.AcceptList(AList: TListBox);
begin
  if AList.ItemIndex < 0 then
    Exit;
  if FMulti then
  begin
    AddChosen(ShownOf(AList)[AList.ItemIndex]);
    Exit;
  end;
  SetEditSilently(ShownOf(AList)[AList.ItemIndex]);
  AcceptEdit;
end;

procedure TUnitPickerForm.AcceptEdit;
begin
  if FMulti then
  begin
    // Enter in the edit adds what was typed; on an empty edit it finishes.
    if Trim(FEdit.Text) = '' then
      OkClick(nil)
    else
      AddChosen(FEdit.Text);
    Exit;
  end;
  FResult:= Trim(FEdit.Text);
  if FResult = '' then
  begin
    FLblNote.Caption:= 'Type a unit name, or pick one from a list.';
    Exit;
  end;
  ModalResult:= mrOk;
end;

class function TUnitPickerForm.Execute(AOwner: TComponent; const ACaption, AInitial: string; ASide: TUnitPickSide; const ASource: TUnitPickSource; out AUnit: string): Boolean;
var
  F: TUnitPickerForm;
begin
  AUnit:= '';
  F:= TUnitPickerForm.Create(AOwner);
  try
    F.Caption:= ACaption;
    F.Load(ASource, ASide);
    F.SetEditSilently(AInitial);
    F.ApplyFilter;
    F.ActiveControl:= F.FEdit;
    F.FEdit.SelectAll;
    Result:= F.ShowModal = mrOk;
    if Result then
      AUnit:= F.FResult;
  finally
    F.Free;
  end; // try
end; // function

procedure TUnitPickerForm.AddChosen(const AUnit: string);
var
  Before: Integer;
begin
  Before := Length(FChosen);
  FChosen:= AddPickedUnit(FChosen, AUnit, FExclude);
  if Length(FChosen) > Before then
  begin
    ShowChosen;
    SetEditSilently('');
    FLblNote.Caption:= Format('%s added.', [Trim(AUnit)]);
  end
  else if SameText(Trim(AUnit), Trim(FExclude)) then
    FLblNote.Caption:= Format('%s is the unit being replaced.', [Trim(AUnit)])
  else if Trim(AUnit) <> '' then
    FLblNote.Caption:= Format('%s is already a replacement.', [Trim(AUnit)]);
end;

procedure TUnitPickerForm.ShowChosen;
begin
  FLbChosen.Items.BeginUpdate;
  try
    FLbChosen.Items.Clear;
    for var LUnit: string in FChosen do
      FLbChosen.Items.Add(LUnit);
  finally
    FLbChosen.Items.EndUpdate;
  end; // try
end;

procedure TUnitPickerForm.RemoveChosen;
var
  Idx: Integer;
begin
  Idx:= FLbChosen.ItemIndex;
  if (Idx < 0) or (Idx > High(FChosen)) then
    Exit;
  Delete(FChosen, Idx, 1);
  ShowChosen;
  if FLbChosen.Count > 0 then
    FLbChosen.ItemIndex:= Min(Idx, FLbChosen.Count - 1);
end;

procedure TUnitPickerForm.ChosenDblClick(Sender: TObject);
begin
  RemoveChosen;
end;

procedure TUnitPickerForm.ChosenKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_DELETE then
  begin
    Key:= 0;
    RemoveChosen;
  end;
end;

class function TUnitPickerForm.ExecuteMulti(AOwner: TComponent; const ACaption, AExclude: string; ASide: TUnitPickSide; const ASource: TUnitPickSource; out AUnits: TArray<string>): Boolean;
var
  F: TUnitPickerForm;
begin
  AUnits:= nil;
  F:= TUnitPickerForm.Create(AOwner);
  try
    F.FMulti  := True;
    F.FExclude:= AExclude;
    F.Caption := ACaption;
    // alBottom stacks by Top: 0 puts the Replacements panel ABOVE the button row.
    F.FChosenPnl.Top    := 0;
    F.FChosenPnl.Visible:= True;
    F.Load(ASource, ASide);
    F.ApplyFilter;
    F.ActiveControl:= F.FEdit;
    Result:= F.ShowModal = mrOk;
    if Result then
      AUnits:= F.FChosen;
  finally
    F.Free;
  end; // try
end; // function

end.
