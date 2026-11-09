unit W4Hub;

interface

uses
  System.Classes,
  System.Generics.Collections,
  W4.Sink,
  W4.Worker;

type
  /// <summary>The Loader main-form shape: a list of workers (150-CY-10b: the w4 list shapes on the default path).</summary>
  TW4Hub = class
  private
    FWorkers: TObjectList<TW4Worker>;
    FSink   : TW4Sink;
    FAction : TBasicAction;
  public
    /// <summary>Runs two workers, one after the other.</summary>
    procedure Run;
  end;

var
  GHubTitle: string = 'hub';

implementation

uses
  System.SysUtils;

procedure TW4Hub.Run;
var
  I: Integer;
  W: TW4Worker;
begin
  FSink := TW4Sink.Create;
  FWorkers := TObjectList<TW4Worker>.Create(True);
  try
    for I := 1 to 2 do FWorkers.Add(TW4Worker.Create(I, FSink));
    for I := 0 to FWorkers.Count - 1 do
    begin
      W := FWorkers[I];
      W.RunToEnd;
      if W.Finished then Writeln('[hub] finished');
      Writeln('[hub] ', W.ID, ' done ', W.Done, ' finished ', FWorkers[I].Finished);
    end;
    var FW: TW4Worker := FWorkers[0];
    Writeln('[hub] first ', FW.ID);
    { an unresolved `.Execute` of another class: the name alone used to drag the override into the base class }
    if Assigned(FAction) then FAction.Execute;
    FWorkers.OwnsObjects := True;
  finally
    FreeAndNil(FWorkers);
    FSink.Free;
  end;
end;

end.