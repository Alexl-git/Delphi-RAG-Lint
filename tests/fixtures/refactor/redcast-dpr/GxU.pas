unit GxU;

// Redundant-cast .dpr-global fixture (wave 150 T4 G5). Markers as in redcast\RcUse.pas.

interface

type
  TGxBase = class
    procedure Foo;
  end;

// A unit-level routine that shares its name with the program symbol: the program symbol must not count as an overload.
function Gx: TGxBase;
function GxUOv(pAt: Integer): TGxBase; overload;
function GxUOv(const pAt: string): TGxBase; overload;

implementation

procedure TGxBase.Foo;
begin
end;

function Gx: TGxBase;
begin
  Result:= nil;
end;

function GxUOv(pAt: Integer): TGxBase;
begin
  Result:= nil;
end;

function GxUOv(const pAt: string): TGxBase;
begin
  Result:= nil;
end;

end.
