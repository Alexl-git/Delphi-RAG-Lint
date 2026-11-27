unit uFb2Arg;

{ Fixture of tests\autotest\run_v156_FB2.ps1 (1.56 lane FB-2, REQUESTS line 47): a NUMERIC unit
  variable passed by reference. Since 1.56 the index also holds VALUE rows (data_flows.val_class):
  `Show(Seen)` has one whose source is GTotal although GTotal is not read on that line. check-init
  must keep its 1.55 events: two writers (the var arguments of the two Fill calls) and two uses
  (`Seen := GTotal` and `Show(GTotal)`). Read as an argument row, the value row takes the read of
  the second Fill call, and the writer moves one line down. }

interface

var
  GTotal: Integer;

procedure Work;

implementation

procedure Fill(var pValue: Integer);
begin
  pValue := 5;
end;

procedure Show(pValue: Integer);
begin
  if pValue > 0 then
    Writeln(pValue);
end;

procedure Work;
var
  Seen: Integer;
begin
  Fill(GTotal);
  Seen := GTotal;
  Show(Seen);
  Fill(GTotal);
  Show(GTotal);
end;

initialization
  Work;

end.
