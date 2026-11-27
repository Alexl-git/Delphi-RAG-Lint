unit uExtsA;

interface

type
  /// <summary>Fixture class of run_v156_EXTS_schema.ps1: two method bodies.</summary>
  TExtsA = class
  private
    FTotal: Integer;
  public
    /// <summary>Adds pValue to the total.</summary>
    /// <param name="pValue">The amount.</param>
    procedure Fill(pValue: Integer);
    /// <summary>The running total.</summary>
    /// <returns>FTotal.</returns>
    function Total: Integer;
  end;

/// <summary>Doubles a value.</summary>
/// <param name="pValue">The value.</param>
/// <returns>pValue * 2.</returns>
function Twice(pValue: Integer): Integer;

implementation

procedure TExtsA.Fill(pValue: Integer);
begin
  FTotal := FTotal + pValue;
end;

function TExtsA.Total: Integer;
begin
  Result := FTotal;
end;

function Twice(pValue: Integer): Integer;
begin
  Result := pValue + pValue;
end;

end.
