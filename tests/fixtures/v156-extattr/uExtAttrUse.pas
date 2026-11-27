unit uExtAttrUse;

{ Fixture for run_v156_EXTATTR.ps1. Every marked line holds the attribute forms named in its
  marker; the runner reads the line numbers from the markers. }

interface

uses
  ExtAttr.Common.Attrs;

type
  TService = class
  end;

  TConsumer = class
  private
    [Inject] { M-BARE }
    FBare: TService;
    [ExtAttr.Common.Attrs.Inject] { M-QUAL }
    FQual: TService;
    [Named('one')] { M-ARGS }
    FArgs: TService;
    [ExtAttr.Common.Attrs.Named('two')] { M-QUAL-ARGS }
    FQualArgs: TService;
    [WeakRef, Tag] { M-LIST }
    FList: TService;
    [ExtAttr.Common.Attrs.WeakRef, ExtAttr.Common.Attrs.Named(ExtAttr.Common.Attrs.DefaultName)] { M-QUAL-LIST }
    FQualList: TService;
    [InjectAttribute] { M-FULL }
    FFull: TService;
    [ExtAttr.Common.Attrs.InjectAttribute] { M-QUAL-FULL }
    FQualFull: TService;
    [NotIndexed] { M-UNKNOWN }
    FUnknown: TService;
  public
    function Control: string;
  end;

implementation

function TConsumer.Control: string;
begin
  Result:= ExtAttr.Common.Attrs.DefaultName; { M-CONTROL }
end;

end.
