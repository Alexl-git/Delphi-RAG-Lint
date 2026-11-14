unit LibUse;

// A unit OUTSIDE the project folder: narrow-param must never plan an edit here.

interface

uses
  LibTypes;

procedure LibRoutine(pP: TNpLeaf);

implementation

procedure LibRoutine(pP: TNpLeaf);
begin
  pP.Foo;
end;

end.
