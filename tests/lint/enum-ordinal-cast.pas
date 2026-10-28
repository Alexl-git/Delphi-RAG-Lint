unit EnumOrdinalCastFixture;

{ enum-ordinal-cast: a hard-coded ORDINAL of an enum -- TEnum(5), Ord(X) = 3,
  case Ord(X) of 2: -- breaks silently when a value is inserted or reordered.
  Known FP shapes kept silent below: Ord() against another Ord() (arithmetic /
  serialisation), Ord() of a Char or Integer, a cast to a non-enum type,
  a cast whose argument is not a literal, a negative sentinel TEnum(-1),
  an enum whose values are all pinned (= N), and an enum whose TYPE line carries
  a dl:ok enum-ordinal-cast review (type-level suppression, ENUMRULES). }

interface

type
  TCmd = (cmdLoad, cmdDelta, cmdSave, cmdQuit);
  TPinned = (pnA = 0, pnB = 1, pnC = 2);
  TMarkedCmd = (mcA, mcB, mcC);  // dl:ok enum-ordinal-cast -- REVIEWED 2026-10-28 ordinals mirror the wire protocol
  TCmdHolder = class
    FCmd: TCmd;
  end;

procedure Run(pCmd: TCmd; pCh: Char; pN: Integer; pH: TCmdHolder);

implementation

procedure Run(pCmd: TCmd; pCh: Char; pN: Integer; pH: TCmdHolder);
var
  C: TCmd;
  B: Byte;
  D: Integer;
  P: TPinned;
  M: TMarkedCmd;
begin
  C:= TCmd(2);                          { hit: cast-in of a literal }
  if Ord(pCmd) = 3 then Exit;           { hit: Ord of a param compared to a literal }
  if 1 <> Ord(C) then Exit;             { hit: literal on the left }
  if Ord(pH.FCmd) >= 2 then Exit;       { hit: Ord of a field }
  case Ord(pCmd) of                     { hit: case on Ord with literal labels }
    0: Exit;
    2: Exit;
  end;
  D:= Ord(pCmd) - Ord(cmdLoad);         { silent: Ord against Ord }
  if Ord(pCmd) = Ord(C) then Exit;      { silent: Ord against Ord }
  if Ord(pCh) = 13 then Exit;           { silent: Ord of a Char }
  if Ord(pN) = 3 then Exit;             { silent: Ord of an Integer }
  B:= Byte(5);                          { silent: cast to a non-enum type }
  C:= TCmd(pN);                         { silent: cast of a non-literal }
  case pCmd of                          { silent: case on the enum itself }
    cmdLoad: Exit;
  end;
  C:= TCmd(-1);                         { silent: negative sentinel, no value's position }
  P:= TPinned(1);                       { silent: every value pinned (= N) }
  if Ord(P) = 2 then Exit;              { silent: every value pinned (= N) }
  M:= TMarkedCmd(1);                    { silent: one dl:ok on the TYPE reviews its casts }
  if Ord(M) = 2 then Exit;              { silent: one dl:ok on the TYPE reviews its casts }
  if (D > 0) and (B > 0) then Exit;
end;

end.
