unit R1Form;

// E18 T5 fixture: the consumer. Its only use of R1Title is ONE call of the
// routine R1TitleOf, whose signature names System types only -- so no
// existing unit is a better home for the pointer than R1Title.Untangle.

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
  Writeln(Format('[form] %s', [R1TitleOf(pId)]));
end;

end.