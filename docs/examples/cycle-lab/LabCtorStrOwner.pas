unit LabCtorStrOwner;

// cycle-lab, LabCtorStr: the owner names its children in fields of its INTERFACE and constructs them in
// its implementation (the Loader2025 shape, two statements on a line included). The literals spell the
// class names: the constructor inversion must leave them byte-identical.

interface

uses
  LabCtorStrChild;

type
  /// <summary>Owns one of each child.</summary>
  TLabCtorStrOwner = class
  private
    FChild: TLabCtorStrChild;
    FArg  : TLabCtorStrArg;
    FBare : TLabCtorStrBare;
  public
    /// <summary>Constructs the children.</summary>
    constructor Create;
    /// <summary>Frees the children.</summary>
    destructor Destroy; override;
    /// <summary>Exercises every child, and one through a local.</summary>
    procedure Run;
    /// <summary>The owner's name.</summary>
    /// <returns>A fixed text.</returns>
    class function Label_: string;
  end;

implementation

uses
  System.SysUtils;

constructor TLabCtorStrOwner.Create;
begin
  inherited Create;
  FChild := TLabCtorStrChild.Create(nil); FChild.Configure('TLabCtorStrChild.Create(nil)', 1);
  FArg := TLabCtorStrArg.Create('TLabCtorStrArg.Create', 2);
  FBare := TLabCtorStrBare.Create;
end;

destructor TLabCtorStrOwner.Destroy;
begin
  FreeAndNil(FBare);
  FArg.Free;
  if FChild <> nil then FChild.Free;
  inherited;
end;

procedure TLabCtorStrOwner.Run;
var
  Local: TLabCtorStrArg;
begin
  FChild.Greet;
  FArg.Show;
  FBare.Ping;
  Local := TLabCtorStrArg.Create('default id'); // TLabCtorStrArg.Create in a comment
  try
    Local.Show;
  finally
    Local.Free;
  end;
end;

class function TLabCtorStrOwner.Label_: string;
begin
  Result := 'owner';
end;

end.
