unit impl_only_routine_type_uses_types;
{ Companion unit: defines the imported type used only in implementation-only
  routine signatures. }

interface

type
  TImportedType = class(TObject)
  private
    FValue: string;
  public
    property Value: string read FValue write FValue;
  end;

implementation

end.
