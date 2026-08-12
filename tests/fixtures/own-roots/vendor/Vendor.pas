unit Vendor;

interface

procedure RunReport(const APath: string);

implementation

uses System.SysUtils, System.Classes;

procedure RunReport(const APath: string);
var
  SL : TStringList;
  I  : Integer    ;
  Acc: Integer    ;
begin
  SL:= TStringList.Create;
  try
    SL.LoadFromFile(APath);
    Acc:= 0;
    for I:= 0 to SL.Count - 1 do
    begin
      if Trim(SL[I]) = '' then Continue;
      if StartsText('#', Trim(SL[I])) then Continue;
      if Length(SL[I]) > 80 then Inc(Acc, 2) else Inc(Acc);
    end;
    if Acc > 100 then Writeln('large: ', Acc)
    else if Acc > 10 then Writeln('medium: ', Acc)
    else Writeln('small: ', Acc);
  finally
    SL.Free;
  end;
end;

end.
