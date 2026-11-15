unit PkgUnit;

{ Listed in Pkg.dpk: TThread.Queue(nil, ...) is a hit here. }

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
