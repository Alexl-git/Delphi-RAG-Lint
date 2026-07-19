program MembersHarness;
{$APPTYPE CONSOLE}
uses
  System.SysUtils
  , DRagLint.Project.Members
  ;
var
  Paths  : TArray<string>;
  Members: TArray<TProjectMember>;
  I      : Integer;
begin
  // args: <path1> <path2> ... -- printed one line per member as
  // UnitPath|DfmPath|HasDfm
  SetLength(Paths, ParamCount);
  for I:= 1 to ParamCount do Paths[I - 1]:= ParamStr(I);
  Members:= PairDfmSiblings(Paths);
  for I:= 0 to High(Members) do
    Writeln(Format('%s|%s|%s', [Members[I].UnitPath, Members[I].DfmPath, BoolToStr(Members[I].HasDfm, True)]));
end.
