unit MvApp;

interface

type
  /// <summary>Registers the job class and names it.</summary>
  TMvApp = class
  public
    /// <summary>Registers TMvJob with the streaming system and prints its registered name.</summary>
    class procedure Start;
  end;

implementation

uses
  System.Classes, MvJob;

class procedure TMvApp.Start;
begin
  RegisterClass(TMvJob);
  Writeln('[mv] ', GetClass('TMvJob').ClassName);
end;

end.