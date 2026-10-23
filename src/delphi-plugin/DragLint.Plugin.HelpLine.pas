unit DragLint.Plugin.HelpLine;

{ The help line at the top of the drag-lint dock page (spec docs\superpowers\
  specs\2026-10-23-ide-help-line-design.md 3.4): "Help on: [edit] [All
  features...]" and a drop-down list of matches under the edit.

  A TPanel built in code, NOT a TFrame: no .dfm, so the EResNotFound trap of
  code-built frames (Delphi_IDE_OptionsPage_HOWTO.md) does not apply. Like
  TDragLintStatusBar it never reads a handle-bound property in the
  constructor; layout happens in Resize, after the dock frame parents it.
  Matching, display text and URL rules are pure (DragLint.Plugin.HelpIndex);
  everything here is wiring, verified in a live IDE. }

interface

uses
  System.Classes
  , Vcl.Controls
  , Vcl.ExtCtrls
  , Vcl.StdCtrls
  , DragLint.Plugin.HelpIndex
  ;

type
  /// <summary>Help line: type part of a feature name, pick a match, open its
  /// help page; or open the complete feature list.</summary>
  /// <remarks>Main thread only. The match list is owned by this panel but
  /// parented to the panel's parent (it must overlap the tabs below); it is
  /// created on first use, when Parent is known.</remarks>
  TDLHelpLine = class(TPanel)
  private
    FCaptionLbl: TLabel  ;
    FEdit      : TEdit   ;
    FAllBtn    : TButton ;
    FList      : TListBox;
    FHits      : TArray<TDLHelpHit>;
    procedure Relayout;
    procedure EnsureList;
    procedure HideList;
    procedure ShowList(const pRows: TArray<string>);
    procedure UpdateHits;
    procedure OpenHit(const pIndex: Integer);
    procedure OpenSelectedOrFirst;
    procedure MoveSelection(const pDelta: Integer);
    procedure HandleEditChange (Sender: TObject);
    procedure HandleEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleEditKeyPress(Sender: TObject; var Key: Char);
    procedure HandleListDblClick(Sender: TObject);
    procedure HandleListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleListExit   (Sender: TObject);
    procedure HandleAllClick   (Sender: TObject);
  protected
    procedure Resize; override;
  public
    /// <summary>Builds the label, edit and button; aligns the panel alTop.</summary>
    /// <param name="AOwner">Owner; frees the panel and its list.</param>
    constructor Create(AOwner: TComponent); override;
    /// <summary>Puts the caret in the edit and selects its text, when the edit
    /// can take focus (a hidden dock cannot); otherwise does nothing.</summary>
    procedure FocusEdit;
  end; // class

implementation

uses
  System.SysUtils
  , System.Math
  , Winapi.Windows
  , DragLint.Plugin.Help
  ;

const
  LINE_HEIGHT    = 26;
  EDGE           = 4;
  GAP            = 6;
  CAPTION_WIDTH  = 52;
  BUTTON_WIDTH   = 96;
  CONTROL_HEIGHT = 21;
  LIST_MAX_ROWS  = DL_HELP_MAX_HITS;
  NOT_INSTALLED  = '(feature list not installed: ' + DL_HELP_INDEX_REL + ')';

constructor TDLHelpLine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align     := alTop;
  Height    := LINE_HEIGHT;
  BevelOuter:= bvNone;
  Caption   := '';

  FCaptionLbl:= TLabel.Create(Self);
  FCaptionLbl.Parent     := Self;
  FCaptionLbl.AutoSize   := False;
  FCaptionLbl.Transparent:= True;
  FCaptionLbl.Layout     := tlCenter;
  FCaptionLbl.Caption    := 'Help on:';

  FEdit:= TEdit.Create(Self);
  FEdit.Parent    := Self;
  FEdit.TextHint  := 'type part of a feature name';
  FEdit.OnChange  := HandleEditChange;
  FEdit.OnKeyDown := HandleEditKeyDown;
  FEdit.OnKeyPress:= HandleEditKeyPress;

  FAllBtn:= TButton.Create(Self);
  FAllBtn.Parent := Self;
  FAllBtn.Caption:= 'All features...';
  FAllBtn.OnClick:= HandleAllClick;
end; // constructor

procedure TDLHelpLine.Relayout;
var
  W, Top: Integer;
begin
  { Field reads only (Height/Width), never ClientWidth: see the unit header. }
  if FAllBtn = nil then Exit;
  W  := Width;
  Top:= (Height - CONTROL_HEIGHT) div 2;
  FCaptionLbl.SetBounds(EDGE, 0, CAPTION_WIDTH, Height);
  FAllBtn.SetBounds(W - EDGE - BUTTON_WIDTH, Top, BUTTON_WIDTH, CONTROL_HEIGHT);
  FEdit.SetBounds(FCaptionLbl.Left + CAPTION_WIDTH + GAP, Top,
    Max(0, FAllBtn.Left - GAP - (FCaptionLbl.Left + CAPTION_WIDTH + GAP)), CONTROL_HEIGHT);
  if (FList <> nil) and FList.Visible then
    FList.SetBounds(Left + FEdit.Left, Top + Height, FEdit.Width, FList.Height);
