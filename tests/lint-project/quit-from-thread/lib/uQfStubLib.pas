unit uQfStubLib;

{ The fixture's "platform library": indexed into its OWN DB and passed as the second --db, so the
  fixture units reach TThread the way a real project reaches the RTL. Hermetic. }

interface

type
  TThread = class(TObject)
  public
    procedure Terminate;
  end;

implementation

procedure TThread.Terminate;
begin
end;

end.