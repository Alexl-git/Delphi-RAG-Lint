unit DRagLint.Charts.Q.DepMatrix;

{ drag-lint 1.56 -- lane CHA-1: the chart question `dependency-matrix` (`ask dependency-matrix`).
  G-40: the unit dependency matrix (library units as one row), drawn by DRagLint.Charts.Adapter.Grid.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT).

  Data (single index, read-only, all through TChartsIndex.Query): the unit symbols are the rows and columns; the
  cell (row, column) is filled when the row's unit has a unit_uses entry naming the column's unit, 'I' when any such
  entry is in the interface section, 'i' when every one is in the implementation section. A unit_uses entry naming
  no indexed unit (RTL, VCL, third party) is a LIBRARY use: all of them share ONE extra row/column "lib"; its cell
  holds the number of DISTINCT library units the row's unit uses. Self-uses are not drawn.
  Selection: the matrix is project-wide (Target is accepted and ignored); when there are more units than Cap
  (default 40) the Cap units with the most edges are shown and the rest are counted as hidden.
  Counts: LeftCount = units shown, RightCount = filled unit-to-unit cells (distinct pairs). }

interface

const
  /// <summary>The registered question id.</summary>
  DEP_MATRIX_ID = 'dependency-matrix';

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Adapter.Grid;

const
  DEFAULT_CAP = 40;
  INTF_FILL = '#FDECEE';
  IMPL_FILL = '#FEF6EC';
  LIB_FILL = '#EDF2FF';
  LIB_COLUMN = 'lib';
  INTF_MARK = 'I';
  IMPL_MARK = 'i';

type
  /// <summary>One indexed unit.</summary>
  TUnitInfo = record
    Name: string;
    Path: string;
    Line: Integer;
    Degree: Integer;
  end;

function PairKey(const pSrc, pDst: string): string;
begin
  Result:= pSrc + '|' + pDst;
end;

