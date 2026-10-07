program DfmLoadCheck;

{ The standing .dfm LOAD guard of the convert suites (1.25.2). A dry run proves
  the PLAN, never the BYTES: a .dfm convert-apply writes is accepted only if
  Delphi's own text reader takes it. For each path given:
    text -> binary (ObjectTextToBinary, what the IDE / dcc do to load a form)
    binary -> text (ObjectBinaryToText) -> binary again, byte-identical.
  Prints one line per file, 'OK <path>' or 'FAIL <path>: <Class>: <message>',
  and exits 1 when any file failed. Built on demand by DfmLoadCheck.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes;

function CheckOne(const APath: string; out AWhy: string): Boolean;
var
  Src, Bin1, Txt, Bin2: TMemoryStream;
begin
  AWhy:= '';
  Src := TMemoryStream.Create;
  Bin1:= TMemoryStream.Create;
  Txt := TMemoryStream.Create;
  Bin2:= TMemoryStream.Create;
  try
    try
      Src.LoadFromFile(APath);
      ObjectTextToBinary(Src, Bin1);
      Bin1.Position:= 0;
      ObjectBinaryToText(Bin1, Txt);
      Txt.Position:= 0;
      ObjectTextToBinary(Txt, Bin2);
      Result:= (Bin1.Size = Bin2.Size) and CompareMem(Bin1.Memory, Bin2.Memory, Bin1.Size);
      if not Result then AWhy:= 'binary -> text -> binary is not byte-identical';
    except
      on E: Exception do
      begin
        AWhy  := E.ClassName + ': ' + E.Message;
        Result:= False;
      end;
    end;
  finally
    Bin2.Free;
    Txt.Free;
    Bin1.Free;
    Src.Free;
  end;
end;

var
  Why: string;
begin
  ExitCode:= 0;
  for var I: Integer:= 1 to ParamCount do
    if CheckOne(ParamStr(I), Why) then
      Writeln('OK ', ParamStr(I))
    else
    begin
      Writeln('FAIL ', ParamStr(I), ': ', Why);
      ExitCode:= 1;
    end;
end.
