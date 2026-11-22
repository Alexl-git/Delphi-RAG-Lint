unit XuConsts2;
{ A second declaration of Twice with other bounds: the name is ambiguous, the rule must stay silent. }

interface

const
  Twice: array [1 .. 9] of Integer = (1, 2, 3, 4, 5, 6, 7, 8, 9);

implementation

end.