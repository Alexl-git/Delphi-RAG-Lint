unit uUnusedEnum;

{ unused-enum-value fixture (lane B-ENUM). Each type below names at least one
  value somewhere (so it is a candidate) except TNoneNamed; markers drive the
  runner. }

interface

type
  TMixed = (
    mxRead,      // CONTROL-READ
    mxUnused,    // TRIGGER-UNUSED
    mxAlso);     // TRIGGER-ALSO
  TIterated = (
    itA,
    itB);        // CONTROL-LOWHIGH
  TCastIn = (
    ciA,
    ciB);        // CONTROL-CAST
  TOrdOut = (
    ooA,
    ooB);        // CONTROL-ORD
  TSucced = (
    suA,
    suB);        // CONTROL-SUCC
  TStreamed = (
    stA,
    stB);        // CONTROL-PROP
  TNoneNamed = (
    nnA,
    nnB);        // CONTROL-NONE
  { ENUMRULES (owner rule 2026-10-28): ONE dl:ok on the TYPE line reviews every
    value of the type. }
  TTypeMarked = (  // dl:ok unused-enum-value -- REVIEWED 2026-10-28 values mirror stored ordinals
    tmRead,
    tmUnusedA,   // CONTROL-TYPEMARK-A
    tmUnusedB);  // CONTROL-TYPEMARK-B
  { A FILLER value is named for its own ordinal (Dummy0 at 0) -- padding so a
    real value lands on a stored ordinal; flSpare is not, and fires. }
  TFiller = (
    flPad0,      // CONTROL-FILLER-0
    flPad1,      // CONTROL-FILLER-1
    flReal,
    flSpare);    // TRIGGER-SPARE
  { A type marker with nothing to suppress is reported unused (positive control). }
  TAllUsed = (  // dl:ok unused-enum-value -- REVIEWED 2026-10-28 nothing to suppress
    auA,
    auB);
  THolder = class
  private
    FS: TStreamed;
  published
    property S: TStreamed read FS write FS;
  end;

procedure Use(pN: Integer);

implementation

procedure Use(pN: Integer);
var
  M: TMixed;
  I: TIterated;
  C: TCastIn;
  O: TOrdOut;
  U: TSucced;
  T: TStreamed;
  K: TTypeMarked;
  L: TFiller;
  A: TAllUsed;
  N: Integer;
begin
  N:= pN;
  M:= mxRead;
  if M = mxRead then N:= N + 1;
  for I:= Low(TIterated) to High(TIterated) do N:= N + 1;
  if I = itA then N:= N + 1;
  C:= TCastIn(N);
  if C = ciA then N:= N + 1;
  O:= ooA;
  N:= N + Ord(O);
  U:= suA;
  U:= Succ(U);
  if U = suA then N:= N + 1;
  K:= tmRead;
  L:= flReal;
  A:= auA;
  if (K = tmRead) and (L = flReal) and (A <> auB) then N:= N + 1;
  T:= stA;
  if (T = stA) and (N > 0) then Exit;
end;

end.
