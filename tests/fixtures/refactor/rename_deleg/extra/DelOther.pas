unit DelOther;

interface

uses
  DelTypes;

type
  { Same method name, no relation to IFoo: must stay. }
  TOther = class
  public
    procedure Bar;
  end;

implementation

procedure TOther.Bar;
begin
end;

end.