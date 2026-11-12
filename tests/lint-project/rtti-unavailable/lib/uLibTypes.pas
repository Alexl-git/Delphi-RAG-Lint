unit uLibTypes;

{ Stand-in library unit of the rtti-unavailable fixture: a record and a component base class that
  only the library index knows. }

interface

uses
  System.Classes;

type
  TLibStamp = packed record
    Year: Word;
    Month: Word;
  end;

  TLibComponent = class(TComponent)
  end;

implementation

end.
