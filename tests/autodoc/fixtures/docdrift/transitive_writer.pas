unit transitive_writer;

{ Fixture for run_doc_exception_transitive_writer.ps1 -- the WRITER half of the
  transitive <exception cref> story (INBOX-exception-cref-transitive-raise,
  gap 2).

  WHY A SECOND FIXTURE, AND NOT MORE DECLS IN transitive.pas
  ----------------------------------------------------------
  transitive.pas pins the CHECKER: every declaration there already carries a
  hand-written doc comment, because the question it asks is "does doc-drift
  accept a cref the callee justifies". That makes it useless for the WRITER,
  whose contract is that a hand-written cref is PRESERVED VERBATIM. Session 75
  proposed ViaHelper there as the writer's RED case; measured, it can never go
  red, because the writer copies the human's text through untouched.

  So the writer needs declarations with NO doc comment at all. Adding those to
  transitive.pas would change what its six assertions mean, so they live here
  and that fixture stays byte-identical.

  WHAT THIS FIXTURE IS SHAPED TO PROVE
  ------------------------------------
  Every declaration below is UNDOCUMENTED on purpose. `document --apply` must
  write an <exception cref> for a class the routine does not raise itself but
  a ONE-HOP callee does, attributed as `via <callee qname>: <message>` -- and
  must NOT write one when the evidence is absent (unresolved callee), too far
  away (two hops), or itself (recursion).

  DO NOT add doc comments here, and do not "tidy" the odd names: NoDocTwoVia's
  callees are named so that FILE order and ALPHABETICAL order disagree, which
  is the only way an ordering assertion can fail. }

interface

uses
  System.SysUtils;

type
  EBoom  = class(Exception);
  EOther = class(Exception);

{ The two raisers the via-tags point at. Declared in the interface so the
  writer documents them here, which is what assertion 2 reads. }
procedure HelperRaise;
procedure OtherRaise;

{ THE FIX: a one-line delegator. Raises nothing itself; HelperRaise does. }
procedure NoDocDelegates;

{ DEPTH PIN: the raise is two hops away, past the deliberate bound. }
procedure NoDocTwoHops;

{ POSITIVE CONTROL: raises EBoom itself AND delegates. The own message must
  come first, so a passing assertion 1 cannot be the writer tagging blindly. }
procedure NoDocOwnAndVia;

{ RECURSION: raises EBoom itself and calls itself. The self-edge must not be
  attributed -- no `via transitive_writer.NoDocRecursive`. }
procedure NoDocRecursive;

{ TWO CLASSES: one callee raises EBoom, the other EOther. Two tags. }
procedure NoDocMulti;

{ FAIL-SAFE: the only callee is RTL and unresolved here. Absence of
  information is not evidence of a raise. }
function NoDocRtlOnly(AValue: Integer): string;

{ CAP: four callees all raising EBoom -- three named, then `(+1 more)`. }
procedure NoDocFanOut;

{ ORDER: two callees raising EBoom, called Zz-first so that file order and
  alphabetical order disagree. }
procedure NoDocTwoVia;

implementation

procedure HelperRaise;
begin
  raise EBoom.Create('boom');
end;

procedure OtherRaise;
begin
  raise EOther.Create('other');
end;

procedure MidHop;
begin
  HelperRaise;
end;

procedure FanA;
begin
  raise EBoom.Create('a');
end;

procedure FanB;
begin
  raise EBoom.Create('b');
end;

procedure FanC;
begin
  raise EBoom.Create('c');
end;

procedure FanD;
begin
  raise EBoom.Create('d');
end;

procedure AaRaise;
begin
  raise EBoom.Create('aa');
end;

procedure ZzRaise;
begin
  raise EBoom.Create('zz');
end;

procedure NoDocDelegates;
begin
  HelperRaise;
end;

procedure NoDocTwoHops;
begin
  MidHop;
end;

procedure NoDocOwnAndVia;
begin
  if Random(2) = 0 then
    raise EBoom.Create('mine');
  HelperRaise;
end;

procedure NoDocRecursive;
begin
  if Random(2) = 0 then
    raise EBoom.Create('rec');
  NoDocRecursive;
end;

procedure NoDocMulti;
begin
  if Random(2) = 0 then
    HelperRaise;
  OtherRaise;
end;

function NoDocRtlOnly(AValue: Integer): string;
begin
  Result:= IntToStr(AValue);
end;

procedure NoDocFanOut;
begin
  FanA;
  FanB;
  FanC;
  FanD;
end;

procedure NoDocTwoVia;
begin
  ZzRaise;
  AaRaise;
end;

end.
