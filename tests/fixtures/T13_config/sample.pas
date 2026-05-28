unit sample;
interface
type
  TX = class
    // loose preceding doc
    procedure A;

    // loose doc with gap

    procedure B;
  end;
implementation
procedure TX.A; begin end;
procedure TX.B; begin end;
end.
