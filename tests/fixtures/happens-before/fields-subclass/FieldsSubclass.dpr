program FieldsSubclass;

{ check-init fixture fields-subclass (lane HBFIELDS): TGood.Create chains to TParent.Create (SET);
  TSkip.CreateSkip never calls an inherited constructor, so a TSkip instance never runs
  TParent2.Create (MAY, subclass-ctor-skips). }

uses
  fsTree in 'fsTree.pas';

begin
  TGood.Create.Show;
  TSkip.CreateSkip.Show;
end.