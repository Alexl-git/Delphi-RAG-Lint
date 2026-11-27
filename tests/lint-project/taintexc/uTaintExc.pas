unit uTaintExc;

{ drag-lint 1.56 lane FA-2 fixture: taint through exceptions (a tainted value raised in one
  routine reaches a sink in a handler of a caller). Read by tests\autotest\run_v156_FA2.ps1
  through the M-* markers (one per line). Sources and sinks are the built-in catalogue
  (ParamStr -> .SQL.Text). Not compiled; 7-bit ASCII, CRLF. }

interface

uses
  System.SysUtils, System.Classes;

type
  ETaint      = class(Exception);
  ETaintChild = class(ETaint);
  EOther      = class(Exception);
  EParam      = class(Exception);
  ESan        = class(Exception);
  ELit        = class(Exception);

  TQ = class
  public
    SQL: TStrings;
  end;

procedure RaiseTainted;
procedure RaiseChild;
procedure RaiseParam(const S: string);
procedure RaiseSanitised;
procedure RaiseLiteral;
procedure Mid;
procedure CatchSameClass(Q: TQ);
procedure CatchTwoHops(Q: TQ);
procedure CatchAncestor(Q: TQ);
procedure CatchViaParam(Q: TQ);
procedure CatchViaLocal(Q: TQ);
procedure CatchOtherClass(Q: TQ);
procedure CatchUnreachable(Q: TQ);
procedure CatchSanitised(Q: TQ);
procedure CatchLiteral(Q: TQ);
procedure CatchNoSink(Q: TQ);
procedure Direct(Q: TQ);

implementation

procedure RaiseTainted;
begin
  raise ETaint.Create('select ' + ParamStr(1)); { M-RAISE }
end;

procedure RaiseChild;
begin
  raise ETaintChild.Create(ParamStr(2)); { M-RAISE-CHILD }
end;

procedure RaiseParam(const S: string);
begin
  raise EParam.Create(S); { M-RAISE-PARAM }
end;

procedure RaiseSanitised;
begin
  raise ESan.Create(QuotedStr(ParamStr(1)));
end;

procedure RaiseLiteral;
begin
  raise ELit.Create('fixed text');
end;

procedure Mid;
begin
  RaiseTainted;
end;

procedure CatchSameClass(Q: TQ);
begin
  try
    RaiseTainted;
  except
    on E: ETaint do
      Q.SQL.Text := E.Message; { M-POS-SAME }
  end;
end;

procedure CatchTwoHops(Q: TQ);
begin
  try
    Mid;
  except
    on E: ETaint do
      Q.SQL.Text := E.Message; { M-POS-HOPS }
  end;
end;

procedure CatchAncestor(Q: TQ);
begin
  try
    RaiseChild;
  except
    on E: ETaint do
      Q.SQL.Text := E.Message; { M-POS-ANCESTOR }
  end;
end;

procedure CatchViaParam(Q: TQ);
begin
  try
    RaiseParam(ParamStr(3));
  except
    on E: EParam do
      Q.SQL.Text := E.Message; { M-POS-PARAM }
  end;
end;

procedure CatchViaLocal(Q: TQ);
var
  S: string;
begin
  try
    RaiseTainted;
  except
    on E: ETaint do
    begin
      S := E.Message;
      Q.SQL.Text := S; { M-POS-LOCAL }
    end;
  end;
end;

procedure CatchOtherClass(Q: TQ);
begin
  try
    RaiseTainted;
  except
    on E: EOther do
      Q.SQL.Text := E.Message; { M-NEG-CLASS }
  end;
end;

procedure CatchUnreachable(Q: TQ);
begin
  try
    RaiseLiteral;
  except
    on E: ETaint do
      Q.SQL.Text := E.Message; { M-NEG-UNREACHABLE }
  end;
end;

procedure CatchSanitised(Q: TQ);
begin
  try
    RaiseSanitised;
  except
    on E: ESan do
      Q.SQL.Text := E.Message; { M-NEG-SANITISED }
  end;
end;

procedure CatchLiteral(Q: TQ);
begin
  try
    RaiseLiteral;
  except
    on E: ELit do
      Q.SQL.Text := E.Message; { M-NEG-LITERAL }
  end;
end;

procedure CatchNoSink(Q: TQ);
var
  S: string;
begin
  try
    RaiseTainted;
  except
    on E: ETaint do
      S := E.Message; { M-NEG-NOSINK }
  end;
end;

procedure Direct(Q: TQ);
begin
  Q.SQL.Text := ParamStr(1); { M-CONTROL }
end;

end.
