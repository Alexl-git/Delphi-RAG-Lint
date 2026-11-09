unit WideHub;

interface

uses
  System.Classes,
  System.Generics.Collections,
  Wide.Sink
  , Wide.Proc
  , Wide.Worker;

type
  /// <summary>The Loader main-form shape: a dead field named like the segment of a dotted unit, a list of workers.</summary>
  TWideHub = class
  private
    Proc    : TWideProc;
    FWorkers: TObjectList<TWideWorker>;
    FSink   : TWideSink;
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

procedure TWideHub.Run;
var
  I: Integer;
  W: TWideWorker;
begin
  FSink := TWideSink.Create;
  FWorkers := TObjectList<TWideWorker>.Create(True);
  try
    for I := 1 to 2 do FWorkers.Add(TWideWorker.Create(I, FSink));
    for I := 0 to FWorkers.Count - 1 do
    begin
      W := FWorkers[I];
      W.RunToEnd;
      if W.Finished then Writeln('[hub] finished');
      Writeln('[hub] ', W.ID, ' done ', W.Done, ' finished ', FWorkers[I].Finished);
    end;
    var FW: TWideWorker := FWorkers[0];
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