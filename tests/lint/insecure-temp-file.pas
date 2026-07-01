unit InsecureTempFile;

interface

implementation

uses System.Classes, System.SysUtils;

procedure WritesToHardcodedTemp;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.SaveToFile('C:\Temp\secrets.txt');
  finally
    sl.Free;
  end;
end;

procedure WritesToProperLocation;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.SaveToFile(TPath.GetTempFileName);
  finally
    sl.Free;
  end;
end;

procedure TempPathInAMessageOnly;
begin
  ShowMessage('Files go in C:\Temp\ by default');
end;

end.
