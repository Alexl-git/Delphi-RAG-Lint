unit DragLint.Plugin.CompletionForm;

{ Borderless completion popup for drag-lint LSP completion results.
  Auto-closes on ESC key, deactivation (click outside).
  Call ShowDragLintCompletion() from the main thread only. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Graphics
  , Winapi.Windows
  , Winapi.Messages
  , ToolsAPI
  , ToolsAPI.Editor               { INTACodeEditorOptions -- the theme handle }
  , DragLint.Plugin.SyntaxColors  { the SAME palette the hover popup renders in }
  , DragLint.Plugin.Theme          { ThemedColor -- the IDE's theme, not Windows' }
  , DragLint.Plugin.CompletionText { kind word + signature split, pure and guarded }
  , DRagLint.Hover.Contrast       { EnsureReadable -- keep every run legible }
  ;

type
  TCompletionInsertCallback = reference to procedure(const AInsertText: string);

  /// <summary>One completion row, kept as PARTS rather than a flat string so
  /// each part can be drawn in its own colour.</summary>
  /// <remarks>The old code concatenated glyph + label + detail into a single
  /// listbox string, which is why the popup could not be themed: by draw time
  /// there was nothing left to tell a type from a name.</remarks>
  TDLCompletionRow = record
    KindWord : string;   { 'procedure', 'function', 'property', ... }
    Name     : string;
    Params   : string;   { '(const S: string)' -- empty when the symbol takes none }
    ReturnTyp: string;   { 'Integer' -- empty for procedures and non-routines }
    Quals    : string;   { '[protected]', '[read-only]' -- already bracketed }
  end;

  TDragLintCompletionForm = class(TForm)
    private
      FListBox    : TListBox                 ;
      FInsertTexts: TArray<string>           ;
      FRows       : TArray<TDLCompletionRow> ;
      FSynOpts    : INTACodeEditorOptions    ;
      FOnInsert   : TCompletionInsertCallback;
      procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure ListBoxDblClick(Sender: TObject);
      procedure ListBoxDrawItem(AControl: TWinControl; AIndex: Integer;
                                ARect: TRect; AState: TOwnerDrawState);
      procedure DoInsertSelected;
    protected
      procedure DoClose(var Action: TCloseAction); override;
      procedure Deactivate; override;
    public
      constructor Create(AOwner: TComponent); override;
      procedure ShowAt(X, Y: Integer; AItems: TJSONArray; const AOnInsert: TCompletionInsertCallback);
  end;

procedure ShowDragLintCompletion(AItems: TJSONArray; AScreenX, AScreenY: Integer; const AOnInsert: TCompletionInsertCallback);

implementation

{ ---- text helpers ----
  KindWord and SplitSignature MOVED to DragLint.Plugin.CompletionText, which is
  pure and therefore testable from a console harness; this unit is not. Local
  aliases keep the call sites below reading the same. }

function KindWord(AKind: Integer): string;
begin
  Result:= CompletionKindWord(AKind);
end;

procedure SplitSignature(const ASignature: string; out AParams, AReturn: string);
begin
  SplitCompletionSignature(ASignature, AParams, AReturn);
end;

{ ---- TDragLintCompletionForm ---- }

constructor TDragLintCompletionForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption    := '';
  BorderStyle:= bsNone;
  FormStyle  := fsStayOnTop;
  { The IDE themes itself through IOTAIDEThemingServices, NOT the process-global
    VCL TStyleManager -- so a bare clWindow is the WINDOWS system colour and
    stays white while the IDE is visibly dark. Reported 2026-08-19: "the
    completion popup is light while the IDE is dark". DragLint.Plugin.Theme is
    where that was already worked out for the hover popup; going through it
    rather than re-deriving an answer here is the point of it being shared. }
  Color      := ThemedColor(clWindow);
  KeyPreview := True;
  Position   := poDesigned;

  OnKeyDown:= FormKeyDown;

  FListBox:= TListBox.Create(Self);
  FListBox.Parent     := Self;
  FListBox.Align      := alClient;
  FListBox.BorderStyle:= bsNone;
  FListBox.Color      := ThemedColor(clWindow);
  FListBox.Font.Name:= 'Consolas';
  FListBox.Font.Size:= 9;
  FListBox.TabStop   := False;
  FListBox.OnDblClick:= ListBoxDblClick;
  { Owner-drawn so each part of a row can carry its own colour. lbOwnerDrawFixed
    (not Variable) because every row is one line of the same height -- the
    listbox never has to ask for a per-item height. }
  FListBox.Style      := lbOwnerDrawFixed;
  FListBox.ItemHeight := 18;
  FListBox.OnDrawItem := ListBoxDrawItem;
end; // constructor

procedure TDragLintCompletionForm.ListBoxDrawItem(AControl: TWinControl; AIndex: Integer;
  ARect: TRect; AState: TOwnerDrawState);
{ Draws one row as coloured runs: kind, name, parameters, return type.

  Every colour goes through EnsureReadable against the row's ACTUAL background
  before it is drawn, so the selected row (system highlight, often dark) does
  not swallow a dark-blue keyword -- the same guard the hover popup applies. }
var
  Cnv : TCanvas;
  Row : TDLCompletionRow;
  X   : Integer;
  Bg  : TColor ;

  procedure Run(const AText: string; ARole: TDLSynRole; ABold: Boolean = False);
  begin
    if AText = '' then Exit;
    Cnv.Font.Color:= EnsureReadable(SyntaxColorFor(FSynOpts, ARole), Bg);
    if ABold then Cnv.Font.Style:= [fsBold] else Cnv.Font.Style:= [];
    Cnv.TextOut(X, ARect.Top + 1, AText);
    Inc(X, Cnv.TextWidth(AText));
  end;

begin
  if not (AControl is TListBox) then Exit;
  Cnv:= (AControl as TListBox).Canvas;

  { Both through the IDE's theme. Bg is also what every run's contrast is
    measured against, so getting it wrong does not merely paint the wrong
    background -- it makes EnsureReadable correct each foreground against a
    colour that is not on screen. }
  if odSelected in AState then Bg:= ThemedColor(clHighlight) else Bg:= ThemedColor(clWindow);
  Cnv.Brush.Color:= Bg;
  Cnv.FillRect(ARect);

  if (AIndex < 0) or (AIndex > High(FRows)) then Exit;
  Row:= FRows[AIndex];

  X:= ARect.Left + 4;
  Cnv.Brush.Style:= bsClear;
  try
    { kind first -- it classifies the row and must not out-shout the name. Gold
      (srKind) rather than srKeyword: in reserved-word blue it read as part of
      the signature rather than a label on it. }
    if Row.KindWord <> '' then
    begin
      Run(Row.KindWord, srKind);
      Run(' ', srMuted);
    end;
    Run(Row.Name, srName, True);
    Run(Row.Params, srParam);
    if Row.ReturnTyp <> '' then
    begin
      Run(': ', srOperator);
      Run(Row.ReturnTyp, srType);
    end;
    if Row.Quals <> '' then
    begin
      Run(' ', srMuted);
      Run(Row.Quals, srMuted);
    end;
  finally
    Cnv.Brush.Style:= bsSolid;
    Cnv.Font.Style := [];
  end;
end; // procedure

procedure TDragLintCompletionForm.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action:= caFree;
end;

procedure TDragLintCompletionForm.Deactivate;
begin
  inherited;
  Close;
end;

procedure TDragLintCompletionForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
    begin
      Key:= 0;
      Close;
    end;
    VK_RETURN:
    begin
      Key:= 0;
      DoInsertSelected;
    end;
    VK_UP, VK_DOWN:
    begin
      { let the ListBox handle arrow keys }
      FListBox.SetFocus;
    end;
  end; // case
end; // procedure

procedure TDragLintCompletionForm.ListBoxDblClick(Sender: TObject);
begin
  DoInsertSelected;
end;

procedure TDragLintCompletionForm.DoInsertSelected;
var
  Idx: Integer;
begin
  Idx:= FListBox.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FInsertTexts)) then
  begin
    if Assigned(FOnInsert) then FOnInsert(FInsertTexts[Idx]);
    Close;
  end;
