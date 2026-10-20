unit R1Nav;

// E18 T5 fixture: closes the cycle R1Form -> R1Title -> R1Nav -> R1Form with
// class-method calls, which no recipe of the plan cuts.

interface

type
  /// <summary>Navigation stand-in.</summary>
  TR1Nav = class
  public
    /// <summary>Name of the navigation target.</summary>
    /// <returns>A fixed caption.</returns>
    class function Caption: string;
    /// <summary>Navigates back to the form (never called by the program).</summary>
    class procedure Back;
  end;

implementation

uses
  R1Form;

class function TR1Nav.Caption: string;
begin
  Result := 'nav';
end;

class procedure TR1Nav.Back;
begin
  TR1Form.Open(0);
end;

end.