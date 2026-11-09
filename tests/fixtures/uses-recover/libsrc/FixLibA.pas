unit FixLibA;

{ uses-recover fixture: the sourceless library unit the probe uses. Interface uses FixLibB + FixRtl,
  implementation uses FixLibC (a header lists only the first two). }

interface

uses
  FixLibB, FixRtl;

function MakeLibB: TLibB;

implementation

uses
  FixLibC;

function MakeLibB: TLibB;
begin
  Result:= TLibB.Create;
  if LibCValue < 0 then Result.Free;
end;

end.
