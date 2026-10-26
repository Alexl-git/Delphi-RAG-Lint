unit R1Form;

// CYC-B B3 fixture: the consumer of R1Title (see R1Title for the edge's shape).

interface

type
  /// <summary>Stand-in for a form that shows a title.</summary>
  TR1Form = class
  public
    /// <summary>Prints the title of one item.</summary>
    /// <param name="pId">Item whose title is shown.</param>
    class procedure Open(const pId: Integer);
  end;

implementation

uses
  System.SysUtils,
  R1Title;

class procedure TR1Form.Open(const pId: Integer);
begin
  Writeln(Format('[form] kind %d of %d', [Ord(R1TitleKind(pId)), Ord(R1TitleKind(1))]));
end;

end.