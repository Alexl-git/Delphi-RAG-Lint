unit NoCutB;

// E18 T13 fixture nocut: the positive control of the Fix-it block. Two plain classes
// that test and read each other (`is` / `as` plus a member read, the shape recipe R2
// carries) AND construct each other, so neither edge of the implementation-only cycle
// can be cut mechanically: a class whose method bodies use the other unit cannot move,
// recipe R1 needs a single routine, and recipe R2 refuses a construction. `cycles --plan`
// must say `Fix it: not available -- construction` and the JSON `fix.available` must be false.

interface

type
  /// <summary>A class that inspects a TNoCutA and constructs one.</summary>
  TNoCutB = class
  private
    FCount: Integer;
  public
    /// <summary>Reads the count of a TNoCutA sender and constructs a TNoCutA.</summary>
    /// <param name="pSender">The object to inspect; ignored unless it is a TNoCutA.</param>
    procedure Run(pSender: TObject);
    /// <summary>What the other unit reads.</summary>
    property Count: Integer read FCount;
  end;

implementation

uses
  NoCutA;

procedure TNoCutB.Run(pSender: TObject);
begin
  if pSender is TNoCutA then
    FCount := (pSender as TNoCutA).Count;
  TNoCutA.Create.Free;
end;

end.