unit DRagLint.Charts.Adapter.Grid;

{ drag-lint 1.56 -- lane CHA-1: the grid (matrix) chart adapter of gap-plan S7, the layout of `ask dependency-matrix`.
  A grid is one DOT HTML-label table: a header row of column numbers, then one row per item with its label, an
  optional click-through and one cell per column. The adapter only LAYS OUT cells it is given; what a cell means
  belongs to the question that fills it. Pure text: no index access, no files.
  Registering it with DRagLint.Charts.Adapters is a request to that unit's owner. }

interface

type
  /// <summary>One cell of a grid.</summary>
  TGridCell = record
    /// <summary>Plain text shown in the cell; '' = an empty cell.</summary>
    Text: string;
    /// <summary>Plain tooltip; '' = none. Written as the TD TOOLTIP, so the .dot names every filled cell.</summary>
    Tip: string;
    /// <summary>Background colour as #RRGGBB; '' = none.</summary>
    Fill: string;
  end;

  /// <summary>One row of a grid: its label, where the label clicks through to, and its cells.</summary>
  TGridRow = record
    /// <summary>Plain row label (the item's name, numbered by the caller).</summary>
    Caption: string;
    /// <summary>Click-through target of the label; '' = not clickable.</summary>
    Href: string;
    /// <summary>One cell per column; a shorter array is padded with empty cells.</summary>
    Cells: TArray<TGridCell>;
  end;

/// <summary>Lays a grid out as DOT text.</summary>
/// <param name="pGraphName">The digraph name (letters, digits, underscore).</param>
/// <param name="pCorner">Plain text of the top-left corner cell.</param>
/// <param name="pColumns">Plain column header texts, left to right.</param>
/// <param name="pRows">The rows, top to bottom.</param>
/// <returns>A complete digraph holding one plaintext node whose label is the table.</returns>
/// <remarks>Pure; every text is XML-escaped. Rows shorter than pColumns are padded, never truncated.</remarks>
function GridDot(const pGraphName, pCorner: string; const pColumns: TArray<string>; const pRows: TArray<TGridRow>): string;

implementation

uses
  System.SysUtils, DRagLint.Charts.Text;

const
  HEADER_FILL = '#E5E9F0';
  CELL_FONT_SIZE = 12;

function CellOpen(const pFill, pTip: string): string;
begin
  Result:= '<TD';
  if pFill <> '' then
    Result:= Result + ' BGCOLOR="' + pFill + '"';
  if pTip <> '' then
    Result:= Result + ' TOOLTIP="' + XmlText(pTip) + '"';
  Result:= Result + '>';
end;

function GridDot(const pGraphName, pCorner: string; const pColumns: TArray<string>; const pRows: TArray<TGridRow>): string;
begin
  var Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine('digraph ' + pGraphName + ' {');
    Sb.AppendLine('  bgcolor="transparent";');
    Sb.AppendLine(Format('  node [shape=plaintext, fontname="Consolas", fontsize=%d];', [CELL_FONT_SIZE]));
    Sb.AppendLine('  grid [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4">');
    Sb.Append('<TR>').Append(CellOpen(HEADER_FILL, '')).Append(XmlText(pCorner)).Append('</TD>');
    for var C in pColumns do
      Sb.Append(CellOpen(HEADER_FILL, '')).Append(XmlText(C)).Append('</TD>');
    Sb.AppendLine('</TR>');
    for var R in pRows do
    begin
      Sb.Append('<TR><TD ALIGN="LEFT" BGCOLOR="').Append(HEADER_FILL).Append('"');
      if R.Href <> '' then
        Sb.Append(' HREF="').Append(R.Href).Append('"');
      Sb.Append('>').Append(XmlText(R.Caption)).Append('</TD>');
      for var K:= 0 to High(pColumns) do
      begin
        var Cell:= Default(TGridCell);
        if K <= High(R.Cells) then
          Cell:= R.Cells[K];
        Sb.Append(CellOpen(Cell.Fill, Cell.Tip)).Append(XmlText(Cell.Text)).Append('</TD>');
      end;
      Sb.AppendLine('</TR>');
    end;
    Sb.AppendLine('</TABLE>>];');
    Sb.AppendLine('}');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
