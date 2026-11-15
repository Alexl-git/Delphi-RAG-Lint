unit AppUnit;

{ Not listed in any .dpk: silent. }

interface

procedure Refresh;

implementation

uses
  System.Classes;

procedure Refresh;
begin
  TThread.Queue(nil,
    procedure
    begin
      Sleep(1);
    end);
end;

end.
