unit R1Form;

// E18 T5 fix round 2 fixture (edge-still-used): the consumer calls the INHERITED
// class method R1Note with no receiver. Delphi binds it to TR1Base.R1Note; the
// planner's name lookup (last visible uses wins) binds it to R1Title.R1Note, so
// R1Title still looks used here and the routine-call inversion must not claim
// the cut.

interface

uses
  R1Base;

type
  /// <summary>Stand-in for a form that shows a title.</summary>
  TR1Form = class(TR1Base)
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
  R1Note('open');
  Writeln(Format('[form] %s', [R1TitleOf(pId)]));
end;

end.