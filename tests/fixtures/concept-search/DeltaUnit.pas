unit DeltaUnit;

{ Fixture for tests\autotest\run_concept_search.ps1 (concept search).
  TDeltaPipe.ApplyRowDelta is the target; the other classes share some of its
  words on purpose so ranking has to discriminate. }

interface

type
  /// <summary>Pipe that carries delta packets between the client and the server.</summary>
  TDeltaPipe = class
  public
    /// <summary>Streams pending row changes into the target table.</summary>
    /// <remarks>Uses a lantern buffer for backpressure.</remarks>
    procedure ApplyRowDelta;
  end;

  /// <summary>Counts things for the status bar.</summary>
  TRowCounter = class
  public
    /// <summary>Counts the rows of a table.</summary>
    function CountRows: Integer;
  end;

  /// <summary>Writes diagnostics to a log file.</summary>
  TPipeLogger = class
  public
    /// <summary>Logs a delta packet to the diagnostics file.</summary>
    procedure LogDelta;
  end;

implementation

procedure TDeltaPipe.ApplyRowDelta;
begin
end;

function TRowCounter.CountRows: Integer;
begin
  Result:= 0;
end;

procedure TPipeLogger.LogDelta;
begin
end;

end.
