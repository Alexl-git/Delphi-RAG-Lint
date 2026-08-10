unit xdb_lib;

{ Stands in for a LIBRARY unit (RTL / VCL / DevExpress / Spring): indexed into a
  SEPARATE database that the consumer's index knows nothing about. }

interface

type
  TJsonThing = class
  public
    constructor Create(AValue: Integer);
    function Encode: string;
  end;

implementation

constructor TJsonThing.Create(AValue: Integer);
begin
end;

function TJsonThing.Encode: string;
begin
  Result := '';
end;

end.
