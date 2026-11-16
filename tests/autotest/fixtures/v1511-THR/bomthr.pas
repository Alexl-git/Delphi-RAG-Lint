unit bomthr;

interface

implementation

uses
  System.Classes;

// copyright ой
procedure NotStarted;
var
  T: TThread;
begin
  T:= TThread.CreateAnonymousThread(
    procedure
    begin
    end);
end;

end.
