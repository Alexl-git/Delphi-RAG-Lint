unit DRagLint.Query.Regions;

{ drag-lint 1.56 -- lane IDX-U: the $REGION / $ENDREGION directive pairs of a unit, each with an id and a line span, for `outline`.
  Called from the routine DoOutline of DRagLint.CLI (lane IDX-U).
  Reads the SOURCE TEXT (the index does not store directives), so it needs no schema or extractor change. }

interface

type
  /// <summary>One {$REGION 'id'} ... {$ENDREGION} pair.</summary>
  TRegionSpan = record
    /// <summary>The text of the quoted region id ('' for a bare {$REGION}).</summary>
    Id       : string ;
    /// <summary>1-based line of the {$REGION directive.</summary>
    StartLine: Integer;
    /// <summary>1-based line of the matching {$ENDREGION; 0 when it is missing.</summary>
    EndLine  : Integer;
    /// <summary>Nesting depth, 0 = outermost.</summary>
    Depth    : Integer;
  end;

/// <summary>FindRegions over a file on disk.</summary>
/// <param name="AFileName">Path of the unit; an unreadable or missing file gives no rows.</param>
/// <returns>See FindRegions.</returns>
function FindRegionsInFile(const AFileName: string): TArray<TRegionSpan>;

implementation

uses
    System.SysUtils
  , System.Classes
  , System.IOUtils
  ;

function DirectiveArg(const ALine: string; const ATag: string; out AArg: string): Boolean;
begin
  AArg:= '';
  var At: Integer:= Pos('{$' + ATag, UpperCase(ALine));
  Result:= At > 0;
  if not Result then Exit;
  var After: Integer:= At + 2 + Length(ATag);
  { {$REGIONX is some other directive; the tag must end at a space or the closing brace }
  if (After <= Length(ALine)) and not CharInSet(ALine[After], [' ', '}', #9]) then Exit(False);
  var Close: Integer:= Pos('}', ALine, After);
  if Close = 0 then Close:= Length(ALine) + 1;
  AArg:= Trim(Copy(ALine, After, Close - After));
  if (Length(AArg) >= 2) and (AArg[1] = '''') and (AArg[Length(AArg)] = '''') then AArg:= Copy(AArg, 2, Length(AArg) - 2);
end;

/// <summary>Pairs the {$REGION} / {$ENDREGION} directives of one unit's source.</summary>
/// <param name="ASource">The unit text; any line-ending style.</param>
/// <returns>One row per {$REGION} in the order the regions OPEN; a region never closed has EndLine 0;
///  a stray {$ENDREGION} is ignored.</returns>
/// <remarks>Pure function. A directive on a // comment line is ignored. Not thread-shared state.</remarks>
function FindRegions(const ASource: string): TArray<TRegionSpan>;
begin
  Result:= nil;
  var Lines: TArray<string>:= ASource.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  var Open : TArray<Integer>:= nil; { indexes into Result of the regions still open }
  for var I: Integer:= 0 to High(Lines) do
  begin
    if TrimLeft(Lines[I]).StartsWith('//') then Continue;
    var Arg: string;
    if DirectiveArg(Lines[I], 'REGION', Arg) then
    begin
      var R: TRegionSpan;
      R.Id       := Arg;
      R.StartLine:= I + 1;
      R.EndLine  := 0;
      R.Depth    := Length(Open);
      Result:= Result + [R];
      Open  := Open + [High(Result)];
    end
    else if DirectiveArg(Lines[I], 'ENDREGION', Arg) and (Length(Open) > 0) then
    begin
      Result[Open[High(Open)]].EndLine:= I + 1;
      SetLength(Open, Length(Open) - 1);
    end;
  end;
end;

function FindRegionsInFile(const AFileName: string): TArray<TRegionSpan>;
begin
  Result:= nil;
  if not TFile.Exists(AFileName) then Exit;
  try
    Result:= FindRegions(TFile.ReadAllText(AFileName, TEncoding.Default));
  except
    on EInOutError do Result:= nil;
  end;
end;

end.
