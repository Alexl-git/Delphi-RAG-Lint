unit uFixTaint;

interface

uses
  System.SysUtils, System.Classes;

procedure IntValueNoFire(ALen: Integer);
procedure LenPathNoFire;
procedure LenCmdNoFire;
procedure StrPathFires;
procedure OpenSqlNotPath;
procedure OpenConstNoFire;
procedure ProjectMethodSink;
procedure ExternalSink;
procedure HandlerNoFire;
procedure DupSite;

implementation

type
  ETx = class(Exception);
  TQ  = class
  public
    SQL: TStrings;
  end;
  TFDQuery = class
    procedure Open(const ASQL: string);
  end;
  TRunner = class
    procedure WinExec(const ACmd: string);
  end;

function WinExec(ACmd: PAnsiChar; AShow: Cardinal): Cardinal; stdcall; external 'kernel32.dll';

procedure TFDQuery.Open(const ASQL: string);
begin
end;

procedure TRunner.WinExec(const ACmd: string);
begin
end;

procedure IntValueNoFire(ALen: Integer);
begin
  DeleteFile(IntToStr(ALen));                          { INTVAL }
end;

procedure LenPathNoFire;
var
  N: Integer;
begin
  N:= Length(GetEnvironmentVariable('X'));
  DeleteFile(IntToStr(N));                             { LENPATH }
end;

procedure LenCmdNoFire;
var
  N: Integer;
begin
  N:= Length(ParamStr(1));
  ShellExecute(0, nil, PChar(IntToStr(N)), nil, nil, 0);   { LENCMD }
end;

procedure StrPathFires;
begin
  DeleteFile(GetEnvironmentVariable('X'));             { STRPATH }
end;

procedure OpenSqlNotPath;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create;
  Q.Open('select * from T where N=' + GetEnvironmentVariable('X'));   { OPENSQL }
end;

procedure OpenConstNoFire;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create;
  Q.Open('select 1');                                  { OPENCONST }
end;

procedure ProjectMethodSink;
var
  R: TRunner;
begin
  R:= TRunner.Create;
  R.WinExec(ParamStr(1));                              { PRJSINK }
end;

procedure ExternalSink;
begin
  WinExec(PAnsiChar(AnsiString(ParamStr(1))), 0);       { EXTSINK }
end;

procedure RaiseTx;
begin
  raise ETx.Create(ParamStr(1));
end;

procedure HandlerNoFire;
begin
  try
    RaiseTx;
  except
    on E: ETx do
      DeleteFile(E.Message);                           { HANDLER }
  end;
end;

procedure DupSite;
var
  Q: TQ;
begin
  Q:= TQ.Create;
  try
    RaiseTx;
  except
    on E: ETx do
      Q.SQL.Text:= E.Message + ParamStr(2);            { DUP }
  end;
end;

end.
