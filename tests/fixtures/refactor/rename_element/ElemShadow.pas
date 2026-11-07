unit ElemShadow;

{ Fixture: ElemUse uses this unit AND ElemTypes, so a bare TTok there has two candidates and the index resolves it to
  nothing. The element of ElemTypes.TTokList is still ElemTypes.TTok: a type text is read in the unit that wrote it. }

interface

type
  TTok = record
    Kind: string;
    OnlyHere: Integer;
  end;

procedure RunShadow;

implementation

procedure RunShadow;
var
  Shadow: TTok;
begin
  Shadow.OnlyHere:= 7;
  Shadow.Kind:= 'shadow';
  WriteLn(Shadow.Kind, ' ', Shadow.OnlyHere);
end;

end.