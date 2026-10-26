unit ConvRules.MigrateForm;

{ A4 #migrate slice 1: the Migrate dialog (spec section 6). Collects one member and its
  replacement -- a rename or DL_NONE -- and shows the line as it will read, the editor's
  pre-check and the block it goes into. Editor-only and code-built (no .dfm): it decides
  nothing and never touches a book. The pre-check comes from the host through a closure
  (ConvRules.Migrate.MigrateCheck); Apply is enabled by ConvRules.MigrateRules'
  refusal rule and the host's block text. }

interface

uses
  System.Classes
  , System.SysUtils
  , Vcl.Forms
  , Vcl.StdCtrls
  , ConvRules.Migrate
  ;

type
  /// <summary>The Migrate dialog.</summary>
  /// <remarks>Controls carry stable names for the GUI driver: LblMember, EdOld, RbRename, EdNew,
  /// RbBreak, LblPreview, LblCheck, LblBlock, BtnApply, BtnCancel. Escape = Cancel.</remarks>
  TMigrateForm = class(TForm)
    private
      FCheck     : TFunc<TMigratePick, string>;
      FBlockOk   : Boolean;
      FEdOld     : TEdit;
      FEdNew     : TEdit;
      FRbRename  : TRadioButton;
      FRbBreak   : TRadioButton;
      FLblPreview: TLabel;
      FLblCheck  : TLabel;
      FBtnApply  : TButton;
      procedure Build(const AMember, ADetail, ABlockText: string; AOldEditable: Boolean);
      function NewLabel(const AName, ACaption: string; ATop: Integer): TLabel;
      function NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
      function Pick: TMigratePick;
      procedure Changed(Sender: TObject);
    public
      /// <summary>Runs the dialog modally.</summary>
      /// <param name="AOwner">The owner (the main form); not nil.</param>
      /// <param name="AMember">The member (Old) to fill in; '' for Add.</param>
      /// <param name="ADetail">The member line ('btnTop.Count (method, public, TSrcBtn) -- lines 28'), or ''.</param>
      /// <param name="ABlockText">'into #convert F -&gt; T (line N of B)' or the FindMigrateBlock Reason;
      /// a text starting 'no #convert' or 'two #convert' disables Apply.</param>
      /// <param name="AOldEditable">True for Add (Old typed); False from a Work list row or for Edit.</param>
      /// <param name="ANew">The New to start with ('' for a new line); DL_NONE starts on the break choice.</param>
      /// <param name="ACheck">The host's pre-check of a pick (MigrateCheck on the target block); may be nil.</param>
      /// <param name="APick">Out: the pick; Default when cancelled.</param>
      /// <returns>True when the user pressed Apply.</returns>
      /// <remarks>Never touches a book. Call from the UI thread.</remarks>
      class function Run(AOwner: TComponent; const AMember, ADetail, ABlockText: string; AOldEditable: Boolean; const ANew: string;
        const ACheck: TFunc<TMigratePick, string>; out APick: TMigratePick): Boolean;
  end;

implementation

uses
  System.StrUtils
  , Vcl.Controls
  , ConvRules.MigrateRules  // dl:unit ConvRules.MigrateRules accepted -- MIGRATE_DL_NONE is the deliberate-break word the dialog writes, with MigrateLineText
  ;

const
  DLG_W       = 600;
  DLG_H       = 330;
  MARGIN      = 12;
  LABEL_H     = 20;
  ROW_H       = 30;
  EDIT_LEFT   = 110;
  INNER_W     = DLG_W - MARGIN - MARGIN;
  MEMBER_TOP  = 12;
  OLD_TOP     = 42;
  RENAME_TOP  = 74;
  BREAK_TOP   = 104;
  PREVIEW_TOP = 140;
  CHECK_TOP   = 166;
  BLOCK_TOP   = 192;
  BTN_W       = 90;
  BTN_TOP     = 250;
  BTN_GAP     = 10;
  APPLY_LEFT  = DLG_W - MARGIN - BTN_W - BTN_GAP - BTN_W;
  CANCEL_LEFT = DLG_W - MARGIN - BTN_W;
  BLOCK_NONE_PREFIX      = 'no #convert';
  BLOCK_AMBIGUOUS_PREFIX = 'two #convert';
  BREAK_CAPTION = 'DL_NONE -- deliberate break (the unit will not compile at these sites until converted by hand)';

class function TMigrateForm.Run(AOwner: TComponent; const AMember, ADetail, ABlockText: string; AOldEditable: Boolean; const ANew: string;  // dl:ok too-many-parameters@ef96 -- the dialog contract of spec section 6 (member, detail, block text, editability, start value, check closure, out pick); a record would only rename them
  const ACheck: TFunc<TMigratePick, string>; out APick: TMigratePick): Boolean;
var
  LForm: TMigrateForm;
begin
  APick:= Default(TMigratePick);
  LForm:= TMigrateForm.CreateNew(AOwner);
  try
    LForm.FCheck:= ACheck;
    LForm.Build(AMember, ADetail, ABlockText, AOldEditable);
    if SameText(ANew, MIGRATE_DL_NONE) then
      LForm.FRbBreak.Checked:= True
    else
      LForm.FEdNew.Text:= ANew;
    LForm.Changed(nil);
    Result:= LForm.ShowModal = mrOk;
    if Result then
      APick:= LForm.Pick;
  finally
    LForm.Free;
  end;
end;

function TMigrateForm.NewLabel(const AName, ACaption: string; ATop: Integer): TLabel;
begin
  Result:= TLabel.Create(Self);
  Result.Parent  := Self;
  Result.Name    := AName;
  Result.Left    := MARGIN;
  Result.Top     := ATop;
  Result.AutoSize:= False;
  Result.Width   := INNER_W;
  Result.Height  := LABEL_H;
  Result.Caption := ACaption;
end;

function TMigrateForm.NewButton(const AName, ACaption: string; ALeft: Integer): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent := Self;
  Result.Name   := AName;
  Result.Caption:= ACaption;
  Result.Width  := BTN_W;
  Result.Left   := ALeft;
  Result.Top    := BTN_TOP;
end;

procedure TMigrateForm.Build(const AMember, ADetail, ABlockText: string; AOldEditable: Boolean);
var
  LLbl: TLabel;
begin
  Caption     := if AOldEditable then 'Add #migrate' else 'Migrate ' + AMember;
  BorderStyle := bsDialog;
  Position    := poOwnerFormCenter;
  ClientWidth := DLG_W;
  ClientHeight:= DLG_H;
  KeyPreview  := True;

  NewLabel('LblMember', if ADetail <> '' then ADetail else AMember, MEMBER_TOP);
  LLbl:= NewLabel('', 'Member:', OLD_TOP);
  LLbl.Width:= EDIT_LEFT - MARGIN;
  FEdOld:= TEdit.Create(Self);
  FEdOld.Parent  := Self;
  FEdOld.Name    := 'EdOld';
  FEdOld.Text    := AMember;
  FEdOld.Left    := EDIT_LEFT;
  FEdOld.Top     := OLD_TOP;
  FEdOld.Width   := DLG_W - EDIT_LEFT - MARGIN;
  FEdOld.ReadOnly:= not AOldEditable;
  FEdOld.OnChange:= Changed;

  FRbRename:= TRadioButton.Create(Self);
  FRbRename.Parent := Self;
  FRbRename.Name   := 'RbRename';
  FRbRename.Caption:= 'Rename to';
  FRbRename.Left   := MARGIN;
  FRbRename.Top    := RENAME_TOP;
  FRbRename.Width  := EDIT_LEFT - MARGIN;
  FRbRename.Checked:= True;
  FRbRename.OnClick:= Changed;
  FEdNew:= TEdit.Create(Self);
  FEdNew.Parent  := Self;
  FEdNew.Name    := 'EdNew';
  FEdNew.Text    := '';
  FEdNew.Left    := EDIT_LEFT;
  FEdNew.Top     := RENAME_TOP;
  FEdNew.Width   := DLG_W - EDIT_LEFT - MARGIN;
  FEdNew.OnChange:= Changed;

  FRbBreak:= TRadioButton.Create(Self);
  FRbBreak.Parent := Self;
  FRbBreak.Name   := 'RbBreak';
  FRbBreak.Caption:= BREAK_CAPTION;
  FRbBreak.Left   := MARGIN;
  FRbBreak.Top    := BREAK_TOP;
  FRbBreak.Width  := INNER_W;
  FRbBreak.Height := ROW_H;
  FRbBreak.OnClick:= Changed;

  FLblPreview:= NewLabel('LblPreview', '', PREVIEW_TOP);
  FLblCheck  := NewLabel('LblCheck', '', CHECK_TOP);
  NewLabel('LblBlock', ABlockText, BLOCK_TOP);
  FBlockOk:= not (StartsText(BLOCK_NONE_PREFIX, ABlockText) or StartsText(BLOCK_AMBIGUOUS_PREFIX, ABlockText));

  FBtnApply:= NewButton('BtnApply', 'Apply', APPLY_LEFT);
  FBtnApply.ModalResult:= mrOk;
  FBtnApply.Default    := True;
  var LCancel: TButton:= NewButton('BtnCancel', 'Cancel', CANCEL_LEFT);
  LCancel.ModalResult:= mrCancel;
  LCancel.Cancel     := True;
end;

function TMigrateForm.Pick: TMigratePick;
begin
  Result:= Default(TMigratePick);
  Result.Old  := Trim(FEdOld.Text);
  Result.Break:= FRbBreak.Checked;
  Result.New  := if Result.Break then MIGRATE_DL_NONE else Trim(FEdNew.Text);
end;

procedure TMigrateForm.Changed(Sender: TObject);
var
  LPick : TMigratePick;
  LCheck: string;
begin
  LPick:= Pick;
  FEdNew.Enabled:= not LPick.Break;
  FLblPreview.Caption:= MigrateLineText(LPick.Old, LPick.New);
  LCheck:= if Assigned(FCheck) then FCheck(LPick) else '';
  FLblCheck.Caption:= LCheck;
  // Apply only for a line the engine applies, into a block that exists.
  FBtnApply.Enabled:= FBlockOk and (LPick.Old <> '') and (LPick.New <> '') and IsValidIdent(LPick.Old) and IsValidIdent(LPick.New);
end;

end.
