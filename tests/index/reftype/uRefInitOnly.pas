unit uRefInitOnly;

{ Lane REFTYPE fixture: uRefInitOnlyDefs is used in the interface ONLY by a
  const initializer, so uses-audit must not call it movable. }

interface

uses
  uRefInitOnlyDefs;

const
  CInitOnly = RiOnly;

implementation

end.
