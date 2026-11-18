program FieldsProperty;

{ check-init fixture fields-property (lane HBFIX, 1.52): a field written only through its property
  (`property P read F write F` or a setter that assigns F) is never NEVER-SET (HBMEASURE F1).
    TItem       written only by `Item.Number:= ..` from outside (direct write-field property), read
                there through the property too (a use, through another object; as an argument of an
                unresolved callee it is no by-reference argument, so no UNKNOWN-CALLEE): MAY
    TNamed      written only by `Obj.Name:= ..` through the setter SetName: MAY
    TSelfProp   the constructor writes `Number:= 1` (Self, direct): SET
    TSelfSet    the constructor writes `Name:= 'x'` (Self, setter that always assigns): SET
    TCondSet    the constructor writes `Name:= 'x'` but the setter assigns only sometimes: MAY (twin)
    TUnwritten  the property is declared with `write FNever` but nobody writes it: NEVER-SET (twin)
    TReadOnly   a read-only property over the field, only read: NEVER-SET (twin)
    TSideHolder written only by `B.Side:= ..` where B's type is not resolved (`var B:= Map['a']`):
                a soft writer, MAY (never NEVER-SET) }

uses
  System.SysUtils,
  System.Generics.Collections,
  fpProps in 'fpProps.pas';

var
  Map: TDictionary<string, TSideHolder>;
  Item: TItem;
  Named: TNamed;

begin
  Item:= TItem.Create;
  Item.Number:= 5;
  Writeln(Item.Number);    // USE-ITEM-PROP
  Writeln(Format('%d', [Item.Number]));    // USE-ITEM-FMT
  Item.Show;
  Named:= TNamed.Create;
  Named.Name:= 'n';
  Named.Show;
  TSelfProp.Create.Show;
  TSelfSet.Create.Show;
  TCondSet.Create.Show;
  TUnwritten.Create.Show;
  TReadOnly.Create.Show;
  Map:= TDictionary<string, TSideHolder>.Create;
  Map.Add('a', TSideHolder.Create);
  var B:= Map['a'];
  B.Side:= 'x';
  B.Show;
end.