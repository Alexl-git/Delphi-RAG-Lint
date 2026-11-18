program SolveVirtual;

{ check-init fixture solve-virtual (lane HBSOLVER): Obj.Init dispatches to TBaseInit.Init or an override;
  every override writes GAll, TBInit.Init does not write GPart (the MAY twin). }

uses
  svShapes in 'svShapes.pas';

var
  Obj: TBaseInit;

begin
  Obj:= TAInit.Create;
  Obj.Init;
  UseShapes;
end.
