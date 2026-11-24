unit FlowOverlay;

// absolute-overlay (G-39)

interface

var
  GBytes: array[0..3] of Byte;
  GAlias: Integer absolute GBytes; // FIRE absolute-overlay

procedure Typed(var N: Integer);
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