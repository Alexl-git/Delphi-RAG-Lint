unit impl_only_routine_type_uses_unused;
{ Fixture companion: listed in impl_only_routine_type_uses' implementation
  uses clause but never referenced there -- the positive control that proves
  unused-unit-in-uses is live when the guard asserts it stays silent on
  impl_only_routine_type_uses_types. }

interface

type
  TNeverUsedType = class(TObject)
  end;

implementation

end.
