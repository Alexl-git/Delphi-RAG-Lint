unit fnp;
interface
type
  TFoo = class
  private
    Count: Integer;         // should fire: field without F prefix
    FName: string;          // clean
  end;
implementation
end.