end;

procedure TDragLintCompletionForm.ShowAt(X, Y: Integer; AItems: TJSONArray; const AOnInsert: TCompletionInsertCallback);
const
  MAX_DETAIL = 60;
  MAX_H      = 320;
  ROW_H      = 18;
  PAD        = 40;
  MIN_W      = 250;
var
  i         : Integer    ;
  ItemObj   : TJSONObject;
  LabelStr  : string     ;
  DetailStr : string     ;
  InsertStr : string     ;
  KindInt   : Integer    ;
  DisplayStr: string     ;
  MaxW      : Integer    ;
  W         : Integer    ;
  H         : Integer    ;
  Count     : Integer    ;
  MonR      : TRect      ;
begin
  FOnInsert:= AOnInsert;
  FListBox.Items.BeginUpdate;
  try
    FListBox.Items.Clear;
    Count:= 0;
    if AItems <> nil then Count:= AItems.Count;
    SetLength(FInsertTexts, Count);
    SetLength(FRows       , Count);
    { Resolve the IDE colour interface ONCE per show, not per row and never per
      run -- the draw handler is called for every visible row on every repaint. }
    FSynOpts:= AcquireEditorColors;
    MaxW:= 0;

    for i:= 0 to Count - 1 do
    begin
      LabelStr := '';
      DetailStr:= '';
      InsertStr:= '';
      KindInt  := 0;

      if AItems.Items[i] is TJSONObject then
      begin
        ItemObj:= AItems.Items[i] as TJSONObject;
        ItemObj.TryGetValue<string>('label'     , LabelStr );
        ItemObj.TryGetValue<string>('detail'    , DetailStr);
        ItemObj.TryGetValue<string>('insertText', InsertStr);
        ItemObj.TryGetValue<Integer>('kind', KindInt);
      end;

      if InsertStr = '' then InsertStr:= LabelStr;
      FInsertTexts[i]:= InsertStr;

      { The engine prefixes qualifiers that decide USABILITY -- '[protected]',
        '[read-only]' -- onto detail. Peel them off so they can be drawn muted
        instead of being mistaken for part of the signature. }
      FRows[i].Quals:= '';
      DetailStr:= Trim(DetailStr);
      if (DetailStr <> '') and (DetailStr[Low(string)] = '[') then
      begin
        var RB: Integer:= Pos(']', DetailStr);
        if RB > 0 then
        begin
          FRows[i].Quals:= Copy(DetailStr, Low(string), RB);
          DetailStr:= Trim(Copy(DetailStr, RB + 1, MaxInt));
        end;
      end;

      { The engine no longer sends a qualified name here -- MakeCompletionItem
        used to fall back to one when a symbol had no signature, and it is now
        simply empty. The scrub that lived here matched
        `Pos('.' + LabelStr, DetailStr) > 0`, which ALSO blanked a genuine
        signature containing '.' + the member's name (a parameter typed
        `TRec.Value` on a member called `Value`) -- so it is deleted rather than
        kept as belt-and-braces. Guarded engine-side by
        run_completion_detail_type_guard.ps1.

        Only `detail = label` is still worth defending against, because it costs
        nothing and an empty type slot is the correct rendering either way. }
      if SameText(DetailStr, LabelStr) then DetailStr:= '';

      FRows[i].KindWord:= KindWord(KindInt);
      FRows[i].Name    := LabelStr;
      SplitSignature(DetailStr, FRows[i].Params, FRows[i].ReturnTyp);

      if Length(FRows[i].Params) > MAX_DETAIL then
        FRows[i].Params:= Copy(FRows[i].Params, Low(string), MAX_DETAIL) + '...)';

      DisplayStr:= FRows[i].KindWord + ' ' + FRows[i].Name + FRows[i].Params;
      { The separator is asked for rather than fixed at ': ' because a const
        whose type could not be inferred carries only its VALUE ('= A * 2'),
        and a colon in front of that reads as `const Derived: = A * 2`. }
      if FRows[i].ReturnTyp <> '' then
        DisplayStr:= DisplayStr + CompletionTypeSeparator(FRows[i].ReturnTyp) + FRows[i].ReturnTyp;
      if FRows[i].Quals     <> '' then DisplayStr:= DisplayStr + ' ' + FRows[i].Quals;

      { The listbox still needs an item per row (owner-draw paints over it, but
        the count and selection come from Items). }
      FListBox.Items.Add(DisplayStr);
      if Length(DisplayStr) > MaxW then MaxW:= Length(DisplayStr);
    end; // for
  finally
    FListBox.Items.EndUpdate;
  end; // try

  if FListBox.Items.Count > 0 then FListBox.ItemIndex:= 0;

  { Size: width heuristic ~7px/char (Consolas 9pt) }
  W:= MaxW * 7 + PAD;
  if W < MIN_W then W:= MIN_W;

  H:= Count * ROW_H + 12;
  if H > MAX_H then H:= MAX_H;
  if H < ROW_H + 12 then H:= ROW_H + 12;

  Width := W;
  Height:= H;

  { Clamp to work area }
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X:= MonR.Right  - W;
    if Y + H > MonR.Bottom then Y:= MonR.Bottom - H;
    if X < MonR.Left then X:= MonR.Left;
    if Y < MonR.Top  then Y:= MonR.Top;
  end;

  Left:= X;
  Top := Y;

  Show;
end; // procedure

{ ---- public factory ---- }

procedure ShowDragLintCompletion(AItems: TJSONArray; AScreenX, AScreenY: Integer; const AOnInsert: TCompletionInsertCallback);
var
  Form: TDragLintCompletionForm;
begin
  Form:= TDragLintCompletionForm.Create(Application);
  Form.ShowAt(AScreenX, AScreenY, AItems, AOnInsert);
end;

end.
