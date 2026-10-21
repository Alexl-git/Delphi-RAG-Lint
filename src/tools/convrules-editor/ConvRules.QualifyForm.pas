unit ConvRules.QualifyForm;

{ A2: the Qualify #convert dialog. Lists the engine's qualify_fixes[] of one Convert
  results row, lets the user pick a candidate per fix and shows the line as it will
  read. Editor-only and code-built (no .dfm): it decides nothing and never touches a
  book -- every rule it shows is in ConvRules.QualifyFix and pinned there; the caller
  gets the picks and hands them to the host. }

interface

uses
  System.Classes
  , Vcl.Forms
  , Vcl.StdCtrls
  , ConvRules.ConvertRun
  , ConvRules.QualifyFix
  ;

type
  /// <summary>The Qualify #convert dialog.</summary>
  /// <remarks>Controls carry stable names for the GUI driver: LbFixes, LbCandidates,
  /// LblCurrent, LblAlternative, BtnUse, LblPreview, BtnApply, BtnCancel. An inferred fix starts
  /// with the engine's chosen candidate picked; a refused fix starts with none. D4: BtnUse
  /// ('Add #use Unit' / 'Remove #use Unit') is enabled when the alternative of the candidate
  /// shown (else the fix's) is a #use of a "to" side (QualifyUseUnit); pressing it makes the fix a
  /// #use pick (no candidate), and picking a candidate again drops it.</remarks>
  TQualifyForm = class(TForm)
    private
      FFixes      : TArray<TQualifyFix>;
      FPicks      : TArray<string>;
      FUse        : TArray<string>;
      FLbFixes    : TListBox;
      FLbCandidates: TListBox;
      FLblCurrent : TLabel;
      FLblAlternative: TLabel;
      FBtnUse     : TButton;
      FLblPreview : TLabel;
      FBtnApply   : TButton;
      procedure Build(const ABook: string);
      function NewLabel(const AName: string; ATop, AHeight: Integer): TLabel;
      function NewList(const AName: string; ATop, AHeight: Integer; AOnClick: TNotifyEvent): TListBox;
      function NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
      procedure FixSelected(Sender: TObject);
      procedure CandidateClicked(Sender: TObject);
      procedure UseClicked(Sender: TObject);
      function AlternativeOf(AFix: Integer): string;
      procedure ShowAlternative;
      procedure ShowPreview;
      function PicksOf(AIndex: Integer): TArray<TQualifyPick>;
    public
      /// <summary>Runs the dialog modally.</summary>
      /// <param name="AOwner">The owner (the Convert tab); not nil.</param>
      /// <param name="ABook">The book's path; only its file name is shown.</param>
      /// <param name="AFixes">The selected row's Apply.QualifyFixes; not empty.</param>
      /// <param name="APicks">Out: one pick per fix, same order; Candidate '' = no pick. Empty when cancelled.</param>
      /// <returns>True when the user pressed Apply.</returns>
      /// <remarks>Never touches a book. Call from the UI thread.</remarks>
      class function Run(AOwner: TComponent; const ABook: string; const AFixes: TArray<TQualifyFix>; out APicks: TArray<TQualifyPick>): Boolean;
  end;

implementation

uses
  System.SysUtils
  , Vcl.Controls
  ;

const
  DLG_W      = 640;
  DLG_H      = 440;
  MARGIN     = 12;
  LABEL_H    = 20;
  ALT_H      = 36;
  USE_W      = 150;
  INNER_W    = DLG_W - MARGIN - MARGIN;
  FIXES_TOP  = 40;
  FIXES_H    = 80;
  CAND_TOP   = 130;
  CAND_H     = 110;
  ALT_TOP    = 248;
  CUR_TOP    = 12;
  PREVIEW_TOP = 290;
  PREVIEW_H  = 60;
  BTN_W      = 90;
  BTN_TOP    = 388;
  BTN_GAP    = 10;
  APPLY_LEFT = DLG_W - MARGIN - BTN_W - BTN_GAP - BTN_W;
  CANCEL_LEFT = DLG_W - MARGIN - BTN_W;
  NO_SELECTION = -1;

class function TQualifyForm.Run(AOwner: TComponent; const ABook: string; const AFixes: TArray<TQualifyFix>; out APicks: TArray<TQualifyPick>): Boolean;
var
  LForm: TQualifyForm;
