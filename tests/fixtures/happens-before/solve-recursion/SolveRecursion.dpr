program SolveRecursion;

{ check-init fixture solve-recursion (lane HBSOLVER): SetRec writes before it recurses (MustA, least
  fixpoint); WalkLoop reads at the top of a recursion entered after the write (EntryDone, greatest
  fixpoint); WalkBad writes only in the base case (least fixpoint stays False: MAY, documented). }

uses
  srRec in 'srRec.pas';

begin
  SetRec(3);
  UseRec;
  GLoop:= 1;
  WalkLoop(3);
  WalkBad(3);
  UseBad;
end.
