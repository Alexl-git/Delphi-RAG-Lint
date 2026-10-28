unit ConvRules.ChainForm;

{ CHAIN-1: the Rule chains dialog. Lists the findings of ConvRules.RuleChains for the
  open book, fixable ones checked, and returns which button was pressed and which rows
  were checked. Editor-only and code-built (no .dfm): it decides nothing and never
  touches a book -- the button gates are CanMergeAll / CanSplitAll, pinned in the model
  tests; the caller (ConvRules.MainForm) runs Merge or Split. }

interface

uses
  System.Classes
  , System.UITypes // TModalResult
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ComCtrls
  , ConvRules.RuleChains
  ;

type
  /// <summary>The Rule chains dialog (spec 5.3 O1, O2, O4).</summary>
  /// <remarks>Controls carry stable names for the GUI driver: LvChains (vsReport,
  /// checkboxes, one column 'Finding', one row per finding in ChainRowText), LblSinglePass,
  /// BtnMerge, BtnSplit, BtnKeep. A row that can be merged or split starts checked; the
  /// others (cycles, duplicate From types) start unchecked. BtnMerge is enabled when
  /// CanMergeAll(checked), BtnSplit when CanSplitAll(checked); re-evaluated on every
  /// check change.</remarks>
  TChainForm = class(TForm)
    private
      FChains  : TArray<TRuleChain>;
      FLvChains: TListView;
      FBtnMerge: TButton;
      FBtnSplit: TButton;
      procedure Build;
      function NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
      function Checked: TArray<TRuleChain>;
      procedure ItemChecked(Sender: TObject; Item: TListItem);
      procedure UpdateButtons;
    public
      /// <summary>Runs the dialog modally.</summary>
      /// <param name="AOwner">The owner (the main form); not nil.</param>
      /// <param name="AChains">The findings to list; not empty.</param>
      /// <param name="AChecked">Out: the checked findings, in list order; empty when Keep / Esc.</param>
      /// <returns>mrYes = Merge, mrNo = Split, mrCancel = Keep (or the window closed).</returns>
      /// <remarks>Never touches a book. Call from the UI thread.</remarks>
      class function Run(AOwner: TComponent; const AChains: TArray<TRuleChain>; out AChecked: TArray<TRuleChain>): TModalResult;
  end;

implementation

uses
  Vcl.Controls
  ;

const
  DLG_W        = 720;
  DLG_H        = 340;
  MARGIN       = 12;
  INNER_W      = DLG_W - MARGIN - MARGIN;
  NOTE_TOP     = 12;
  NOTE_H       = 36;
  LIST_TOP     = 52;
  LIST_H       = 230;
  BTN_W        = 90;
  BTN_GAP      = 10;
  BTN_TOP      = 296;
  KEEP_LEFT    = DLG_W - MARGIN - BTN_W;
  SPLIT_LEFT   = KEEP_LEFT - BTN_GAP - BTN_W;
  MERGE_LEFT   = SPLIT_LEFT - BTN_GAP - BTN_W;
  SINGLE_PASS  = 'convert-apply applies a book in ONE pass against the original source: a rule''s output is never matched by another rule.';

class function TChainForm.Run(AOwner: TComponent; const AChains: TArray<TRuleChain>; out AChecked: TArray<TRuleChain>): TModalResult;
var
  LForm: TChainForm;
begin
  AChecked:= nil;
  LForm   := TChainForm.CreateNew(AOwner);
  try
    LForm.FChains:= AChains;
    LForm.Build;
    Result:= LForm.ShowModal;
    if Result in [mrYes, mrNo] then
      AChecked:= LForm.Checked
    else
      Result:= mrCancel;
  finally
    LForm.Free;
  end;
end;

function TChainForm.NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent := Self;
  Result.Name   := AName;
  Result.Caption:= ACaption;
  Result.Width  := BTN_W;
  Result.Top    := BTN_TOP;
  Result.Left   := ALeft;
end;

procedure TChainForm.Build;
var
  LNote: TLabel;
  LKeep: TButton;
begin
  Name        := 'ChainForm';
  Caption     := 'Rule chains';
  BorderStyle := bsDialog;
  Position    := poOwnerFormCenter;
  ClientWidth := DLG_W;
  ClientHeight:= DLG_H;
  LNote:= TLabel.Create(Self);
  LNote.Parent  := Self;
  LNote.Name    := 'LblSinglePass';
  LNote.Left    := MARGIN;
  LNote.Top     := NOTE_TOP;
  LNote.AutoSize:= False;
  LNote.WordWrap:= True;
  LNote.Width   := INNER_W;
  LNote.Height  := NOTE_H;
  LNote.Caption := SINGLE_PASS;
  FLvChains:= TListView.Create(Self);
  FLvChains.Parent    := Self;
  FLvChains.Name      := 'LvChains';
  FLvChains.Left      := MARGIN;
  FLvChains.Top       := LIST_TOP;
  FLvChains.Width     := INNER_W;
  FLvChains.Height    := LIST_H;
  FLvChains.ViewStyle := vsReport;
  FLvChains.Checkboxes:= True;
  FLvChains.ReadOnly  := True;
  FLvChains.RowSelect := True;
  FLvChains.Columns.Add.Caption:= 'Finding';
  FLvChains.Columns[0].Width   := INNER_W - MARGIN - MARGIN;
  for var LChain: TRuleChain in FChains do
  begin
    var LItem: TListItem:= FLvChains.Items.Add;
    LItem.Caption:= ChainRowText(LChain);
    LItem.Checked:= CanMergeChain(LChain) or CanSplitChain(LChain);
  end;
  // Wired after the rows exist: the initial checks above need no per-row re-gate.
  FLvChains.OnItemChecked:= ItemChecked;
  FBtnMerge:= NewButton('BtnMerge', '&Merge', MERGE_LEFT);
  FBtnMerge.ModalResult:= mrYes;
  FBtnSplit:= NewButton('BtnSplit', '&Split', SPLIT_LEFT);
  FBtnSplit.ModalResult:= mrNo;
  LKeep:= NewButton('BtnKeep', '&Keep', KEEP_LEFT);
  LKeep.ModalResult:= mrCancel;
  LKeep.Cancel     := True;
  UpdateButtons;
end;

// The checked findings, list order (the rows are FChains in order).
function TChainForm.Checked: TArray<TRuleChain>;
begin
  Result:= nil;
  for var I: Integer:= 0 to FLvChains.Items.Count - 1 do
    if FLvChains.Items[I].Checked then
      Result:= Result + [FChains[I]];
end;

procedure TChainForm.ItemChecked(Sender: TObject; Item: TListItem);
begin
  UpdateButtons;
end;

procedure TChainForm.UpdateButtons;
begin
  FBtnMerge.Enabled:= CanMergeAll(Checked);
  FBtnSplit.Enabled:= CanSplitAll(Checked);
end;

end.
