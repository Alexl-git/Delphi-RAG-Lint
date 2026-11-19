unit UbaApiFill;

interface

implementation

uses
  Winapi.Windows;

{ 1.52.1 SLZ-RULE2: an element of a local buffer handed to a Win32 API whose
  parameter is an untyped `var Buffer` the call FILLS (GitSince.pas:134,
  CompileCheck.pas:419). The control hands it to WriteFile, whose
  `const Buffer` READS it: that must keep firing. }

function ApiFill(AHandle: THandle): Integer;
var
  Buf : array[0..63] of AnsiChar;
  Got : DWORD;
begin
  Result := 0;
  Got := 0;
  if not ReadFile(AHandle, Buf[0], SizeOf(Buf) - 1, Got, nil) then Exit;
  Result := Ord(Buf[0]) + Integer(Got);
end;

function CtlApiReadsBuffer(AHandle: THandle): Integer;
var
  Buf : array[0..63] of AnsiChar;
  Sent: DWORD;
begin
  Result := 0;
  Sent := 0;
  if not WriteFile(AHandle, Buf[0], SizeOf(Buf), Sent, nil) then Exit;
  Result := Integer(Sent);
end;

end.