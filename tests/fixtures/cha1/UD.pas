unit UD;

interface

type
  TD = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  UA;

procedure TD.Run;
begin
  TA.Create.Run;
end;

end.
