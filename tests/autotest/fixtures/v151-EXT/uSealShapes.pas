unit uSealShapes;

interface

type
  IShFace = interface
    ['{6D0C5B1E-1A2B-4C3D-8E9F-0A1B2C3D4E5F}']
  end;

  TShFwd = class;

  TShPlain = class sealed
  end;

  TShGen<T> = class sealed(TObject)
  end;

  TShOuter = class
  public type
    TShInner = class sealed
    end;
  end;

  TShFwd = class sealed
  end;

  TShAbs = class abstract
  end;

  TShRec = record
    X: Integer;
  end;

procedure Probe(F: IShFace; P: TShPlain; I: TShOuter.TShInner; W: TShFwd);
procedure Halt2; noreturn;

implementation

procedure Probe(F: IShFace; P: TShPlain; I: TShOuter.TShInner; W: TShFwd);
begin
  if P is IShFace then Exit;
  if F is TShPlain then Exit;
  if I is IShFace then Exit;
  if W is IShFace then Exit;
  if F is TShFwd then Exit;
end;

procedure Halt2;
begin
  Halt;
end;

end.
