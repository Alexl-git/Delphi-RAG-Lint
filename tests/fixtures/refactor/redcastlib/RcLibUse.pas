unit RcLibUse;

// FIX = removed; REFUSE <kind> = named refusal. Needs the library index lib.sqlite (the guard builds it).
// TLibCls and TLibTwin come from the library, never from this project.

interface

uses
  LibTypes, LibOther;

procedure RunLib;

implementation

function OwnArg(pValue: Integer): string;
begin
  Result:= '';
end;

function Own: string;
begin
  Result:= '';
end;

procedure RunLib;
var
  LC: TLibCls;
  LT: TLibTwin;
  S: string;
  N: Integer;
begin
  LC:= TLibCls(LC); // FIX
  LT:= TLibTwin(LT); // REFUSE type-not-indexed
  S:= string(Own); // FIX
  S:= string(OwnArg(N)); // FIX
  S:= string(N); // NONE
  N:= Integer(N); // REFUSE type-not-indexed
end;

end.
