unit fnpvis;
interface
type
  TGroup = class
    Tag: Integer;           // implicit-first: surface, exempt
  public
    Name: string;           // public data member: exempt
    ForceClosed: Boolean;   // public data member: exempt
  protected
    Cache: Integer;         // inheritable surface: exempt
  private
    Count: Integer;         // MUST fire: private, no F
    FTotal: Integer;        // clean
  strict private
    Buffer: string;         // MUST fire: strict private is private
  end;
implementation
end.
