unit DRagLint.Charts.Q.ChangeCoupling;

{ drag-lint 1.56 -- lane G46: the chart question `change-coupling` (`ask change-coupling`).
  G-46: units that change together in the version control history (git and hg), whether or not one uses the other.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question.

  Data: the commit log of the working copy that holds the indexed units (DRagLint.Query.Vcs.ReadCommitLog), read at
  run time; nothing about it is stored in the index. The index only decides WHICH files count: a pair is two
  indexed units (a unit symbol of the index whose file is on disk), so a file the index does not hold is never
  guessed into a pair.
  Arguments: --since <rev|YYYY-MM-DD> (default: the whole history; a revision is excluded, its later commits are
  read), --min-support N (default 2: a pair needs at least N shared commits), --cap N (pairs listed, default 20).
  Counting (the same for git and hg):
    * merge commits are not read; a rename is never detected by similarity: the old name is a deleted file, the
      new name an added one;
    * a commit that touches more than MECHANICAL_FILES files is a mechanical change (a rename of a folder, a
      formatter run) and is skipped; it is counted as Excluded;
    * support of a unit = counted commits that added or modified it; co-changes of a pair = counted commits that
      added or modified both;
    * weight = 2 * co-changes / (support A + support B), 0..1 (the pair's shared share of the two units' changes).
  Deleted files and files named by the log that are no longer on disk are reported (Gone), never paired; a
  touched file that exists but is no indexed unit is counted as Unindexed.
  Output: change_coupling.dot (a grid, one row per pair) plus change_coupling_pairs.csv
  (unit_a,unit_b,co_changes,support_a,support_b,weight) beside it.
  Counts: LeftCount = distinct units in the listed pairs, RightCount = pairs listed. }

interface

const
  /// <summary>The registered question id.</summary>
  CHANGE_COUPLING_ID = 'change-coupling';
  /// <summary>A commit touching more files than this is mechanical and is not counted.</summary>
  MECHANICAL_FILES = 40;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, System.Generics.Defaults, System.Math,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Adapter.Grid, DRagLint.Query.Vcs;

const
  DEFAULT_MIN_SUPPORT = 2;
  PAIR_FILL = '#EDF2FF';
  WEIGHT_SCALE = 2.0;
  PAIR_SHIFT = 32; { a pair of unit numbers is one Int64: the first in the high half }
  PAIR_MASK = $FFFFFFFF;
  ARG_SINCE = 'Since';
  ARG_MIN_SUPPORT = 'MinSupport';

type
  /// <summary>One unit pair that changed together.</summary>
  TPairInfo = record
    A: Integer;
    B: Integer;
    Co: Integer;
    Weight: Double;
  end;

