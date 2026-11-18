program RecvLocal;

{ check-init fixture recv-local (lane HBRECV): see rlWork.pas. }

uses
  rlWork in 'rlWork.pas';

begin
  RunAll(ParamCount > 0);
end.
