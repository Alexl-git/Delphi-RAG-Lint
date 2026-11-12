unit uRttiObjects;

{ Fixture of the rtti-unavailable rule (wave 152b lane RTTI, INBOX rtti-availability-rule).
  Every line that must fire carries an EXPECT tag naming its sub-kind and severity; every other line
  must stay silent. Lines tagged CONTROL are the negative controls named in the plan row. }

{$WEAKLINKRTTI ON} // EXPECT rtti-narrowing-directive warning
{$RTTI EXPLICIT METHODS([vcPrivate]) PROPERTIES([vcPublic, vcPublished]) FIELDS([])} // EXPECT rtti-narrowing-directive warning
{$RTTI EXPLICIT METHODS(DefaultMethodRttiVisibility)} // CONTROL default visibility keeps public + published

interface

uses
  System.Classes, Data.SqlTimSt, uLibTypes;

type
  TGap = (gA = 1, gB = 3); // EXPECT enum-no-typeinfo warning
  TFromOne = (foA = 1, foB, foC); // EXPECT enum-no-typeinfo warning
  TPinned = (pA = 0, pB = 1, pC = 2); // CONTROL contiguous from 0
  TPlain = (plA, plB); // CONTROL no explicit ordinal
  TComputed = (cA = Ord('A'), cB); // CONTROL ordinal not a literal: not judged

  TMyRec = record
    X: Integer;
  end;

  TObj = class(TComponent)
  private
    FStamp: TSQLTimeStamp;
    FKind: TGap;
    FRec: TMyRec;
    FPlain: TPlain;
    FLib: TLibStamp;
  protected
    procedure DefineProperties(Filer: TFiler); override;
  published
    property Stamp: TSQLTimeStamp read FStamp write FStamp; // EXPECT published-record-property info
    property Kind: TGap read FKind write FKind; // EXPECT enum-no-typeinfo warning
    property Rec: TMyRec read FRec write FRec; // EXPECT published-record-property warning
    property Plain: TPlain read FPlain write FPlain; // CONTROL enum with type info
    property LibStamp: TLibStamp read FLib write FLib; // LIBONLY published-record-property warning
  end;

  TClean = class(TPersistent) // CONTROL TPersistent descendant with a published section
  private
    FName: string;
  published
    property Name: string read FName write FName;
  end;

  TChild = class(TClean) // CONTROL ancestry through a class of this unit
  private
    FExtra: string;
  published
    property Extra: string read FExtra write FExtra;
  end;

  TViaLib = class(TLibComponent) // CONTROL ancestor known only to the library: unknown -> silent, TPersistent with it
  private
    FTag2: Integer;
  published
    property Tag2: Integer read FTag2 write FTag2;
  end;

  TBare = class // EXPECT published-without-persistent warning
  private
    FValue: Integer;
  published
    property Value: Integer read FValue write FValue;
  end;

{$M+}
  TMarked = class // CONTROL declared under $M+
  private
    FV: Integer;
  published
    property V: Integer read FV write FV;
  end;
{$M-} // EXPECT rtti-narrowing-directive warning

  TAfterM = class // EXPECT published-without-persistent warning
  private
    FW: Integer;
  published
    property W: Integer read FW write FW;
  end;

  TMarkedChild = class(TMarked) // CONTROL ancestor declared under $M+
  private
    FU: Integer;
  published
    property U: Integer read FU write FU;
  end;

implementation

procedure TObj.DefineProperties(Filer: TFiler);
begin
  inherited;
  Filer.DefineProperty('Stamp', nil, nil, True);
end;

end.