begin
  APicks:= nil;
  LForm := TQualifyForm.CreateNew(AOwner);
  try
    LForm.FFixes:= AFixes;
    LForm.Build(ABook);
    Result:= LForm.ShowModal = mrOk;
    if Result then
      for var I: Integer:= 0 to High(AFixes) do
        APicks:= APicks + [LForm.PicksOf(I)[0]];
  finally
    LForm.Free;
  end;
end;

function TQualifyForm.NewLabel(const AName: string; ATop, AHeight: Integer): TLabel;
begin
  Result:= TLabel.Create(Self);
  Result.Parent  := Self;
  Result.Name    := AName;
  Result.Left    := MARGIN;
  Result.Top     := ATop;
  Result.AutoSize:= False;
  Result.WordWrap:= True;
  Result.Width   := INNER_W;
  Result.Height  := AHeight;
end;

function TQualifyForm.NewList(const AName: string; ATop, AHeight: Integer; AOnClick: TNotifyEvent): TListBox;
begin
  Result:= TListBox.Create(Self);
  Result.Parent  := Self;
  Result.Name    := AName;
  Result.Left    := MARGIN;
  Result.Top     := ATop;
  Result.Width   := INNER_W;
  Result.Height  := AHeight;
  Result.OnClick := AOnClick;
end;

function TQualifyForm.NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent := Self;
  Result.Name   := AName;
  Result.Caption:= ACaption;
  Result.Width  := BTN_W;
  Result.Top    := BTN_TOP;
  Result.Left   := ALeft;
end;

procedure TQualifyForm.Build(const ABook: string);
var
  LCancel: TButton;
begin
  Name        := 'QualifyForm';
  Caption     := 'Qualify #convert -- ' + ExtractFileName(ABook);
  BorderStyle := bsDialog;
  Position    := poOwnerFormCenter;
  ClientWidth := DLG_W;
  ClientHeight:= DLG_H;
  FLblCurrent:= NewLabel('LblCurrent', CUR_TOP, LABEL_H);
  FLbFixes   := NewList('LbFixes', FIXES_TOP, FIXES_H, FixSelected);
  FLbCandidates:= NewList('LbCandidates', CAND_TOP, CAND_H, CandidateClicked);
  FLblAlternative:= NewLabel('LblAlternative', ALT_TOP, ALT_H);
  FLblAlternative.Width:= INNER_W - USE_W - MARGIN;
  FBtnUse:= NewButton('BtnUse', 'Add #use', MARGIN + INNER_W - USE_W);
  FBtnUse.Top    := ALT_TOP;
  FBtnUse.Width  := USE_W;
  FBtnUse.Enabled:= False;
  FBtnUse.OnClick:= UseClicked;
  FLblPreview:= NewLabel('LblPreview', PREVIEW_TOP, PREVIEW_H);
  FBtnApply:= NewButton('BtnApply', 'Apply', APPLY_LEFT);
  FBtnApply.Default:= True;
  FBtnApply.ModalResult:= mrOk;
  LCancel:= NewButton('BtnCancel', 'Cancel', CANCEL_LEFT);
  LCancel.Cancel     := True;
  LCancel.ModalResult:= mrCancel;
  SetLength(FPicks, Length(FFixes));
  SetLength(FUse, Length(FFixes));
  for var I: Integer:= 0 to High(FFixes) do
  begin
    FLbFixes.Items.Add(QualifyFixRowText(FFixes[I]));
    var LDefault: Integer:= DefaultCandidateIndex(FFixes[I]);
    FPicks[I]:= if LDefault >= 0 then FFixes[I].Suggestions[LDefault].Candidate else '';
  end;
  if FLbFixes.Items.Count > 0 then
  begin
    FLbFixes.ItemIndex:= 0;
    FixSelected(nil);
  end;
end;

// The pick of fix AIndex as a one-element array (the form keeps candidates only).
function TQualifyForm.PicksOf(AIndex: Integer): TArray<TQualifyPick>;
begin
  SetLength(Result, 1);
  Result[0].Fix      := FFixes[AIndex];
  Result[0].Candidate:= FPicks[AIndex];
  Result[0].UseUnit  := FUse[AIndex];
end;

