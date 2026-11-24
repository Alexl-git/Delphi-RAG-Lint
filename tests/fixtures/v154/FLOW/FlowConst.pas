unit FlowConst;

// constant-return (G-31)

interface

uses
  System.SysUtils, FlowOther;

type
  TBase2 = class
  public
    function Virt(A: Integer): Integer; virtual;
    function Own(A: Integer): Integer;
  end;
  TImpl2 = class(TInterfacedObject, ICheck)
  public
    function Allowed(A: Integer): Boolean;
    procedure Adjust(var A: Integer);
  end;

function ThreeWays(N: Integer): Integer;
function ByExit(N: Integer): Boolean;
function Nils(N: Integer): TObject;
function Texts(N: Integer): string;
function Stub(N: Integer): Integer;
function Differ(N: Integer): Integer;
function Raises(N: Integer): Boolean;
function Passed(N: Integer): Integer;
function Changed(N: Integer): Integer;
function Computed(N: Integer): Integer;
function Callback(A: Integer): Boolean;
function NestedSet(N: Integer): Integer;
procedure Use;

implementation

var
  GLog: Integer;

function ThreeWays(N: Integer): Integer; // FIRE constant-return
begin
  if N = 1 then Result := 5
  else if N = 2 then
  begin
    GLog := 1;
    Result := 5;
  end
  else Result := 5;
end;

function ByExit(N: Integer): Boolean; // FIRE constant-return
begin
  Result := False;
  if N = 1 then Exit(False);
  GLog := N;
end;

function Nils(N: Integer): TObject; // FIRE constant-return
begin
  if N > 0 then Exit(nil);
  Result := nil;
end;

function Texts(N: Integer): string; // FIRE constant-return
begin
  case N of
    1: Result := 'a';
  else
    Result := 'a';
  end;
end;

function Stub(N: Integer): Integer;
begin
  Result := 0;
end;

function Differ(N: Integer): Integer;
begin
  Result := 0;
  if N = 1 then Result := 1;
end;

function Raises(N: Integer): Boolean;
begin
  Result := True;
  if N = 1 then raise Exception.Create('x');
  if N = 2 then Exit(True);
end;

function Passed(N: Integer): Integer;
begin
  Result := 0;
  if N = 1 then Result := 0;
  if not TryStrToInt('1', Result) then GLog := 1;
end;

function Changed(N: Integer): Integer;
begin
  Result := 0;
  if N = 1 then Result := 0;
  Inc(Result);
end;

function Computed(N: Integer): Integer;
begin
  if N = 1 then Exit(1);
  Result := N;
end;

function Callback(A: Integer): Boolean;
begin
  Result := True;
  if A = 1 then Exit(True);
  GLog := A;
end;

function NestedSet(N: Integer): Integer;

  procedure Inner;
  begin
    Result := N;
  end;

begin
  Result := 0;
  if N = 1 then Exit(0);
  Inner;
end;

function TBase2.Virt(A: Integer): Integer;
begin
  if A = 1 then Exit(0);
  Result := 0;
end;

function TBase2.Own(A: Integer): Integer; // FIRE constant-return
begin
  if A = 1 then Exit(0);
  Result := 0;
end;

function TImpl2.Allowed(A: Integer): Boolean;
begin
  if A = 1 then Exit(True);
  Result := True;
end;

procedure TImpl2.Adjust(var A: Integer);
begin
  A := 1;
end;

procedure Use;
begin
  RunEnum(Callback);
end;

end.