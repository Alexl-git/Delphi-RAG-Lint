program Probe;
{$APPTYPE CONSOLE}
uses System.SysUtils;

procedure Fail(const AText: string); noreturn;
begin
  raise Exception.Create(AText);
end;

procedure Plain;
begin
end;

procedure FallsOff(const AText: string); noreturn;
begin
  if AText <> '' then
    raise Exception.Create(AText);
end;

procedure EndsInPlain; noreturn;
begin
  Plain;
end;

procedure UsesExit(A: Integer); noreturn;
begin
  if A = 1 then Exit;
  Fail('x');
end;

function AfterCall(A: Integer): Integer;
begin
  if A = 1 then Exit(1);
  Fail('x');
  Result := 2;
end;

function NoResult(A: Integer): Integer;
begin
  if A = 1 then Exit(1);
  Fail('x');
end;

type
  TBase = class
    procedure Stop; virtual; noreturn;
  end;
  TDer = class(TBase)
    procedure Stop; override;
  end;
  IStop = interface
    procedure Halt2; noreturn;
  end;

procedure TBase.Stop;
begin
  raise Exception.Create('s');
end;

procedure TDer.Stop;
begin
end;

function F2: Integer; noreturn;
begin
  raise Exception.Create('s');
end;

begin
  Writeln(AfterCall(1), NoResult(1));
end.
