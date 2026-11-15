unit RcUse;

// Fixture of extract-interface --retype-consumer (lane v151 REPARENT). A consumer's declaration line ends with
// `// RETYPE <routine>.<param> <class>` (the retype must apply) or `// REFUSE <kind> <routine>.<param> <class>`.

interface

uses
  RcWidget;

type
  TRcHost = class
  public
    procedure Visit(pC: TRcCounter); virtual; // REFUSE virtual-method TRcHost.Visit.pC TRcCounter
    procedure Look(pC: TRcCounter); // RETYPE TRcHost.Look.pC TRcCounter
  end;

procedure ShowCount(const pC: TRcCounter); // RETYPE ShowCount.pC TRcCounter
procedure BumpTwice(pC: TRcCounter); // RETYPE BumpTwice.pC TRcCounter
procedure Leak(pC: TRcCounter); // REFUSE use-not-interface Leak.pC TRcCounter
procedure Peek(pC: TRcCounter); // REFUSE use-not-interface Peek.pC TRcCounter
procedure Swap(var pC: TRcCounter); // REFUSE var-param Swap.pC TRcCounter
procedure Pair(pA, pB: TRcCounter); // REFUSE param-group Pair.pA TRcCounter
procedure Over(pC: TRcCounter); overload; // REFUSE overloaded Over.pC TRcCounter
procedure Over(const pS: string); overload;
procedure KidUse(pK: TRcCounterKid); // RETYPE KidUse.pK TRcCounterKid
procedure CountedUse(pC: TRcCounted); // REFUSE lifetime-refcounted CountedUse.pC TRcCounted
procedure PartUse(pP: TRcPart); // RETYPE PartUse.pP TRcPart
procedure QuietUse(pQ: TRcQuiet); // RETYPE QuietUse.pQ TRcQuiet
procedure LoudUse(pL: TRcLoud); // REFUSE lifetime-unknown LoudUse.pL TRcLoud
procedure PlainUse(pP: TRcPlain); // REFUSE no-iinterface PlainUse.pP TRcPlain
procedure BareUse(pB: TRcBare); // REFUSE not-implemented BareUse.pB TRcBare
procedure MappedUse(pM: TRcMapped); // REFUSE method-resolution MappedUse.pM TRcMapped
procedure AgainUse(pA: TRcAgain); // REFUSE reimplemented AgainUse.pA TRcAgain
procedure WrongType(pN: Integer); // REFUSE param-not-class WrongType.pN TRcCounter
procedure Hooked(pC: TRcCounter); // GATE Hooked.pC TRcCounter
procedure RunAll;

implementation

uses
  System.Classes;

var
  GKeep: TRcCounter;
  { Hooked's address is taken with its signature: a retype the plan proves and only the build rejects }
  GHook: procedure(pC: TRcCounter);

procedure TRcHost.Visit(pC: TRcCounter);
begin
  pC.Bump;
end;

procedure TRcHost.Look(pC: TRcCounter);
begin
  if pC <> nil then
    Write('look ', pC.Count, ' ');
end;

procedure ShowCount(const pC: TRcCounter);
begin
  if not Assigned(pC) then Exit;
  pC.Bump;
  Write('count ', pC.Count, ' ');
end;

procedure BumpTwice(pC: TRcCounter);
begin
  if nil = pC then Exit;
  pC.Bump;
  pC . Bump; { pC.Secret in a comment is not a use }
end;

procedure Leak(pC: TRcCounter);
begin
  GKeep:= pC;
end;

procedure Peek(pC: TRcCounter);
begin
  Write(pC.Secret);
end;

procedure Swap(var pC: TRcCounter);
begin
  pC:= nil;
end;

procedure Pair(pA, pB: TRcCounter);
begin
  pA.Bump;
  pB.Bump;
end;

procedure Over(pC: TRcCounter);
begin
  pC.Bump;
end;

procedure Over(const pS: string);
begin
  Write(pS);
end;

procedure KidUse(pK: TRcCounterKid);
begin
  pK.Bump;
end;

procedure CountedUse(pC: TRcCounted);
begin
  pC.Bump;
end;

procedure PartUse(pP: TRcPart);
begin
  Write(pP.PartName, ' ');
end;

procedure QuietUse(pQ: TRcQuiet);
begin
  pQ.Ping;
end;

procedure LoudUse(pL: TRcLoud);
begin
  pL.Shout;
end;

procedure PlainUse(pP: TRcPlain);
begin
  pP.Bump;
end;

procedure BareUse(pB: TRcBare);
begin
  pB.Bump;
end;

procedure MappedUse(pM: TRcMapped);
begin
  pM.Bump;
end;

procedure AgainUse(pA: TRcAgain);
begin
  pA.Bump;
end;

procedure WrongType(pN: Integer);
begin
  Write(pN);
end;

procedure Hooked(pC: TRcCounter);
begin
  pC.Bump;
end;

procedure RunAll;
begin
  GHook:= Hooked;
  var C:= TRcCounter.Create;
  var Host:= TRcHost.Create;
  var Part:= TRcPart.Create(nil);
  var Quiet:= TRcQuiet.Create;
  try
    ShowCount(C);
    BumpTwice(C);
    BumpTwice(nil);
    Host.Look(C);
    PartUse(Part);
    QuietUse(Quiet);
    { the caller's instance outlives every call: a counting base would have freed it here }
    Writeln('final ', C.Count, ' ', C.Secret);
  finally
    Quiet.Free;
    Part.Free;
    Host.Free;
    C.Free;
  end;
end;

end.