function PathKey(const pPath: string): string;
begin
  Result:= LowerCase(StringReplace(pPath, '/', '\', [rfReplaceAll]));
end;

function Num(pValue: Double): string;
begin
  Result:= Format('%.2f', [pValue], TFormatSettings.Invariant);
end;

function PairId(pA, pB: Integer): Int64;
begin
  Result:= (Int64(pA) shl PAIR_SHIFT) or pB;
end;

/// <summary>Answers `change-coupling`: the unit pairs that changed together in the VCS history.</summary>
/// <param name="pArgs">The question arguments; Target is ignored; Cap bounds the pairs listed; the command's
/// Since and MinSupport select the history and the minimum shared commits.</param>
/// <param name="pOutDir">Where dot, svg, plain, png, pdf and the pairs csv are written.</param>
/// <returns>The chart result: LeftCount = units in the listed pairs, RightCount = pairs listed.</returns>
/// <exception cref="EChartsQuestion">No working copy holds the units, the revision is unknown, the tool does not
/// run, or --min-support is not a positive integer.</exception>
/// <remarks>Read-only. Meta fields: Commits, Excluded, Units, PairsAll, Pairs, Gone, Unindexed, Vcs.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var MinSupport:= DEFAULT_MIN_SUPPORT;
  var Typed:= pArgs.Command.Get(ARG_MIN_SUPPORT);
  if (Typed <> '') and (not TryStrToInt(Typed, MinSupport) or (MinSupport < 1)) then
    raise EChartsQuestion.Create('--min-support needs a positive integer, got "' + Typed + '"');
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Names: TArray<string>:= [];
  var Paths: TArray<string>:= [];
  var Lines: TArray<Integer>:= [];
  var ByPath:= TDictionary<string, Integer>.Create;
  try
    var UnitRows:= Index.Query('SELECT s.qualified_name AS q, f.path AS path, s.start_line AS line' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''unit'' ORDER BY LOWER(s.qualified_name), s.id');
    try
      for var R in UnitRows do
      begin
        var Full:= ExpandFileName(R.S('path'));
        if FileExists(Full) and not ByPath.ContainsKey(PathKey(Full)) then
        begin
          ByPath.Add(PathKey(Full), Length(Names));
          Names:= Names + [R.S('q')];
          Paths:= Paths + [Full];
          Lines:= Lines + [R.I('line')];
        end;
      end;
    finally
      UnitRows.Free;
    end;
    if Length(Names) = 0 then
      raise EChartsQuestion.Create('change-coupling: no indexed unit of this index exists on disk');

    var Wc: TVcsWorkingCopy;
    var Refusal: string;
    if not FindWorkingCopy(ExtractFileDir(Paths[0]), Wc, Refusal) then
      raise EChartsQuestion.Create('change-coupling: ' + Refusal);
    var Commits: TArray<TVcsCommit>;
    if not ReadCommitLog(Wc, pArgs.Command.Get(ARG_SINCE), Commits, Refusal) then
      raise EChartsQuestion.Create('change-coupling: ' + Refusal);

    var Support: TArray<Integer>;
    SetLength(Support, Length(Names));
    var Co:= TDictionary<Int64, Integer>.Create;
    var Gone:= TDictionary<string, Boolean>.Create;
    var Unindexed:= TDictionary<string, Boolean>.Create;
    try
      var Counted:= 0;
      var Excluded:= 0;
      for var C in Commits do
      begin
        if Length(C.Files) > MECHANICAL_FILES then
        begin
          Inc(Excluded);
          Continue;
        end;
        Inc(Counted);
        var Touched: TArray<Integer>:= [];
        for var F in C.Files do
        begin
          var At: Integer;
          if (F.Status <> 'D') and ByPath.TryGetValue(PathKey(F.Path), At) then
          begin
            if not TArray.Contains<Integer>(Touched, At) then
              Touched:= Touched + [At];
          end
          else if (F.Status = 'D') or not FileExists(F.Path) then
            Gone.AddOrSetValue(PathKey(F.Path), True)
          else
            Unindexed.AddOrSetValue(PathKey(F.Path), True);
        end;
        TArray.Sort<Integer>(Touched);
        for var K:= 0 to High(Touched) do
        begin
          Inc(Support[Touched[K]]);
          for var L:= K + 1 to High(Touched) do
          begin
            var Key:= PairId(Touched[K], Touched[L]);
            var Was: Integer;
            if not Co.TryGetValue(Key, Was) then
              Was:= 0;
            Co.AddOrSetValue(Key, Was + 1);
          end;
        end;
      end;

      var All: TArray<TPairInfo>:= [];
      for var Pair in Co do
        if Pair.Value >= MinSupport then
        begin
          var P:= Default(TPairInfo);
          P.A:= Integer(Pair.Key shr PAIR_SHIFT);
          P.B:= Integer(Pair.Key and PAIR_MASK);
          P.Co:= Pair.Value;
          P.Weight:= WEIGHT_SCALE * Pair.Value / (Support[P.A] + Support[P.B]);
          All:= All + [P];
        end;
      TArray.Sort<TPairInfo>(All, TComparer<TPairInfo>.Construct(
        function(const pX, pY: TPairInfo): Integer
        begin
          Result:= CompareValue(pY.Weight, pX.Weight);
          if Result = 0 then
            Result:= pY.Co - pX.Co;
          if Result = 0 then
            Result:= CompareText(Names[pX.A] + '|' + Names[pX.B], Names[pY.A] + '|' + Names[pY.B]);
        end));
      var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
      var Shown:= Length(All);
      if Shown > Cap then
        Shown:= Cap;

      var Cols: TArray<string>:= ['co-changes', 'commits A', 'commits B', 'weight'];
      var Rows: TArray<TGridRow>:= [];
      var InPairs:= TDictionary<Integer, Boolean>.Create;
      var Csv:= TStringBuilder.Create;
      try
        Csv.AppendLine('unit_a,unit_b,co_changes,support_a,support_b,weight');
        for var K:= 0 to Shown - 1 do
        begin
          var P:= All[K];
          InPairs.AddOrSetValue(P.A, True);
          InPairs.AddOrSetValue(P.B, True);
          var Row:= Default(TGridRow);
          Row.Caption:= Format('%d %s <-> %s', [K + 1, Names[P.A], Names[P.B]]);
          Row.Href:= RowHref(Paths[P.A], Lines[P.A]);
          SetLength(Row.Cells, Length(Cols));
          Row.Cells[0].Text:= IntToStr(P.Co);
          Row.Cells[0].Fill:= PAIR_FILL;
          Row.Cells[0].Tip:= Format('%s and %s changed together in %d commit(s)', [Names[P.A], Names[P.B], P.Co]);
          Row.Cells[1].Text:= IntToStr(Support[P.A]);
          Row.Cells[2].Text:= IntToStr(Support[P.B]);
          Row.Cells[3].Text:= Num(P.Weight);
          Rows:= Rows + [Row];
          Csv.AppendLine(Format('%s,%s,%d,%d,%d,%s', [Names[P.A], Names[P.B], P.Co, Support[P.A], Support[P.B],
            Num(P.Weight)]));
        end;
        TFile.WriteAllText(TPath.Combine(pOutDir, 'change_coupling_pairs.csv'), Csv.ToString, TEncoding.UTF8);
        var Msgs: TArray<string>;
        Result.Layout:= DotLayout(pArgs.Dot, GridDot('change_coupling', 'pair', Cols, Rows), pOutDir, 'change_coupling', Msgs);
        Result.LeftCount:= InPairs.Count;
        Result.RightCount:= Shown;
        Result.ClickTargets:= Result.Layout.Anchors;
        Result.AllClickable:= Result.Layout.Anchors >= Shown;
        Result.Fields:= [TMetaField.Int('Commits', Counted), TMetaField.Int('Excluded', Excluded),
          TMetaField.Int('Units', Length(Names)), TMetaField.Int('PairsAll', Length(All)),
          TMetaField.Int('Pairs', Shown), TMetaField.Int('Gone', Gone.Count),
          TMetaField.Int('Unindexed', Unindexed.Count), TMetaField.Str('Vcs', VcsKindName(Wc.Kind)),
          TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Shown),
          TMetaField.Bool('AllClickable', Result.AllClickable)];
      finally
        Csv.Free;
        InPairs.Free;
      end;
    finally
      Unindexed.Free;
      Gone.Free;
      Co.Free;
    end;
  finally
    ByPath.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CHANGE_COUPLING_ID, Emit);

end.