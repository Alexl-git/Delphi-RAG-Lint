unit uExtB2;

{ drag-lint 1.56 lane EXT-B2 (B4) fixture: data flows through raise and except handlers.
  Read by tests\autotest\run_v156_EXTB2_exc.ps1 through the M-* markers (one per line).
  Not compiled; 7-bit ASCII, CRLF. }

interface

uses
  System.SysUtils;

type
  EProbe = class(Exception);
  EOther = class(Exception);

procedure Sink(const S: string);
procedure RaiseArg(const Msg: string);
procedure RaiseFmt(const Name: string; Code: Integer);
procedure RaiseQualified(const Msg: string);
procedure RaiseLiteral;
procedure HandleLog;
function HandleResult: string;
procedure Reraise;
procedure Wrap;
procedure RaiseVar;
procedure BareExcept;
procedure Nested;
procedure Outside(E: Exception);
procedure AfterHandler(const P: string);
procedure MemberNamedE(const P: TObject);

implementation

procedure Sink(const S: string);
begin
end;

procedure RaiseArg(const Msg: string);
begin
  raise EProbe.Create(Msg); { M-RAISE }
end;

procedure RaiseFmt(const Name: string; Code: Integer);
begin
  raise EProbe.CreateFmt('%s failed with %d', [Name, Code]); { M-FMT }
end;

procedure RaiseQualified(const Msg: string);
begin
  raise uExtB2.EProbe.Create(Msg); { M-QUAL }
end;

procedure RaiseLiteral;
begin
  raise EProbe.Create('fixed text'); { M-LIT }
end;

procedure HandleLog;
begin
  try
    Sink('x');
  except
    on E: EProbe do { M-ON }
      Sink(E.Message); { M-ON-SINK }
  end;
end;

function HandleResult: string;
var
  S: string;
begin
  Result := '';
  try
    Sink('x');
  except
    on E: EOther do { M-RES-ON }
    begin
      S := E.Message;
      Result := S;
    end;
  end;
end;

procedure Reraise;
begin
  try
    Sink('x');
  except
    on E: EProbe do { M-RE-ON }
    begin
      Sink('log');
      raise; { M-RERAISE }
    end;
  end;
end;

procedure Wrap;
begin
  try
    Sink('x');
  except
    on E: EProbe do { M-WRAP-ON }
      raise EOther.Create('wrapped: ' + E.Message); { M-WRAP }
  end;
end;

procedure RaiseVar;
begin
  try
    Sink('x');
  except
    on E: EProbe do { M-VAR-ON }
      raise E; { M-VAR }
  end;
end;

procedure BareExcept;
begin
  try
    Sink('x');
  except { M-BARE }
    Sink(Exception(ExceptObject).Message); { M-BARE-SINK }
    raise; { M-BARE-RAISE }
  end;
end;

procedure Nested;
begin
  try
    Sink('x');
  except
    on E: EProbe do { M-OUTER-ON }
      try
        Sink(E.Message); { M-OUTER-SINK }
      except
        on E: EOther do { M-INNER-ON }
          Sink(E.Message); { M-INNER-SINK }
      end;
  end;
end;

procedure Outside(E: Exception);
begin
  Sink(E.Message); { M-OUT }
end;

procedure AfterHandler(const P: string);
var
  E: string;
begin
  try
    Sink('x');
  except
    on E: EProbe do
      Sink('h');
  end;
  E := P;
  Sink(E); { M-AFTER }
end;

procedure MemberNamedE(const P: TObject);
begin
  try
    Sink('x');
  except
    on E: EProbe do
      Sink(P.E); { M-MEMBER }
  end;
end;

end.
