unit UnsignedCmp;

interface

implementation

procedure Bad(pLen: Cardinal);
var
  B: Byte;
  W: Word;
  N: Integer;
begin
  if pLen >= 0 then N := 1;
  if B < 0 then N := 2;
  if W >= 0 then N := 3;
  if N >= 0 then N := 4;
  if pLen > 0 then N := 5;
  if pLen >= 1 then N := 6;
  if N < 0 then N := 7;
end;

type
  TRec = class
    FCount: Cardinal;
    procedure Run;
  end;

procedure TRec.Run;
var
  N: Integer;
begin
  { Known FP shape: a FIELD or unit global has no visible declaration in the
    routine, so #declared-type? stays silent (no guess). }
  if FCount >= 0 then N := 8;
end;

end.
