unit propself;
interface
type
  TFoo = class
  private
    FBar: Integer;
  public
    property Bar: Integer read Bar;
    property Baz: Integer read FBar write FBar;
  end;
implementation
end.
