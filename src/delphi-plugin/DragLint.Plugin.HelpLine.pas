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
  , DragLint.Plugin.HelpIndex // dl:unit DragLint.Plugin.HelpIndex accepted -- the help line is the UI of the matcher; DL_HELP_INDEX_REL names the file it reports missing
  ;

type
  /// <summary>Help line: type part of a feature name, pick a match, open its
  /// help page; or open the complete feature list.</summary>
  /// <remarks>
  /// Main thread only. The match list is owned by this panel but
  /// parented to the panel's parent (it must overlap the tabs below); it is
  /// created on first use, when Parent is known.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.DockForm.pas) ?, DragLint.Plugin.DockForm.TDragLintDockFrame.Create (DragLint.Plugin.DockForm.pas)</para>
  /// <para>Used in units: DragLint.Plugin.DockForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDLHelpLine = class(TPanel)
  private
    FCaptionLbl: TLabel  ;
    FEdit      : TEdit   ;
    FAllBtn    : TButton ;
    FList      : TListBox;
    FHits      : TArray<TDLHelpHit>;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.Resize (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: Max</para>
    /// <para>Reads: FAllBtn, FCaptionLbl, FEdit, FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Relayout;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.ShowList (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Reads: FList   Writes: FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure EnsureList;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.HandleListExit (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.HandleListKeyDown (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.UpdateHits (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Reads: FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HideList;
    /// <param name="pRows"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.UpdateHits (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList, Min</para>
    /// <para>Reads: FList, FEdit, FHits</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ShowList(const pRows: TArray<string>);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.Help.DLSharedHelpIndex, DragLint.Plugin.HelpIndex.DLHelpMatch, DragLint.Plugin.HelpLine.TDLHelpLine.HideList, DragLint.Plugin.HelpLine.TDLHelpLine.ShowList, Trim</para>
    /// <para>Reads: FEdit, FHits   Writes: FHits</para>
    /// <seealso cref="DragLint.Plugin.Help.DLSharedHelpIndex"/>
    /// <seealso cref="DragLint.Plugin.HelpIndex.DLHelpMatch"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HideList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.ShowList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpdateHits;
    /// <param name="pIndex"><!-- drag-lint:auto type -->const Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.HandleListDblClick (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.HandleListKeyDown (DragLint.Plugin.HelpLine.pas), DragLint.Plugin.HelpLine.TDLHelpLine.OpenSelectedOrFirst (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.Help.DLOpenHelp, DragLint.Plugin.HelpLine.TDLHelpLine.HideList</para>
    /// <para>Reads: FHits</para>
    /// <seealso cref="DragLint.Plugin.Help.DLOpenHelp"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HideList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure OpenHit(const pIndex: Integer);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit</para>
    /// <para>Reads: FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure OpenSelectedOrFirst;
    /// <param name="pDelta"><!-- drag-lint:auto type -->const Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: EnsureRange</para>
    /// <para>Reads: FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure MoveSelection(const pDelta: Integer);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.Create (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.UpdateHits</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.UpdateHits"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleEditChange (Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <param name="Key"><!-- drag-lint:auto type -->var Word</param>
    /// <param name="Shift"><!-- drag-lint:auto type -->TShiftState</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.Create (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.HideList, DragLint.Plugin.HelpLine.TDLHelpLine.MoveSelection, DragLint.Plugin.HelpLine.TDLHelpLine.OpenSelectedOrFirst</para>
    /// <para>Reads: FEdit</para>
    /// <para>Mutates: Key (var)</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HideList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.MoveSelection"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.OpenSelectedOrFirst"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <param name="Key"><!-- drag-lint:auto type -->var Char</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.Create (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: CharInSet</para>
    /// <para>Mutates: Key (var)</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleEditKeyPress(Sender: TObject; var Key: Char);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit</para>
    /// <para>Reads: FList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleListDblClick(Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <param name="Key"><!-- drag-lint:auto type -->var Word</param>
    /// <param name="Shift"><!-- drag-lint:auto type -->TShiftState</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit, DragLint.Plugin.HelpLine.TDLHelpLine.HideList, DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit</para>
    /// <para>Reads: FList</para>
    /// <para>Mutates: Key (var)</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HideList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.OpenHit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.HideList</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HideList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleListExit   (Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.HelpLine.TDLHelpLine.Create (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Calls: DragLint.Plugin.Help.DLOpenAllFeatures</para>
    /// <seealso cref="DragLint.Plugin.Help.DLOpenAllFeatures"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure HandleAllClick   (Sender: TObject);
  protected
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DragLint.Plugin.HelpLine.TDLHelpLine.Relayout</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Relayout"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Resize; override;
  public
    /// <summary>Builds the label, edit and button; aligns the panel alTop.</summary>
    /// <param name="AOwner">Owner; frees the panel and its list.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.DockForm.TDragLintDockFrame.Create (DragLint.Plugin.DockForm.pas)</para>
    /// <para>constructor</para>
    /// <para>Reads: FCaptionLbl, FEdit, FAllBtn   Writes: FCaptionLbl, FEdit, FAllBtn</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.FocusEdit"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(AOwner: TComponent); override;
    /// <summary>Puts the caret in the edit and selects its text, when the edit
    /// can take focus (a hidden dock cannot); otherwise does nothing.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.DockForm.TDragLintDockFrame.FocusHelpLine (DragLint.Plugin.DockForm.pas), DragLint.Plugin.HelpLine.TDLHelpLine.HandleListKeyDown (DragLint.Plugin.HelpLine.pas)</para>
    /// <para>Reads: FEdit</para>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.Create"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.EnsureList"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleAllClick"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditChange"/>
    /// <seealso cref="DragLint.Plugin.HelpLine.TDLHelpLine.HandleEditKeyDown"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
