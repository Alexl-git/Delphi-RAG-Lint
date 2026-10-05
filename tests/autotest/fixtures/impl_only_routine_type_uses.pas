unit impl_only_routine_type_uses;
{ Fixture: a routine declared ONLY in implementation section, where the
  only use of an imported type is in the routine's signature (parameter or
  return type). The extractor should emit type_use refs for these, but
  currently does not, causing unused-unit-in-uses false positives. }

interface

uses
  SysUtils;

procedure DoSomething;

implementation

uses
  Classes,
  impl_only_routine_type_uses_types;  // declares TImportedType

type
  TLocalType = class(TObject)
  end;

{ Implementation-only routine: TImportedType appears ONLY in the signature,
  not in the body, and not in the interface. This should emit type_use refs
  for TImportedType. }
function GetImportedInstance: TImportedType;
begin
  { Empty body; the fixture's point is the signature, not the body. }
  Result := nil;
end;

{ Variant with multiple parameters and out/var modifiers. }
procedure ProcessWithImported(var Param1: TImportedType; const Param2: TImportedType; out Param3: TImportedType);
begin
  { Empty. }
end;

{ Variant with a function-type parameter. }
procedure CallWithFunctionType(Callback: function(X: TImportedType): TImportedType);
begin
  { Empty. }
end;

{ Variant with a nested routine that uses the imported type. }
procedure NestedRoutineVariant;
  procedure NestedWithImported(P: TImportedType);
  begin
    { Empty. }
  end;
begin
  { Empty. }
end;

procedure DoSomething;
begin
  { Implementation of interface routine; this one can use local types. }
end;

end.
