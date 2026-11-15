unit queue_nil_in_package_plain;

{ Not a package unit: no design-time uses, no .dpk lists it. TThread.Queue(nil, ...) is fine here. }

interface

uses
  System.Classes;

procedure Refresh;

implementation

procedure Refresh;
begin
  TThread.Queue(nil, {OK}
    procedure
    begin
      Sleep(1);
    end);
end;

end.
