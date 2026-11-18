program SolveCallChain;

{ check-init fixture solve-callchain (lane HBSOLVER): the use is three calls below RunAll; SetData
  dominates RunAll in the program block, SetDataIf runs under an `if` (the MAY twin). }

uses
  scData in 'scData.pas',
  scWork in 'scWork.pas';

begin
  SetData;
  if ParamCount > 0 then
    SetDataIf;
  RunAll;
end.
