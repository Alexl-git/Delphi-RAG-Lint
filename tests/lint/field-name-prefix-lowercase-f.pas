unit fnl;
interface
type
  TFoo = class
  private
    fFLDRID: Integer;   // lowercase f prefix: clean
    FOk: Integer;       // clean
    Bad: Integer;       // must fire
    filter: Integer;    // plain word starting with f: must fire
  end;
implementation
end.
