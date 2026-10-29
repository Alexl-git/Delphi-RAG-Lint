unit DragLint.Plugin.MissingUses;

{ The Ctrl+Alt+U quick-fix for the engine rule unit-missing-from-uses: reads the
  unit AND the section the engine decided (interface when the name is used
  there, redirected to implementation when the interface edge would close a
  circular unit reference) out of the cached diagnostic on the caret line, and
  inserts it with the same TUsesText.BuildInsertion the engine's LSP code
  action and `lint --fix` use -- so the IDE and the engine cannot disagree on
  where the unit goes. Kept out of DragLint.Plugin.Editor on purpose: that unit
  is being rewritten on a parallel branch; Editor calls two routines here. }

interface

uses
  DRagLint.Core.UsesInsert;

/// <summary>The unit-missing-from-uses suggestion on the caret line, if any.</summary>
/// <param name="AUnit">Out: the unit to add.</param>
/// <param name="ASection">Out: the uses clause the engine chose.</param>
/// <returns>False when no cached diagnostic on the caret line carries the rule's message.</returns>
/// <remarks>Reads the diagnostic cache only (LSP publishDiagnostics / live lint); never runs the engine.</remarks>
function DLCursorMissingUses(out AUnit: string; out ASection: TUsesSection): Boolean;

/// <summary>Adds AUnit to the ASection uses clause of the active editor buffer
/// as one undoable edit, creating the clause when the section has none.</summary>
/// <param name="AUnit">The unit name to add.</param>
/// <param name="ASection">The target clause.</param>
/// <param name="AInserted">Out: AUnit when inserted, else ''.</param>
/// <returns>False when there is no active buffer, the unit is already listed,
/// or the buffer has no such section keyword.</returns>
function DLAddUnitToUsesSection(const AUnit: string; ASection: TUsesSection; out AInserted: string): Boolean;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  DragLint.Plugin.DiagnosticCache;

const
  READ_CHUNK = 16384; { bytes per IOTAEditReader.GetText call }

function ActiveBuffer(out ABuffer: IOTAEditBuffer; out AText: string): Boolean;
var
  ESS   : IOTAEditorServices;
  EV    : IOTAEditView;
  Reader: IOTAEditReader;
  Buf   : TBytes;
  Chunk : array[0..READ_CHUNK - 1] of AnsiChar;
  At    : Integer;
  N     : Integer;
begin
  Result := False;
  ABuffer:= nil;
  AText  := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  ABuffer:= EV.Buffer;
  Reader := ABuffer.CreateReader;
  if Reader = nil then Exit;
  Buf:= nil;
  At := 0;
  repeat
    N:= Reader.GetText(At, Chunk, SizeOf(Chunk));
    if N <= 0 then Break;
    SetLength(Buf, Length(Buf) + N);
    Move(Chunk[0], Buf[Length(Buf) - N], N);
    Inc(At, N);
  until False;
  Reader:= nil;
  AText := TEncoding.ANSI.GetString(Buf);
  Result:= True;
end;

function DLCursorMissingUses(out AUnit: string; out ASection: TUsesSection): Boolean;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView;
begin
  Result  := False;
  AUnit   := '';
  ASection:= usImplementation;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  for var D: TDragLintDiagnostic in Cache.GetForLine(EV.Buffer.FileName, EV.Position.Row - 1) do
    if TUsesText.ParseMessage(D.Message, AUnit, ASection) then Exit(True);
end;

function DLAddUnitToUsesSection(const AUnit: string; ASection: TUsesSection; out AInserted: string): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text  : string;
  Ins   : TUsesInsertion;
begin
  Result   := False;
  AInserted:= '';
  if not ActiveBuffer(Buffer, Text) then Exit;
  var Lines: TArray<string>:= Text.Replace(#13#10, #10).Split([#10]);
  if not TUsesText.BuildInsertion(Lines, [AUnit], ASection, Ins) then Exit;
  { byte offset of (Line, Col): the buffer is the ANSI text just read, so a
    character is a byte; line breaks are counted as they are in the buffer. }
  var Row: Integer:= 1;
  var I: Integer:= 1;
  while (Row < Ins.Line) and (I <= Length(Text)) do
  begin
    if Text[I] = #10 then Inc(Row);
    Inc(I);
  end;
  if Row <> Ins.Line then Exit;
  var Offset: Integer:= (I - 1) + (Ins.Col - 1);
  var Writer: IOTAEditWriter:= Buffer.CreateUndoableWriter;
  if Writer = nil then Exit;
  Writer.CopyTo(Offset);
  Writer.Insert(PAnsiChar(AnsiString(Ins.Text)));
  Writer:= nil;
  AInserted:= AUnit;
  Result   := True;
end;

end.
