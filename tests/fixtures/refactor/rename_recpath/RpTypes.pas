unit RpTypes;

// Plan-only fixture: never compiled (its library records live in the stub library only).

interface

uses
  LibRecs;

type
  TMine = record
    X: Integer;
  end;

  TWrap = record
    Sh: TLibShape;
  end;

  TGhostWrap = record
    Gh: TNoSuchLib;
  end;

const
  CMine: TMine = (X: 1);
  { A record constant whose field path walks off the project into the library AND through an array level. }
  CWrap: TWrap = (Sh: (Pts: ((X: 1; Y: 2), (X: 3; Y: 4))));
  { The same shape off a type no index holds: must stay refused. }
  CGhost: TGhostWrap = (Gh: (Pts: ((X: 5))));

implementation

end.