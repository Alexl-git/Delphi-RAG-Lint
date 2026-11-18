program SolveMainBlock;

{ check-init fixture solve-mainblock (lane HBSOLVER): GMain is written in the program block BEFORE the
  call that reads it, GLate only AFTER (the MAY twin). }

uses
  smData in 'smData.pas';

begin
  GMain:= 1;
  UseMain;
  UseLate;
  GLate:= 1;
end.
