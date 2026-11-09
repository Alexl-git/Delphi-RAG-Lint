unit FixLibB;

{ uses-recover fixture: reached through FixLibA's INTERFACE uses only. }

interface

uses
  FixRtl;

type
  TLibB = class
  public
    function Value: Integer;
  end;

implementation

function TLibB.Value: Integer;
begin
  Result:= RtlAnswer;
end;

end.
