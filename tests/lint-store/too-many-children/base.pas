unit base;

interface

type
  TAnimal = class
  public
    procedure Speak; virtual;
  end;

  TDog = class(TAnimal)
  end;

  TCat = class(TAnimal)
  end;

  TCow = class(TAnimal)
  end;

implementation

procedure TAnimal.Speak;
begin
end;

end.
