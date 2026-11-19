unit rtti-unavailable;

{ Fixture of rtti-unavailable sub-kind anonymous-field-type (v152 lane RTTI5, INBOX
  rtti-availability-rule sub-check 5): a published field whose type is spelled inline -- a static
  or dynamic array, a set of an anonymous enum -- has no named type, so TRttiContext sees no type
  name for it. Every line that must fire carries an EXPECT tag; every other line is a CONTROL. }

interface

uses
  System.Classes;

type
  TArr4 = array[0..3] of Integer;
  TKind = (kNone, kOne, kTwo);
  TKinds = set of TKind;

  TAnonObj = class(TPersistent)
  private
    FHidden: array[0..1] of Integer; // CONTROL private section is not judged
  public
    FOpen: array of string; // CONTROL public section is not judged
  published
    FBad: array[0..3] of Integer; // EXPECT anonymous-field-type
    FSet: set of (sA, sB); // EXPECT anonymous-field-type
    FDyn: array of string; // EXPECT anonymous-field-type
    FPairA, FPairB: array[0..1] of Byte; // EXPECT anonymous-field-type
    FSplit:
      array[0..2] of
        Integer; // EXPECT anonymous-field-type
    FNamedArr: TArr4; // CONTROL the named twin of FBad
    FNamedSet: TKinds; // CONTROL the named twin of FSet
    FText: string; // CONTROL plain type
    FLabel: string; // array[0..3] of Integer -- CONTROL text of a comment
    FMode: (mA, mB); // EXPECT anonymous-field-type
    property Items[AIndex: Integer]: Integer read GetItem; // CONTROL indexed property, not a field
  end;

  TAnonRec = record
    Data: array[0..3] of Integer; // CONTROL a record has no published section
  end;

implementation

end.