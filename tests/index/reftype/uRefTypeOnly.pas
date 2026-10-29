unit uRefTypeOnly;

{ Lane REFTYPE fixture: uRefTypeOnlyDefs is used in the interface ONLY by a
  procedural type signature, so uses-audit must not call it movable. }

interface

uses
  uRefTypeOnlyDefs;

type
  TOnlyOpener = reference to function(const pPath: string): TRtOnly;

implementation

end.
