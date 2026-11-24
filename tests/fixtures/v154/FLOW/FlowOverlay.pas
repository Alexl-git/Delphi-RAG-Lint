unit FlowOverlay;

// absolute-overlay (G-39)

interface

type
  TRoot = class
  end;

var
  GRoot: TRoot;
  GSame: TObject absolute GRoot;
  GBytes: array[0..3] of Byte;
  GAlias: Integer absolute GBytes; // FIRE absolute-overlay

type
  TShape = class
  end;
  TCircle = class(TShape)
  public
    R: Integer;
  end;
  TSize4 = record
    W: Integer;
  end;

procedure Typed(var N: Integer);
procedure Refs(AShape: TShape; const AObject: TObject);
procedure Raw(var Buf; const Src);

implementation

procedure Typed(var N: Integer);
var
  W: array[0..1] of Word absolute N; // FIRE absolute-overlay
  L: Single;
  I: Integer absolute L; // FIRE absolute-overlay
begin
  L := 1;
  W[0] := I and $FF;
end;

procedure Refs(AShape: TShape; const AObject: TObject);
var
  LCircle: TCircle absolute AShape;
  LOther: TCircle absolute AObject;
  LSize: TSize4 absolute AShape; // FIRE absolute-overlay
  LAddress: NativeUInt absolute AObject; // FIRE absolute-overlay
begin
  if AShape is TCircle then LCircle.R := LSize.W;
  if LAddress > 0 then LOther.R := 1;
end;

procedure Raw(var Buf; const Src);
var
  B: array[0..7] of Byte absolute Buf;
  S: array[0..7] of Byte absolute Src;
  K: Integer;

  procedure Inner;
  var
    C: array[0..3] of Word absolute Buf;
  begin
    C[0] := 1;
  end;

begin
  Inner;
  for K := 0 to 7 do
    B[K] := S[K];
end;

end.