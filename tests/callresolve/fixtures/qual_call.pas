unit qual_call;

{ Calling half. MakePlain and MakeQualified must BOTH resolve to
  qual_decl.TOnlyOnce.Create as [certain].

  NoiseUnknown is the NEGATIVE control: a dotted receiver naming a type this DB
  does not declare must NOT resolve. Without it, "the qualified call resolves"
  would also be satisfied by a resolver that simply matched every leaf name it
  saw -- which is the 107-caller bug this whole area exists to prevent. }

interface

uses
  qual_decl;

function MakePlain: TOnlyOnce;
function MakeQualified: TOnlyOnce;
procedure NoiseUnknown;

implementation

function MakePlain: TOnlyOnce;
begin
  Result := TOnlyOnce.Create(1);
end;

function MakeQualified: TOnlyOnce;
begin
  Result := qual_decl.TOnlyOnce.Create(2);
end;

procedure NoiseUnknown;
begin
  uNotIndexed.TStranger.Create(3);
end;

end.
