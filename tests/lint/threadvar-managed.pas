unit threadvar_managed;

{ threadvar-managed fixture.  HIT marker = rule fires on that line, OK marker = silent. }

interface

type
  TManagedRec = record
    Count: Integer;
    Name : string;
  end;

  TPlainRec = record
    Count: Integer;
    Size : Double;
  end;

  IThing = interface
  end;

  TIntArr = array of Integer;

threadvar
  GMessage : string; {HIT}
  GThing   : IThing; {HIT}
  GItems   : TArray<Integer>; {HIT}
  GRec     : TManagedRec; {HIT}
  GVar     : Variant; {HIT}
  GDyn     : array of Integer; {HIT}
  GAlias   : TIntArr; {HIT}
  GCount   : Integer; {OK}
  GShort   : string[20]; {OK}
  GObj     : TObject; {OK}
  GPlain   : TPlainRec; {OK}
  GBig     : Int64; {OK}
  GText    : PChar; {OK}
  GStatic  : array[0..3] of Integer; {OK}

implementation

end.
