unit uRttiClean;

{ Fixture of the rtti-unavailable rule: a clean component unit -- no finding at all. }

interface

uses
  System.Classes;

type
  TCleanKind = (ckNone, ckOne, ckTwo);

  TCleanComponent = class(TComponent)
  private
    FKind: TCleanKind;
    FCaption: string;
  published
    property Kind: TCleanKind read FKind write FKind;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
