unit wsl_core;

{ The "library" half of WITH-SELF-PROP: indexed into its own DB, opened by the
  resolve pass as --library-db. The project DB holds none of these types. }

interface

type
  TLibRoot = class
  public
    RootShadow: Integer;
    procedure LibRootCall;
  end;

  TLibBase = class(TLibRoot)
  public
    ShadowProp: Integer;
    procedure LibCall;
  end;

  { Its chain leaves the library: TNotInThisLibrary is declared nowhere. }
  TLibLeaves = class(TNotInThisLibrary)
  public
    procedure LeavesCall;
  end;

  TLibHelped = class
  public
    procedure HelpedCall;
  end;

  { A helper on a library type is in the with scope of a descendant. }
  TLibHelpedHelper = class helper for TLibHelped
  public
    procedure HelperCall;
  end;

  { Same leaf name as wsl_other.TLibTwice, which alone declares TwiceCall. }
  TLibTwice = class
  public
    procedure OtherCall;
  end;

  TLibForProjectHelper = class
  public
    procedure PlainCall;
  end;

implementation

procedure TLibRoot.LibRootCall; begin end;
procedure TLibBase.LibCall; begin end;
procedure TLibLeaves.LeavesCall; begin end;
procedure TLibHelped.HelpedCall; begin end;
procedure TLibHelpedHelper.HelperCall; begin end;
procedure TLibTwice.OtherCall; begin end;
procedure TLibForProjectHelper.PlainCall; begin end;

end.