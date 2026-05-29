unit DragLint.Plugin.CompletionForm;

{ Borderless completion popup for drag-lint LSP completion results.
  Auto-closes on ESC key, deactivation (click outside).
  Call ShowDragLintCompletion() from the main thread only. }

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Winapi.Windows, Winapi.Messages;

type
  TCompletionInsertCallback = reference to procedure(const AInsertText: string);

  TDragLintCompletionForm = class(TForm)
  private
    FListBox:     TListBox;
    FInsertTexts: TArray<string>;
    FOnInsert:    TCompletionInsertCallback;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListBoxDblClick(Sender: TObject);
    procedure DoInsertSelected;
  protected
    procedure DoClose(var Action: TCloseAction); override;
    procedure Deactivate; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowAt(X, Y: Integer; AItems: TJSONArray;
      const AOnInsert: TCompletionInsertCallback);
  end;

procedure ShowDragLintCompletion(AItems: TJSONArray;
  AScreenX, AScreenY: Integer; const AOnInsert: TCompletionInsertCallback);

implementation

{ ---- kind glyph helper ---- }

function KindGlyph(AKind: Integer): Char;
begin
  case AKind of
    2:  Result := 'M';
    3:  Result := 'f';
    4:  Result := 'C';
    5:  Result := 'F';
    6:  Result := 'v';
    7:  Result := 'T';
    8:  Result := 'I';
    9:  Result := 'U';
    10: Result := 'p';
    13: Result := 'e';
    22: Result := 'R';
  else
    Result := '.';
  end;
end;

{ ---- TDragLintCompletionForm ---- }

constructor TDragLintCompletionForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption     := '';
  BorderStyle := bsNone;
  FormStyle   := fsStayOnTop;
  Color       := clWindow;
  KeyPreview  := True;
  Position    := poDesigned;

  OnKeyDown := FormKeyDown;

  FListBox := TListBox.Create(Self);
  FListBox.Parent      := Self;
  FListBox.Align       := alClient;
  FListBox.BorderStyle := bsNone;
  FListBox.Font.Name   := 'Consolas';
  FListBox.Font.Size   := 9;
  FListBox.TabStop     := False;
  FListBox.OnDblClick  := ListBoxDblClick;
end;

procedure TDragLintCompletionForm.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action := caFree;
end;

procedure TDragLintCompletionForm.Deactivate;
begin
  inherited;
  Close;
end;

procedure TDragLintCompletionForm.FormKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        Close;
      end;
    VK_RETURN:
      begin
        Key := 0;
        DoInsertSelected;
      end;
    VK_UP, VK_DOWN:
      begin
        { let the ListBox handle arrow keys }
        FListBox.SetFocus;
      end;
  end;
end;

procedure TDragLintCompletionForm.ListBoxDblClick(Sender: TObject);
begin
  DoInsertSelected;
end;

procedure TDragLintCompletionForm.DoInsertSelected;
var
  Idx: Integer;
begin
  Idx := FListBox.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FInsertTexts)) then
  begin
    if Assigned(FOnInsert) then
      FOnInsert(FInsertTexts[Idx]);
    Close;
  end;
end;

procedure TDragLintCompletionForm.ShowAt(X, Y: Integer; AItems: TJSONArray;
  const AOnInsert: TCompletionInsertCallback);
const
  MAX_DETAIL = 60;
  MAX_H      = 320;
  ROW_H      = 18;
  PAD        = 40;
  MIN_W      = 250;
var
  i:          Integer;
  ItemObj:    TJSONObject;
  LabelStr:   string;
  DetailStr:  string;
  InsertStr:  string;
  KindInt:    Integer;
  DisplayStr: string;
  MaxW:       Integer;
  W, H:       Integer;
  Count:      Integer;
  MonR:       TRect;
begin
  FOnInsert := AOnInsert;
  FListBox.Items.BeginUpdate;
  try
    FListBox.Items.Clear;
    Count := 0;
    if AItems <> nil then
      Count := AItems.Count;
    SetLength(FInsertTexts, Count);
    MaxW := 0;

    for i := 0 to Count - 1 do
    begin
      LabelStr  := '';
      DetailStr := '';
      InsertStr := '';
      KindInt   := 0;

      if AItems.Items[i] is TJSONObject then
      begin
        ItemObj := AItems.Items[i] as TJSONObject;
        ItemObj.TryGetValue<string>('label',      LabelStr);
        ItemObj.TryGetValue<string>('detail',     DetailStr);
        ItemObj.TryGetValue<string>('insertText', InsertStr);
        ItemObj.TryGetValue<Integer>('kind',      KindInt);
      end;

      if InsertStr = '' then
        InsertStr := LabelStr;
      FInsertTexts[i] := InsertStr;

      if Length(DetailStr) > MAX_DETAIL then
        DetailStr := Copy(DetailStr, 1, MAX_DETAIL) + '...';

      DisplayStr := KindGlyph(KindInt) + ' ' + LabelStr;
      if DetailStr <> '' then
        DisplayStr := DisplayStr + ' - ' + DetailStr;

      FListBox.Items.Add(DisplayStr);
      if Length(DisplayStr) > MaxW then
        MaxW := Length(DisplayStr);
    end;
  finally
    FListBox.Items.EndUpdate;
  end;

  if FListBox.Items.Count > 0 then
    FListBox.ItemIndex := 0;

  { Size: width heuristic ~7px/char (Consolas 9pt) }
  W := MaxW * 7 + PAD;
  if W < MIN_W then W := MIN_W;

  H := Count * ROW_H + 12;
  if H > MAX_H then H := MAX_H;
  if H < ROW_H + 12 then H := ROW_H + 12;

  Width  := W;
  Height := H;

  { Clamp to work area }
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X := MonR.Right  - W;
    if Y + H > MonR.Bottom then Y := MonR.Bottom - H;
    if X < MonR.Left then X := MonR.Left;
    if Y < MonR.Top  then Y := MonR.Top;
  end;

  Left := X;
  Top  := Y;

  Show;
end;

{ ---- public factory ---- }

procedure ShowDragLintCompletion(AItems: TJSONArray;
  AScreenX, AScreenY: Integer; const AOnInsert: TCompletionInsertCallback);
var
  Form: TDragLintCompletionForm;
begin
  Form := TDragLintCompletionForm.Create(Application);
  Form.ShowAt(AScreenX, AScreenY, AItems, AOnInsert);
end;

end.
