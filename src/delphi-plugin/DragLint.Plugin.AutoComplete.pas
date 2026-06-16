unit DragLint.Plugin.AutoComplete;

{ v0.46: automatic completion trigger.

  The IDE's own completion can get "stuck"; ours is a reliable backup. This unit
  pops the existing (scrollable) completion list automatically when the user
  types a '.', WITHOUT hijacking the keystroke -- it reacts to the edit-view
  Modified notification, debounces ~220 ms (so it fires when the user pauses,
  not on every keypress), then checks whether the character immediately before
  the caret is a '.' and, if so, calls the SILENT completion path
  (InvokeCompletionAuto: no dialogs, short timeout, only pops when there are
  items). Guarded so it never disturbs typing or surfaces an exception. }

interface

procedure StartAutoComplete;
procedure StopAutoComplete;
{ Called from the edit-view Modified hook (EditViewNotifier). }
procedure NotifyEditForAutoComplete;

implementation

uses
  System.SysUtils, System.Classes,
  Winapi.Windows,
  Vcl.ExtCtrls,
  ToolsAPI,
  DragLint.Plugin.Settings,
  DragLint.Plugin.Editor;

type
  TAutoCompleter = class
  private
    FTimer: TTimer;
    FDirty: Boolean;
    FTick:  Cardinal;
    procedure OnTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Notify;
  end;

var
  GAuto: TAutoCompleter = nil;

function IdeIsForeground: Boolean;
var
  Fg:  HWND;
  Pid: DWORD;
begin
  Result := False;
  Fg := GetForegroundWindow;
  if Fg = 0 then Exit;
  Pid := 0;
  GetWindowThreadProcessId(Fg, Pid);
  Result := (Pid <> 0) and (Pid = GetCurrentProcessId);
end;

function CaretPrecededByDot: Boolean;
var
  ESS:    IOTAEditorServices;
  EV:     IOTAEditView;
  Reader: IOTAEditReader;
  Buf:    array[0..2047] of AnsiChar;
  CaretRow, CaretCol, Read, LineStartPos, Pos, CurRow, I, EolIdx: Integer;
  LineText: string;
begin
  Result := False;
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EV := ESS.TopView;
    if (EV = nil) or (EV.Buffer = nil) then Exit;
    CaretRow := EV.Position.Row;
    CaretCol := EV.Position.Column;
    if (CaretRow <= 0) or (CaretCol <= 1) then Exit;
    Reader := EV.Buffer.CreateReader;
    if Reader = nil then Exit;

    { Walk to the caret line's start (buffer is character-addressed). }
    LineStartPos := 0; CurRow := 1; Pos := 0;
    while CurRow < CaretRow do
    begin
      Read := Reader.GetText(Pos, Buf, SizeOf(Buf));
      if Read <= 0 then Exit;
      for I := 0 to Read - 1 do
        if Buf[I] = #10 then
        begin
          Inc(CurRow);
          if CurRow = CaretRow then
          begin
            LineStartPos := Pos + I + 1;
            Break;
          end;
        end;
      if CurRow >= CaretRow then Break;
      Inc(Pos, Read);
    end;

    Read := Reader.GetText(LineStartPos, Buf, SizeOf(Buf));
    if Read <= 0 then Exit;
    EolIdx := 0;
    while (EolIdx < Read) and not (Buf[EolIdx] in [#10, #13]) do Inc(EolIdx);
    SetString(LineText, PAnsiChar(@Buf[0]), EolIdx);

    { char immediately before the caret = LineText[CaretCol - 1] (1-based) }
    if (CaretCol - 1 >= 1) and (CaretCol - 1 <= Length(LineText)) then
      Result := LineText[CaretCol - 1] = '.';
  except
    Result := False;
  end;
end;

constructor TAutoCompleter.Create;
begin
  inherited;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer  := OnTick;
  FTimer.Enabled  := True;
end;

destructor TAutoCompleter.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TAutoCompleter.Notify;
begin
  FDirty := True;
  FTick  := GetTickCount;
end;

procedure TAutoCompleter.OnTick(Sender: TObject);
begin
  try
    if not FDirty then Exit;
    if GetTickCount - FTick < 220 then Exit;   { debounce: fire after a pause }
    FDirty := False;
    if not LoadSettings.EnableCompletion then Exit;
    if not IdeIsForeground then Exit;
    if CaretPrecededByDot then
      try InvokeCompletionAuto; except end;
  except
    { never let a timer exception surface inside the IDE }
  end;
end;

procedure StartAutoComplete;
begin
  if GAuto = nil then
    GAuto := TAutoCompleter.Create;
end;

procedure StopAutoComplete;
begin
  FreeAndNil(GAuto);
end;

procedure NotifyEditForAutoComplete;
begin
  if GAuto <> nil then
    GAuto.Notify;
end;

initialization

finalization
  StopAutoComplete;

end.
