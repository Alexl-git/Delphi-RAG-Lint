unit ota_notifier_not_removed_plain;

{ Fixture for ota-notifier-not-removed: a unit that does not use ToolsAPI has
  its own AddNotifier, and the rule stays silent. (-) must not fire. }

interface

type
  TBus = class
  public
    function AddNotifier(AListener: TObject): Integer;
  end;

procedure Wire(ABus: TBus);

implementation

function TBus.AddNotifier(AListener: TObject): Integer;
begin
  Result := 0;
end;

procedure Wire(ABus: TBus);
begin
  ABus.AddNotifier(nil); { (-) }
end;

end.
