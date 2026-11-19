program FieldsSameWrite;

{ check-init fixture fields-samewrite (lane HBFIX, 1.52; HBMEASURE F4): the constructor does not set
  FSecs, but a method that writes it through Self on every path before its own read reads its own
  write: that use is SET. Twins: a read with no earlier write (MAY), a conditional earlier write (MAY),
  and a read through ANOTHER object after a Self write (MAY: not the same instance). }

uses
  fsRun in 'fsRun.pas';

var
  R: TRun;

begin
  R:= TRun.Create;
  R.Build;
  R.Peek;
  R.Maybe(True);
  R.CopyFrom(R);
end.