// The alternative text of the candidate shown for fix AFix (else the fix's own).
function TQualifyForm.AlternativeOf(AFix: Integer): string;
begin
  if FUse[AFix] <> '' then
    Exit('#use ' + FUse[AFix]); // the pick made stays shown whatever candidate is highlighted
  Result:= FFixes[AFix].Alternative;
  if (FLbCandidates.ItemIndex <> NO_SELECTION) and (FFixes[AFix].Suggestions[FLbCandidates.ItemIndex].Alternative <> '') then
    Result:= FFixes[AFix].Suggestions[FLbCandidates.ItemIndex].Alternative;
end;

// LblAlternative and BtnUse for the selected fix; the button needs a clickable #use.
procedure TQualifyForm.ShowAlternative;
var
  LAt  : Integer;
  LAlt : string;
  LUnit: string;
begin
  LAt:= FLbFixes.ItemIndex;
  if LAt = NO_SELECTION then
    Exit;
  LAlt := AlternativeOf(LAt);
  LUnit:= QualifyUseUnit(FFixes[LAt], LAlt);
  FLblAlternative.Caption:= if LAlt = '' then '' else 'or: ' + LAlt;
  FBtnUse.Enabled:= LUnit <> '';
  if LUnit = '' then
    FBtnUse.Caption:= 'Add #use'
  else
    FBtnUse.Caption:= (if SameText(FUse[LAt], LUnit) then 'Remove #use ' else 'Add #use ') + LUnit;
end;

procedure TQualifyForm.FixSelected(Sender: TObject);
var
  LAt: Integer;
begin
  LAt:= FLbFixes.ItemIndex;
  FLbCandidates.Items.Clear;
  if LAt = NO_SELECTION then
    Exit;
  for var LSug: TQualifySuggestion in FFixes[LAt].Suggestions do
    FLbCandidates.Items.Add(QualifyCandidateText(LSug));
  FLbCandidates.ItemIndex:= NO_SELECTION;
  for var I: Integer:= 0 to High(FFixes[LAt].Suggestions) do
    if SameText(FFixes[LAt].Suggestions[I].Candidate, FPicks[LAt]) then
      FLbCandidates.ItemIndex:= I;
  ShowAlternative;
  ShowPreview;
end;

procedure TQualifyForm.CandidateClicked(Sender: TObject);
var
  LAt: Integer;
begin
  LAt:= FLbFixes.ItemIndex;
  if (LAt = NO_SELECTION) or (FLbCandidates.ItemIndex = NO_SELECTION) then
    Exit;
  FPicks[LAt]:= FFixes[LAt].Suggestions[FLbCandidates.ItemIndex].Candidate;
  FUse[LAt]  := '';
  ShowAlternative;
  ShowPreview;
end;

// BtnUse: the fix becomes (or stops being) a #use pick; the candidate it replaces is dropped.
procedure TQualifyForm.UseClicked(Sender: TObject);
var
  LAt  : Integer;
  LUnit: string;
begin
  LAt:= FLbFixes.ItemIndex;
  if LAt = NO_SELECTION then
    Exit;
  LUnit:= QualifyUseUnit(FFixes[LAt], AlternativeOf(LAt));
  if LUnit = '' then
    Exit;
  if SameText(FUse[LAt], LUnit) then
    FUse[LAt]:= ''
  else
  begin
    FUse[LAt]  := LUnit;
    FPicks[LAt]:= '';
    FLbCandidates.ItemIndex:= NO_SELECTION;
  end;
  ShowAlternative;
  ShowPreview;
end;

// The selected fix's line as it will read: every pick of the fixes sharing its header.
procedure TQualifyForm.ShowPreview;
var
  LAt   : Integer;
  LPicks: TArray<TQualifyPick>;
begin
  LAt:= FLbFixes.ItemIndex;
  if LAt = NO_SELECTION then
    Exit;
  LPicks:= nil;
  for var I: Integer:= 0 to High(FFixes) do
    if (FFixes[I].RuleLine = FFixes[LAt].RuleLine) and (FFixes[I].Current = FFixes[LAt].Current) then
      LPicks:= LPicks + PicksOf(I);
  FLblCurrent.Caption:= FFixes[LAt].Current;
  FLblPreview.Caption:= 'will read: ' + QualifyPreviewText(FFixes[LAt].Current, LPicks);
  if FUse[LAt] <> '' then
    FLblPreview.Caption:= FLblPreview.Caption + sLineBreak + QualifyUsePreviewText(FUse[LAt]);
end;

end.
