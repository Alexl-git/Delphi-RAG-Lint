unit LabCtorStrChild;

// cycle-lab, LabCtorStr: three classes the owner constructs, each with bodies that use the owner's unit,
// so none can move. Shapes of the constructor inversion: an INHERITED constructor (TComponent.Create),
// an own constructor with a string and a default parameter, and a parameterless one called without parentheses.

interface

uses
  System.Classes;

type
  /// <summary>Inherits its constructor from a library class, as a TDataModule does.</summary>
  TLabCtorStrChild = class(TComponent)
  private
    FTitle: string;
  public
    /// <summary>Sets the title.</summary>
    /// <param name="pTitle">The title.</param>
    /// <param name="pId">Appended to it.</param>
    procedure Configure(const pTitle: string; pId: Integer);
    /// <summary>Prints the title and the owner's name.</summary>
    procedure Greet;
  end;

  /// <summary>An own constructor with a default parameter.</summary>
  TLabCtorStrArg = class
  private
    FText: string;
  public
    /// <summary>Remembers the text.</summary>
    /// <param name="pText">The text.</param>
    /// <param name="pId">Appended to it.</param>
    constructor Create(const pText: string; pId: Integer = 7);
    /// <summary>Prints the text and the owner's name.</summary>
    procedure Show;
  end;

  /// <summary>A parameterless own constructor.</summary>
  TLabCtorStrBare = class
  public
    /// <summary>Prints that it was built.</summary>
    constructor Create;
    /// <summary>Prints the owner's name.</summary>
    procedure Ping;
  end;

implementation

uses
  System.SysUtils,
  LabCtorStrOwner;

procedure TLabCtorStrChild.Configure(const pTitle: string; pId: Integer);
begin
  FTitle := Format('%s/%d', [pTitle, pId]);
end;

procedure TLabCtorStrChild.Greet;
begin
  Writeln('[str] ', FTitle, ' of ', TLabCtorStrOwner.Label_);
end;

constructor TLabCtorStrArg.Create(const pText: string; pId: Integer);
begin
  inherited Create;
  FText := Format('%s/%d', [pText, pId]);
end;

procedure TLabCtorStrArg.Show;
begin
  Writeln('[arg] ', FText, ' of ', TLabCtorStrOwner.Label_);
end;

constructor TLabCtorStrBare.Create;
begin
  inherited Create;
  Writeln('[bare] built');
end;

procedure TLabCtorStrBare.Ping;
begin
  Writeln('[bare] ping of ', TLabCtorStrOwner.Label_);
end;

end.
