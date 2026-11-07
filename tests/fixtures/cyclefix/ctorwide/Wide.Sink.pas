unit Wide.Sink;

interface

type
  /// <summary>A constructor parameter type outside the cycle.</summary>
  TWideSink = class
  public
    /// <summary>Prints one line.</summary>
    /// <param name="pText">The line.</param>
    procedure Say(const pText: string);
  end;

implementation

procedure TWideSink.Say(const pText: string);
begin
  Writeln(pText);
end;

end.