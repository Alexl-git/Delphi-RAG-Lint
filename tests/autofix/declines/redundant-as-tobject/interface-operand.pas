unit ifaceasobj;

{ `IFoo as TObject` is NOT redundant: an interface reference is not a TObject, the cast is the
  only way to the implementing instance. Stripping it is E2010 (TObject vs interface). The fixer
  must decline an interface-typed (or unknown-typed) operand; the rule still fires. Found by the
  ORM3 --fix --apply build proof (uPipeSessionBuilder.OpenConnectionForUser). }

interface

type
  IFoo = interface
    procedure Go;
  end;

implementation

procedure P(const TS: IFoo; var Obj: TObject);
begin
  Obj:= TS as TObject;
end;

end.
