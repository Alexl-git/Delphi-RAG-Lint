program SolveUnknown;

{ check-init fixture solve-unknown (lane HBSOLVER, owner ruling 2026-11-17 13:56): FillExternal has no
  source in the index. GUnk = the UNKNOWN-CALLEE warning; GRead / GSets = the answer recorded once on
  the call line; GExempt goes only to a read-only RTL routine (exempt: no warning, NEVER-SET). }

uses
  suData in 'suData.pas';

begin
  FillExternal(GUnk); // CALL-UNKNOWN
  FillExternal(GRead); // dl:callee-reads
  FillExternal(GSets); // dl:callee-sets
  Writeln(IntToStr(GExempt)); // USE-EXEMPT
  UseAll;
end.
