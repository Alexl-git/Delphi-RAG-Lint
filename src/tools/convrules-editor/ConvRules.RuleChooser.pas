unit ConvRules.RuleChooser;

{ Modal "which rule did you mean" picker.

  FormTypeDblClick (ConvRules.MainForm.pas) opens this when RulesForType
  (ConvRules.RuleCatalog.pas) finds MORE than one rule converting the double-
  clicked From class -- legitimately possible, since the same From class may be
  converted differently in different rule books for different campaigns. The
  picker lists every match so the user can OPEN the one they meant, or say none
  of these is it and ADD another conversion for the same From class -- the
  requirement (R3.5) a single-ruled class reaches through the "+ Add rule for
  this class" button on the main form instead, since with exactly one match this
  picker never opens.

  VCL, code-built (no .dfm), on the create/ShowModal/free shape
  ConvRules.CurationForm.pas's TCurationForm.Execute uses. }

interface

uses
  System.SysUtils
  , System.Classes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , ConvRules.RuleCatalog
  ;

type
  /// <summary>What the user did in the rule chooser.</summary>
  /// <remarks>
  /// crOpen means the Execute out param was set to the row the user picked.
  /// For crCancel and crNew that out param is left at its Default(...) value --
  /// the caller must not read it for either.
  /// </remarks>
  TChooserResult = (crCancel, crOpen, crNew);

  /// <summary>Modal picker over the several rules RulesForType found for one
  /// From class.</summary>
  /// <remarks>
  /// Columns are To / % / File, matching the convention the main form's own
  /// FRules list uses (To / %) plus File, since a chooser exists precisely
  /// because more than one BOOK may be involved. The % column is left blank: an
  /// entry may live in a book that is not the one currently open, and computing
  /// completion would mean loading each candidate book just to paint a list --
  /// out of scope for the selection contract this picker exists to provide.
  /// </remarks>
  TRuleChooserForm = class(TForm)
    private
      FList   : TListView             ;
      FEntries: TArray<TRuleCatalogEntry>;
      FResult : TChooserResult        ;
      procedure BuildUI;
      procedure PopulateList(const AType: string);
      procedure DoOpen(Sender: TObject);
      procedure DoNew(Sender: TObject);
    public
      /// <summary>Creates the form. Prefer Execute over calling this directly.</summary>
      /// <param name="AOwner">Owning component.</param>
      constructor Create(AOwner: TComponent); override;
      /// <summary>Shows the modal picker over AEntries.</summary>
      /// <param name="AOwner">Owning component.</param>
      /// <param name="AType">The From class being chosen for; shown in the caption.</param>
      /// <param name="AEntries">The candidate rules, as RulesForType returns them;
      /// one row per entry, in the order given.</param>
      /// <param name="AEntry">Receives the chosen entry when the result is crOpen;
      /// left at Default(TRuleCatalogEntry) for crCancel and crNew.</param>
      /// <returns>crOpen with AEntry set, crNew, or crCancel.</returns>
      class function Execute(AOwner: TComponent; const AType: string; const AEntries: TArray<TRuleCatalogEntry>; out AEntry: TRuleCatalogEntry): TChooserResult;
  end;

implementation

const
  FORM_WIDTH   = 560;
  FORM_HEIGHT  = 320;
  BTN_BAR_H    = 40 ;
  BTN_MARGIN   = 8  ;
  BTN_TOP      = 6  ;
  BTN_H        = 25 ;
  BTN_OPEN_W   = 90 ;
  BTN_NEW_W    = 160;
  BTN_CANCEL_W = 90 ;
  BTN_GAP      = 8  ;
  COL_TO_W     = 180;
  COL_PCT_W    = 50 ;
  COL_FILE_W   = 260;

constructor TRuleChooserForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FResult:= crCancel;
  BuildUI;
end;

procedure TRuleChooserForm.BuildUI;
var
  Btm     : TPanel ;
  BtnOpen : TButton;
  BtnNew  : TButton;
  BtnClose: TButton;
  X       : Integer;
begin
  Caption    := 'Choose a rule';
  Width      := FORM_WIDTH;
  Height     := FORM_HEIGHT;
  Position   := poOwnerFormCenter;
  BorderStyle:= bsSizeable;

  Btm:= TPanel.Create(Self);
  Btm.Parent    := Self;
  Btm.Align     := alBottom;
  Btm.Height    := BTN_BAR_H;
  Btm.BevelOuter:= bvNone;

  X:= BTN_MARGIN;
  BtnOpen:= TButton.Create(Self);
  BtnOpen.Parent:= Btm;
  BtnOpen.SetBounds(X, BTN_TOP, BTN_OPEN_W, BTN_H);
  BtnOpen.Caption:= 'Open';
  BtnOpen.Default:= True;
  BtnOpen.OnClick:= DoOpen;

  X:= X + BTN_OPEN_W + BTN_GAP;
  BtnNew:= TButton.Create(Self);
  BtnNew.Parent:= Btm;
  BtnNew.SetBounds(X, BTN_TOP, BTN_NEW_W, BTN_H);
  BtnNew.Caption:= 'Add a new rule...';
  BtnNew.OnClick:= DoNew;

  X:= X + BTN_NEW_W + BTN_GAP;
  BtnClose:= TButton.Create(Self);
  BtnClose.Parent:= Btm;
  BtnClose.SetBounds(X, BTN_TOP, BTN_CANCEL_W, BTN_H);
  BtnClose.Caption    := 'Cancel';
  BtnClose.ModalResult:= mrCancel;
  BtnClose.Cancel     := True;

  FList:= TListView.Create(Self);
  FList.Parent:= Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly  := True;
  FList.OnDblClick:= DoOpen;
  FList.Columns.Add.Caption:= 'To';
  FList.Columns[0].Width   := COL_TO_W;
  FList.Columns.Add.Caption:= '%';
  FList.Columns[1].Width   := COL_PCT_W;
  FList.Columns.Add.Caption:= 'File';
  FList.Columns[2].Width   := COL_FILE_W;
end; // procedure

procedure TRuleChooserForm.PopulateList(const AType: string);
var
  i  : Integer  ;
  Row: TListItem;
begin
  Caption:= Format('%d rules convert %s -- pick one, or add another', [Length(FEntries), AType]);
  FList.Items.Clear;
  for i:= 0 to High(FEntries) do
  begin
    Row:= FList.Items.Add;
    Row.Caption:= FEntries[i].ToType;
    Row.SubItems.Add(''); // % -- see the type's remarks: no per-entry figure without opening the book
    Row.SubItems.Add(ExtractFileName(FEntries[i].FilePath));
  end; // for
  if FList.Items.Count > 0 then
    FList.ItemIndex:= 0;
end; // procedure

procedure TRuleChooserForm.DoOpen(Sender: TObject);
begin
  if FList.ItemIndex < 0 then
    Exit;
  FResult:= crOpen;
  ModalResult:= mrOk;
end; // procedure

procedure TRuleChooserForm.DoNew(Sender: TObject);
begin
  FResult:= crNew;
  ModalResult:= mrOk;
end; // procedure

class function TRuleChooserForm.Execute(AOwner: TComponent; const AType: string; const AEntries: TArray<TRuleCatalogEntry>; out AEntry: TRuleCatalogEntry): TChooserResult;
var
  F: TRuleChooserForm;
begin
  AEntry:= Default(TRuleCatalogEntry);
  F:= TRuleChooserForm.Create(AOwner);
  try
    F.FEntries:= AEntries;
    F.PopulateList(AType);
    F.ShowModal;
    Result:= F.FResult;
    if (Result = crOpen) and (F.FList.ItemIndex >= 0) then
      AEntry:= F.FEntries[F.FList.ItemIndex];
  finally
    F.Free;
  end; // try
end; // function

end.
