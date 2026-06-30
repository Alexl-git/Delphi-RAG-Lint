unit fnp;
interface
type
  TFoo = class
  private
    Count: Integer;         // should fire: field without F prefix
    FName: string;          // clean: F + uppercase N
    FfID: Integer;          // clean: F + lowercase f (accepted by StartsWithPrefix)
  end;
implementation
end.
