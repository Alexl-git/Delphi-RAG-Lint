unit BfShape;

// CYCC B4-f fixture: the class the consumer BfCanvas tests, casts and reads.

interface

type
  /// <summary>A shape with a name; Draw hands itself to the canvas.</summary>
  TBfShape = class
  private
    FName: string;
  public
    /// <summary>Creates a named shape.</summary>
    /// <param name="pName">The name.</param>
    constructor Create(const pName: string);
    /// <summary>Paints the shape on the canvas.</summary>
    procedure Draw;
    /// <summary>The name given at creation.</summary>
    property Name: string read FName;
  end;

implementation

uses
  BfCanvas;

constructor TBfShape.Create(const pName: string);
begin
  inherited Create;
  FName := pName;
end;

procedure TBfShape.Draw;
begin
  BfCanvasPaint(Self, 1);
  BfCanvasPaint(Self, 'x');
end;

end.