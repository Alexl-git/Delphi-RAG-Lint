unit W4.Sink;

interface

type
  /// <summary>A constructor parameter type outside the cycle.</summary>
  TW4Sink = class
  public
    /// <summary>Prints one line.</summary>
    /// <param name="pText">The line.</param>
    procedure Say(const pText: string);
  end;

implementation

procedure TW4Sink.Say(const pText: string);
begin
  Writeln(pText);
end;

end.