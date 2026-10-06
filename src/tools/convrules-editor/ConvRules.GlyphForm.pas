unit ConvRules.GlyphForm;

{ C10 E6-E8: the one place a glyph expression is WRITTEN. An edit, a live check line
  (the engine's own parser through ConvRules.Glyph, plus the two block-level rules in
  the engine's wording), an optional "also add the count link" checkbox, OK / Clear /
  Cancel. No slot picker, no preview (grammar spec, build 1). Editor-only: outside the
  model tests' closure, so it decides nothing -- every rule it shows is in
  ConvRules.Glyph and pinned there. }

interface

uses
  System.SysUtils
  , System.Classes
  , ConvRules.Model
  ;

type
  /// <summary>What the dialog's close means for the link.</summary>
  /// <remarks>gerCancel: leave the link alone. gerSet: write the accepted expression.
  /// gerClear: remove the link's expression.</remarks>
  TGlyphExprResult = (gerCancel, gerSet, gerClear);

  /// <summary>Dialog input and output.</summary>
  TGlyphDialogOptions = record
    /// <summary>The link's bare FromPath (title and the count-link text).</summary>
    FromPath   : string;
    /// <summary>The link's ToPath (title only).</summary>
    ToPath     : string;
    /// <summary>In: the current expression. Out (gerSet): the accepted text, trimmed.</summary>
    Expr       : string;
    /// <summary>The ACTIVE block's links, for CountLinkIssue / StraightCountCarryHint.</summary>
    BlockNodes : TArray<TRuleNode>;
    /// <summary>The To leaf a G[count] link may be added for; '' hides the checkbox.</summary>
    CountTarget: string;
    /// <summary>True when CountTarget is an EXISTING G[count] link from FromPath: the box
    /// then reads 'Keep' and unchecking it removes that link. False: 'Also add'.</summary>
    CountExists: Boolean;
  end;

/// <summary>Runs the glyph-expression dialog modally.</summary>
/// <param name="AOwner">The main form.</param>
/// <param name="AOpts">See TGlyphDialogOptions; Expr is written back on gerSet.</param>
/// <param name="AAddCountLink">True when the user left the count-link box checked
/// (gerSet only, and only when CountTarget was given and the box was shown). False on
/// gerSet with CountExists means: remove the existing count link.</param>
/// <returns>gerSet (write Expr), gerClear (remove the expression) or gerCancel.</returns>
function RunGlyphExprDialog(AOwner: TComponent; var AOpts: TGlyphDialogOptions; out AAddCountLink: Boolean): TGlyphExprResult;

implementation

uses
  Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.Graphics  // dl:ok unused-unit-in-uses@825b -- REVIEWED 2026-10-06 false positive: clRed / clWindowText are used inside an if-expression (EditChange), whose then/else operands the 1.21.1 extractor emits no refs for; filed as a gap
  , ConvRules.Glyph  // dl:unit ConvRules.Glyph accepted -- GLYPH_COUNT_EXPR travels with the count-link rules this dialog shows (CountLinkIssue)
  ;

const
  DLG_W        = 560;
  DLG_H        = 230;
  MARGIN       = 12;
  ROW_H        = 24;
  HINT_H       = 36;
  BTN_W        = 80;
  BTN_SLOT     = BTN_W + MARGIN;
  INNER_W      = DLG_W - MARGIN - MARGIN;
  EDIT_TOP     = 40;
  CHECK_TOP    = 72;
  COUNTBOX_TOP = 104;
  HINT_TOP     = 134;
  BTN_TOP      = 176;
  OK_LEFT      = DLG_W - BTN_SLOT - BTN_SLOT - BTN_SLOT;
  CLEAR_LEFT   = DLG_W - BTN_SLOT - BTN_SLOT;
  CANCEL_LEFT  = DLG_W - BTN_SLOT;
  CHECK_OK     = 'OK';
  NEED_TEXT    = 'enter an expression, or Clear to remove it';

type
  TGlyphExprForm = class(TForm)
    private
      FEdit      : TEdit;
      FCheck     : TLabel;
      FHint      : TLabel;
      FCountBox  : TCheckBox;
      FOk        : TButton;
      FClear     : TButton;
      FOpts      : TGlyphDialogOptions;
      FResultKind: TGlyphExprResult;
      procedure EditChange(Sender: TObject);
      procedure OkClick(Sender: TObject);
      procedure ClearClick(Sender: TObject);
      function NewLabel(ATop, AHeight: Integer): TLabel;
      function NewButton(const ACaption: string; ALeft: Integer): TButton;
      procedure Build;
    public
      constructor CreateFor(AOwner: TComponent; const AOpts: TGlyphDialogOptions);
  end;

constructor TGlyphExprForm.CreateFor(AOwner: TComponent; const AOpts: TGlyphDialogOptions);
begin
  inherited CreateNew(AOwner);
  FOpts:= AOpts;
  FResultKind:= gerCancel;
  Build;
end;

function TGlyphExprForm.NewLabel(ATop, AHeight: Integer): TLabel;
begin
  Result:= TLabel.Create(Self);
  Result.Parent  := Self;
  Result.Left    := MARGIN;
  Result.Top     := ATop;
  Result.AutoSize:= False;
  Result.WordWrap:= True;
  Result.Width   := INNER_W;
  Result.Height  := AHeight;
end;

function TGlyphExprForm.NewButton(const ACaption: string; ALeft: Integer): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption:= ACaption;
  Result.Width  := BTN_W;
  Result.Top    := BTN_TOP;
  Result.Left   := ALeft;
end;

procedure TGlyphExprForm.Build;
var
  L: TLabel;
  B: TButton;
begin
  Caption     := Format('Glyph expression: %s -> %s', [FOpts.FromPath, FOpts.ToPath]);
  BorderStyle := bsDialog;
  Position    := poOwnerFormCenter;
  ClientWidth := DLG_W;
  ClientHeight:= DLG_H;
  L:= NewLabel(MARGIN, ROW_H);
  L.Caption:= 'G[I/N] terms stitch left to right; commas separate per-N alternatives; G[count] links the glyph count.';
  FEdit:= TEdit.Create(Self);
  FEdit.Parent:= Self;
  FEdit.Left  := MARGIN;
  FEdit.Top   := EDIT_TOP;
  FEdit.Width := INNER_W;
  FEdit.Text  := FOpts.Expr;
  FEdit.OnChange:= EditChange;
  FCheck:= NewLabel(CHECK_TOP, ROW_H);
  // The check line is red on an error: the VCL style would repaint the font otherwise.
  FCheck.StyleElements:= FCheck.StyleElements - [seFont];
  FCountBox:= TCheckBox.Create(Self);
  FCountBox.Parent := Self;
  FCountBox.Left   := MARGIN;
  FCountBox.Top    := COUNTBOX_TOP;
  FCountBox.Width  := INNER_W;
  FCountBox.Caption:= Format('%s #link %s <- %s %s', [if FOpts.CountExists then 'Keep' else 'Also add', FOpts.CountTarget, FOpts.FromPath, GLYPH_COUNT_EXPR]);
  FCountBox.Checked:= FOpts.CountTarget <> '';
  FCountBox.Visible:= FOpts.CountTarget <> '';
  FHint:= NewLabel(HINT_TOP, HINT_H);
  FHint.Caption:= StraightCountCarryHint(FOpts.BlockNodes);
  FOk:= NewButton(CHECK_OK, OK_LEFT);
  FOk.Default:= True;
  FOk.OnClick:= OkClick;
  FClear:= NewButton('Clear', CLEAR_LEFT);
  FClear.OnClick:= ClearClick;
  FClear.Enabled:= FOpts.Expr <> '';
  B:= NewButton('Cancel', CANCEL_LEFT);
  B.Cancel     := True;
  B.ModalResult:= mrCancel;
  EditChange(nil);
end;

{ The live check: the engine's parser first, then the G[count] block rule. OK is
  enabled only when both are silent; a non-empty expression is required (Clear is the
  way to remove one, so an emptied edit cannot be confirmed as "set"). }
procedure TGlyphExprForm.EditChange(Sender: TObject);
var
  Err: string;
  T  : string;
begin
  T:= Trim(FEdit.Text);
  if T = '' then
    Err:= NEED_TEXT
  else if CheckGlyphExprText(T, Err) then
    Err:= CountLinkIssue(FOpts.BlockNodes, FOpts.FromPath, T);
  FCheck.Caption   := if Err = '' then CHECK_OK else Err;
  FCheck.Font.Color:= if Err = '' then clWindowText else clRed;
  FOk.Enabled:= Err = '';
  // a count link needs no count link of its own
  FCountBox.Visible:= (FOpts.CountTarget <> '') and (Err = '') and not SameText(T, GLYPH_COUNT_EXPR);
end;

procedure TGlyphExprForm.OkClick(Sender: TObject);
begin
  FOpts.Expr:= Trim(FEdit.Text);
  FResultKind:= gerSet;
  ModalResult:= mrOk;
end;

procedure TGlyphExprForm.ClearClick(Sender: TObject);
begin
  FResultKind:= gerClear;
  ModalResult:= mrOk;
end;

function RunGlyphExprDialog(AOwner: TComponent; var AOpts: TGlyphDialogOptions; out AAddCountLink: Boolean): TGlyphExprResult;
var
  F: TGlyphExprForm;
begin
  AAddCountLink:= False;
  F:= TGlyphExprForm.CreateFor(AOwner, AOpts);
  try
    if F.ShowModal <> mrOk then
      Exit(gerCancel);
    Result:= F.FResultKind;
    if Result = gerSet then
    begin
      AOpts.Expr:= F.FOpts.Expr;
      AAddCountLink:= F.FCountBox.Visible and F.FCountBox.Checked;
    end;
  finally
    F.Free;
  end;
end;

end.
