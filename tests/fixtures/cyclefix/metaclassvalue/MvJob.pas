unit MvJob;

interface

uses
  System.Classes;

type
  /// <summary>A job the app registers.</summary>
  TMvJob = class(TPersistent)
  public
    /// <summary>Starts the app through its class.</summary>
    procedure Kick;
  end;

implementation

uses
  MvApp;

procedure TMvJob.Kick;
begin
  TMvApp.Start;
end;

end.