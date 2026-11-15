unit PUse;

// OWN: a project routine that narrow-param may narrow (positive control).

interface

uses
  LibTypes;

procedure OwnRoutine(pP: TNpLeaf);

implementation

procedure OwnRoutine(pP: TNpLeaf);
begin
  pP.Foo;
end;

end.