end; // procedure

procedure TDLHelpLine.Resize;
begin
  inherited Resize;
  Relayout;
end; // procedure

procedure TDLHelpLine.EnsureList;
begin
  if (FList <> nil) or (Parent = nil) then Exit;
  FList:= TListBox.Create(Self);
  FList.Visible   := False;
  FList.Parent    := Parent;
  FList.OnDblClick:= HandleListDblClick;
  FList.OnKeyDown := HandleListKeyDown;
  FList.OnExit    := HandleListExit;
end; // procedure

procedure TDLHelpLine.HideList;
begin
  if (FList <> nil) and FList.Visible then FList.Visible:= False;
end; // procedure

procedure TDLHelpLine.ShowList(const pRows: TArray<string>);
begin
  EnsureList;
  if FList = nil then Exit;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for var Row in pRows do FList.Items.Add(Row);
  finally
    FList.Items.EndUpdate;
  end; // try
  FList.SetBounds(Left + FEdit.Left, Top + Height, FEdit.Width,
    Min(Length(pRows), LIST_MAX_ROWS) * FList.ItemHeight + EDGE);
  FList.ItemIndex:= if Length(FHits) > 0 then 0 else -1;
  FList.Visible:= True;
  FList.BringToFront;
end; // procedure

procedure TDLHelpLine.UpdateHits;
var
  Index: TDLHelpIndex;
  Rows : TArray<string>;
begin
  FHits:= nil;
  if Trim(FEdit.Text) = '' then
  begin
    HideList;
    Exit;
  end; // if
  { Lazy: the list is located and parsed on the first keystroke, then only
    stat'ed (DLSharedHelpIndex re-reads it when size/mtime changed). }
  Index:= DLSharedHelpIndex;
  if not Index.Loaded then
  begin
    ShowList([if Index.LastError <> '' then '(feature list unreadable: ' + Index.LastError + ')' else NOT_INSTALLED]);
    Exit;
  end; // if
  FHits:= DLHelpMatch(FEdit.Text, Index.Entries);
  if Length(FHits) = 0 then
  begin
    HideList;
    Exit;
  end; // if
  SetLength(Rows, Length(FHits));
  for var I:= 0 to High(FHits) do Rows[I]:= FHits[I].Display;
  ShowList(Rows);
end; // procedure

procedure TDLHelpLine.OpenHit(const pIndex: Integer);
begin
  if (pIndex < 0) or (pIndex > High(FHits)) then Exit;
  HideList;
  DLOpenHelp(FHits[pIndex].Id);
end; // procedure

procedure TDLHelpLine.OpenSelectedOrFirst;
begin
  { "selecting with no list open opens the first hit" (spec 3.4) }
  if (FList <> nil) and FList.Visible and (FList.ItemIndex >= 0) then OpenHit(FList.ItemIndex)
  else                                                               OpenHit(0);
end; // procedure

procedure TDLHelpLine.MoveSelection(const pDelta: Integer);
begin
  if (FList = nil) or not FList.Visible or (FList.Items.Count = 0) then Exit;
  FList.ItemIndex:= EnsureRange(FList.ItemIndex + pDelta, 0, FList.Items.Count - 1);
end; // procedure

procedure TDLHelpLine.HandleEditChange(Sender: TObject);
begin
  UpdateHits;
end; // procedure

procedure TDLHelpLine.HandleEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN  : MoveSelection(1);
    VK_UP    : MoveSelection(-1);
    VK_RETURN: OpenSelectedOrFirst;
    VK_ESCAPE:
      begin
        FEdit.Text:= '';
        HideList;
      end;
  else
    Exit;
  end; // case
  Key:= 0;
end; // procedure

procedure TDLHelpLine.HandleEditKeyPress(Sender: TObject; var Key: Char);
begin
  { Enter / Esc are handled in KeyDown; swallowing them here stops the beep. }
  if CharInSet(Key, [#13, #27]) then Key:= #0;
end; // procedure

procedure TDLHelpLine.HandleListDblClick(Sender: TObject);
begin
  OpenHit(FList.ItemIndex);
end; // procedure

procedure TDLHelpLine.HandleListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN: OpenHit(FList.ItemIndex);
    VK_ESCAPE:
      begin
        HideList;
        FocusEdit;
      end;
  else
    Exit;
  end; // case
  Key:= 0;
end; // procedure

procedure TDLHelpLine.HandleListExit(Sender: TObject);
begin
  HideList;
end; // procedure

procedure TDLHelpLine.HandleAllClick(Sender: TObject);
begin
  DLOpenAllFeatures;
end; // procedure

procedure TDLHelpLine.FocusEdit;
begin
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end; // if
end; // procedure

end.
