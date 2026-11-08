unit EiUse;

interface

procedure RunAll;

implementation

uses
  EiWidget;

procedure RunAll;
begin
  var W:= TEiWidget.Make;
  try
    W.Tag:= 1;
    W.Count:= W.Sum(2, 3);
    W.Over(4);
    W.Over('five');
    Writeln(W.Value, ' ', W.Count, ' ', W.Virt, ' ', W.Direct, ' ', W.Conv(ekTwo), ' ', W.KindOf(TEiWidget.TKind.kB), ' ', W.Gen<Integer>(9));
    var C:= W.Clone;
    Writeln(C.Count);
    C.Free;
  finally
    W.Free;
  end;
  var D:= TEiDesc.Create;
  D.Go;
  Writeln(D.Virt, ' ', D.Value);
  D.Free;
  var P:= TEiPlain.Create;
  Writeln(P.Ping);
  P.Free;
  var E:= TEiDeep.Create;
  Writeln(E.Pong);
  E.Free;
  var B:= TEiBroken.Create;
  Writeln(B.Item(1));
  B.Free;
end;

end.