unit uMustWrites;

{ Fixture of tests\autotest\run_v156_EXTC1_mustwrites.ps1 (1.56 B5, lane EXT-C1): one routine per
  must-write shape. The expected symbol_facts.must_writes value of every routine is in the runner,
  not here, so that this file stays plain compilable Pascal. Each "proven" routine has a twin
  that differs by one construct and must NOT be proven. }

interface

uses
  System.SysUtils;

type
  TMwRec = record
    X: Integer;
  end;

  TMwOther = class
  public
    FA: Integer;
  end;

  TMw = class
  private
    FA: Integer;
    FB: Integer;
    FObj: TObject;
    FOther: TMwOther;
  public
    constructor Create;
    function Always(pIn: Integer; out pOut: Integer): Integer;
    function Conditional(pIn: Integer): Integer;
    function BothBranches(pIn: Integer): Integer;
    procedure EarlyExit(pIn: Integer);
    function ExitValue(pIn: Integer): Integer;
    procedure RaisePath(pIn: Integer);
    procedure TryExceptBody(const pText: string);
    procedure TryExceptBoth(const pText: string);
    procedure Swallow(const pText: string);
    procedure TryFinally;
    procedure Loops(pIn: Integer);
    procedure NilWrite;
    procedure SelfDot;
    procedure Shadow;
    procedure WithOpaque;
    procedure Partial(out pRec: TMwRec; var pVar: Integer; pVal: Integer);
    procedure Lambda;
    procedure CaseNoElse(pIn: Integer);
    procedure CaseElse(pIn: Integer);
    procedure AfterSwallow(const pText: string);
  end;

function OldStyle(pIn: Integer): Integer;
procedure FreeOut(out pOut: Integer; pIn: Integer);
procedure FreeOutMaybe(out pOut: Integer; pIn: Integer);

implementation

constructor TMw.Create;
begin
  inherited Create;
  FA := 1;
  FObj := TObject.Create;
end;

function TMw.Always(pIn: Integer; out pOut: Integer): Integer;
begin
  FA := pIn;
  pOut := 1;
  Result := 2;
end;

function TMw.Conditional(pIn: Integer): Integer;
begin
  if pIn > 0 then
    FA := 1;
  Result := 0;
end;

function TMw.BothBranches(pIn: Integer): Integer;
begin
  if pIn > 0 then
  begin
    FA := 1;
    Result := 1;
  end
  else
  begin
    FA := 2;
    Result := 2;
  end;
end;

procedure TMw.EarlyExit(pIn: Integer);
begin
  if pIn = 0 then
    Exit;
  FA := 1;
end;

function TMw.ExitValue(pIn: Integer): Integer;
begin
  if pIn = 0 then
    Exit(5);
  Result := 1;
end;

procedure TMw.RaisePath(pIn: Integer);
begin
  if pIn < 0 then
    raise Exception.Create('negative');
  FA := 1;
end;

procedure TMw.TryExceptBody(const pText: string);
begin
  try
    FA := StrToInt(pText);
  except
    on E: Exception do
      FB := 1;
  end;
end;

procedure TMw.TryExceptBoth(const pText: string);
begin
  try
    FA := StrToInt(pText);
  except
    on E: Exception do
      FA := 2;
  end;
end;

procedure TMw.Swallow(const pText: string);
begin
  try
    FB := StrToInt(pText);
    FA := 1;
  except
  end;
end;

procedure TMw.TryFinally;
begin
  try
    FA := 1;
  finally
    FB := 2;
  end;
end;

procedure TMw.Loops(pIn: Integer);
begin
  while pIn > 0 do
  begin
    FA := 1;
    Dec(pIn);
  end;
  repeat
    FB := 1;
  until pIn <= 0;
end;

procedure TMw.NilWrite;
begin
  FObj := nil;
end;

procedure TMw.SelfDot;
begin
  Self.FA := 1;
  FOther.FA := 2;
end;

procedure TMw.Shadow;
var
  FA: Integer;
begin
  FA := 1;
  FB := FA;
end;

procedure TMw.WithOpaque;
begin
  with FOther do
    FA := 1;
end;

procedure TMw.Partial(out pRec: TMwRec; var pVar: Integer; pVal: Integer);
begin
  pRec.X := 1;
  pVar := 2;
  pVal := 3;
end;

procedure TMw.Lambda;
var
  P: TProc;
begin
  P := procedure
    begin
      FA := 1;
    end;
  FB := 2;
  P();
end;

procedure TMw.CaseNoElse(pIn: Integer);
begin
  case pIn of
    1: FA := 1;
    2: FA := 2;
  end;
end;

procedure TMw.CaseElse(pIn: Integer);
begin
  case pIn of
    1: FA := 1;
    2: FA := 2;
  else
    FA := 3;
  end;
end;

procedure TMw.AfterSwallow(const pText: string);
begin
  try
    FB := StrToInt(pText);
  except
  end;
  FA := 1;
end;

function OldStyle(pIn: Integer): Integer;
begin
  OldStyle := pIn + 1;
end;

procedure FreeOut(out pOut: Integer; pIn: Integer);
begin
  if pIn > 0 then
    pOut := 1
  else
    pOut := 2;
end;

procedure FreeOutMaybe(out pOut: Integer; pIn: Integer);
begin
  if pIn > 0 then
    pOut := 1;
end;

end.
