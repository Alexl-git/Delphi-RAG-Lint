program FieldsVirtual;

{ check-init fixture fields-virtual-in-ctor (lane HBFIELDS): TBase.Create calls the virtual Setup, which
  TDerived overrides and which reads FItems before TDerived.Create has set it (MAY,
  virtual-call-in-ancestor-ctor). TBase2.Create does not call Setup: the SET twin. }

uses
  fvShapes in 'fvShapes.pas';

begin
  TDerived.Create.Use;
  TDerived2.Create.Setup;
end.