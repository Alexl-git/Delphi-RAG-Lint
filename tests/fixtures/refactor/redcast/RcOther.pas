unit RcOther;

// Same names as RcTypes: the callee of a "cast" cannot be proved a type by name alone.

interface

uses
  RcTypes;

type
  TDup = class(TBase)
  end;

function TNamed(pValue: TBase): TBase;

implementation

function TNamed(pValue: TBase): TBase;
begin
  Result:= pValue;
end;

end.