/// <summary>Answers `dependency-matrix`: the unit-to-unit uses matrix plus one library row/column.</summary>
/// <param name="pArgs">The question arguments; Target is ignored (project-wide); Cap bounds the unit count.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = units shown, RightCount = filled unit-to-unit cells.</returns>
/// <remarks>Read-only. Meta fields: Units, Edges, InterfaceEdges, LibraryRows, LibraryUnits, Hidden, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var All: TArray<TUnitInfo>:= [];
  var Known:= TDictionary<string, Integer>.Create;
  var Intf:= TDictionary<string, Boolean>.Create;     // 'src|dst' -> any interface-section use
  var Libs:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);  // src -> distinct library unit names
  try
    var UnitRows:= Index.Query('SELECT s.qualified_name AS q, f.path AS path, s.start_line AS line' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''unit'' ORDER BY LOWER(s.qualified_name), s.id');
    try
      for var R in UnitRows do
        if not Known.ContainsKey(R.S('q').ToLowerInvariant) then
        begin
          var U:= Default(TUnitInfo);
          U.Name:= R.S('q');
          U.Path:= R.S('path');
          U.Line:= R.I('line');
          Known.Add(U.Name.ToLowerInvariant, Length(All));
          All:= All + [U];
        end;
    finally
      UnitRows.Free;
    end;

    var EdgeRows:= Index.Query('SELECT LOWER(su.qualified_name) AS src, uu.unit_name AS dst, uu.section AS section' + sLineBreak +
      '  FROM unit_uses uu JOIN symbols su ON su.file_id = uu.file_id AND su.kind = ''unit''');
    try
      for var E in EdgeRows do
      begin
        var Src:= E.S('src');
        var Dst:= E.S('dst').ToLowerInvariant;
        if (Src = Dst) or not Known.ContainsKey(Src) then
          Continue;
        if Known.ContainsKey(Dst) then
        begin
          var Key:= PairKey(Src, Dst);
          var Was: Boolean;
          if not Intf.TryGetValue(Key, Was) then
            Was:= False;
          Intf.AddOrSetValue(Key, Was or SameText(E.S('section'), 'interface'));
        end
        else
        begin
          var LibSet: TDictionary<string, Boolean>;
          if not Libs.TryGetValue(Src, LibSet) then
          begin
            LibSet:= TDictionary<string, Boolean>.Create;
            Libs.Add(Src, LibSet);
          end;
          LibSet.AddOrSetValue(Dst, True);
        end;
      end;
    finally
      EdgeRows.Free;
    end;

    // degree = edges touching the unit; the cap keeps the busiest units
    for var Key in Intf.Keys do
    begin
      var Cut:= Key.IndexOf('|');
      Inc(All[Known[Key.Substring(0, Cut)]].Degree);
      Inc(All[Known[Key.Substring(Cut + 1)]].Degree);
    end;
    var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    var Order: TArray<Integer>:= [];
    for var K:= 0 to High(All) do
      Order:= Order + [K];
    if Length(All) > Cap then
    begin
      TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
        function(const pA, pB: Integer): Integer
        begin
          Result:= All[pB].Degree - All[pA].Degree;
          if Result = 0 then
            Result:= CompareText(All[pA].Name, All[pB].Name);
        end));
      SetLength(Order, Cap);
    end;
    TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
      function(const pA, pB: Integer): Integer
      begin
        Result:= CompareText(All[pA].Name, All[pB].Name);
      end));

    var Cols: TArray<string>:= [];
    for var K:= 1 to Length(Order) do
      Cols:= Cols + [IntToStr(K)];
    Cols:= Cols + [LIB_COLUMN];
    var Rows: TArray<TGridRow>:= [];
    var Edges:= 0;
    var IntfEdges:= 0;
    var LibRows:= 0;
    var Expected:= 0;
    var LibNames:= TDictionary<string, Boolean>.Create;
    try
      for var K:= 0 to High(Order) do
      begin
        var U:= All[Order[K]];
        var LowSrc:= U.Name.ToLowerInvariant;
        var Row:= Default(TGridRow);
        Row.Caption:= Format('%d %s', [K + 1, U.Name]);
        if U.Path <> '' then
        begin
          Row.Href:= RowHref(U.Path, U.Line);
          Inc(Expected);
        end;
        SetLength(Row.Cells, Length(Cols));
        for var L:= 0 to High(Order) do
        begin
          var IsIntf: Boolean;
          if Intf.TryGetValue(PairKey(LowSrc, All[Order[L]].Name.ToLowerInvariant), IsIntf) then
          begin
            Inc(Edges);
            if IsIntf then
              Inc(IntfEdges);
            Row.Cells[L].Text:= if IsIntf then INTF_MARK else IMPL_MARK;
            Row.Cells[L].Fill:= if IsIntf then INTF_FILL else IMPL_FILL;
            Row.Cells[L].Tip:= Format('%s uses %s', [U.Name, All[Order[L]].Name]);
          end;
        end;
        var LibSet: TDictionary<string, Boolean>;
        if Libs.TryGetValue(LowSrc, LibSet) and (LibSet.Count > 0) then
        begin
          Inc(LibRows);
          for var N in LibSet.Keys do
            LibNames.AddOrSetValue(N, True);
          Row.Cells[High(Cols)].Text:= IntToStr(LibSet.Count);
          Row.Cells[High(Cols)].Fill:= LIB_FILL;
          Row.Cells[High(Cols)].Tip:= Format('%s uses %d library unit(s)', [U.Name, LibSet.Count]);
        end;
        Rows:= Rows + [Row];
      end;

      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, GridDot('dependency_matrix', 'uses', Cols, Rows), pOutDir, 'dependency_matrix', Msgs);
      Result.LeftCount:= Length(Order);
      Result.RightCount:= Edges;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.Fields:= [TMetaField.Int('Units', Length(Order)), TMetaField.Int('Edges', Edges),
        TMetaField.Int('InterfaceEdges', IntfEdges), TMetaField.Int('LibraryRows', LibRows),
        TMetaField.Int('LibraryUnits', LibNames.Count), TMetaField.Int('Hidden', Length(All) - Length(Order)),
        TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Expected),
        TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      LibNames.Free;
    end;
  finally
    Libs.Free;
    Intf.Free;
    Known.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(DEP_MATRIX_ID, Emit);

end.
