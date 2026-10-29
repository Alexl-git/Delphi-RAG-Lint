unit uEnumDecl;

{ enum-type-marker fixture (ENUMRULES 2026-10-28): the TYPE declarations. One
  dl:ok on a type line reviews every enum-ordinal-cast finding OF that type, in
  any unit; the casts live in uEnumUse. }

interface

type
  TMarkedCmd = (  // dl:ok enum-ordinal-cast -- REVIEWED 2026-10-28 ordinals mirror the wire protocol
    mcA,
    mcB,
    mcC);
  TFreeCmd = (
    fcA,
    fcB,
    fcC);

implementation

end.