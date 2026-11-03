unit DRagLint.Query.SyntaxCount;

{ GAP-SYNTAXQ (backlog 2026-11-01; gaps.log 2026-10-30T06:32:46 "unsupported"):
  the `syntax-count` verb -- how often a codebase uses a modern syntax feature
  (Delphi 13 ternary `if`, `is not`, `not in`; inline var / const; anonymous
  methods; multiline strings). `query --text` covers strings and comments only
  and caps at 200 hits; this counts SHAPES in the tree-sitter parse, uncapped.

  Query-time only: every file is parsed again at the call (TAstParseCache, raw
  bytes, no preprocessing -- what is WRITTEN, every $IFDEF branch included). The
  index is read for nothing but the file list (files.path); no row is written,
  so the extractor fingerprint is untouched. }

interface

uses
  System.SysUtils, System.JSON, TreeSitter;

type
  /// <summary>One syntax feature the count recognises in the parse.</summary>
  /// <remarks>Grammar shapes (tree-sitter-delphi13): sfIfExpr = exprIf;
  /// sfIsNot = exprBinary(kIs) whose rhs is exprUnary(kNot); sfNotIn = exprBinary
  /// carrying kNot then kIn; sfInlineVar = varDef / varAssignDef (block-level
  /// `var`, `for var`); sfInlineConst = constInline; sfAnonMethod = lambda;
  /// sfMultilineString = a literalString opening with ''' and a line break.</remarks>
  TSyntaxFeature = (sfIfExpr, sfIsNot, sfNotIn, sfInlineVar, sfInlineConst,
    sfAnonMethod, sfMultilineString);
  /// <summary>A set of syntax features to count.</summary>
  TSyntaxFeatures = set of TSyntaxFeature;
  /// <summary>One count per feature.</summary>
  TSyntaxCounts = array[TSyntaxFeature] of Integer;

  /// <summary>One occurrence: the feature and where its node starts (1-based).</summary>
  TSyntaxHit = record
    Feature : TSyntaxFeature;
    FilePath: string;
    Line    : Integer;
    Col     : Integer;
  end;

  /// <summary>The counts of one file that holds at least one occurrence.</summary>
  TSyntaxFileCount = record
    FilePath: string;
    Counts  : TSyntaxCounts;
  end;

  /// <summary>The result of one count run over a file list.</summary>
  /// <remarks>Files lists only files with at least one occurrence, in input
  /// order; Hits is filled only when the caller asked for it. A file that
  /// parses with ERROR nodes is still counted (the shapes outside the error
  /// survive) and is tallied in FilesWithParseErrors.</remarks>
  TSyntaxCountReport = record
    Features            : TSyntaxFeatures;
    Totals              : TSyntaxCounts;
    FilesScanned        : Integer;
    FilesUnreadable     : Integer;
    FilesWithParseErrors: Integer;
    Files               : TArray<TSyntaxFileCount>;
    Hits                : TArray<TSyntaxHit>;
  end;

/// <summary>The CLI name of a feature (if-expr, is-not, not-in, inline-var,
/// inline-const, anon-method, multiline-string).</summary>
/// <param name="pFeature">The feature.</param>
/// <returns>Its lower-case hyphenated name.</returns>
function SyntaxFeatureName(pFeature: TSyntaxFeature): string;

/// <summary>The first Delphi version that accepts a feature.</summary>
/// <param name="pFeature">The feature.</param>
/// <returns>A label such as 'Delphi 13'.</returns>
function SyntaxFeatureSince(pFeature: TSyntaxFeature): string;

/// <summary>Parses a comma-separated --feature list.</summary>
/// <param name="pList">Names as SyntaxFeatureName gives them, any case; 'all'
/// or an empty string selects every feature.</param>
/// <param name="pFeatures">The selected set; empty on failure.</param>
/// <param name="pBad">The first name that is not a feature; '' on success.</param>
/// <returns>True when every name is known.</returns>
function TryParseSyntaxFeatures(const pList: string; out pFeatures: TSyntaxFeatures;
  out pBad: string): Boolean;

/// <summary>Counts the selected features in one parsed tree.</summary>
/// <param name="pRoot">The root (or any) node; walked depth-first, every node visited once.</param>
/// <param name="pSrc">The UTF-8 bytes the tree was parsed from (read for string literals).</param>
/// <param name="pFeatures">The features to count; others stay 0.</param>
/// <param name="pCounts">Incremented, never reset: the caller zeroes it.</param>
/// <param name="pFilePath">Copied into each hit.</param>
/// <param name="pHits">Appended to when pWantHits is True.</param>
/// <param name="pWantHits">Record each occurrence in pHits.</param>
procedure CountTreeFeatures(const pRoot: TTSNode; const pSrc: TBytes;
  const pFeatures: TSyntaxFeatures; var pCounts: TSyntaxCounts; const pFilePath: string;
  var pHits: TArray<TSyntaxHit>; pWantHits: Boolean);

/// <summary>Parses each file and counts the selected features.</summary>
/// <param name="pFiles">Source paths (.pas / .dpr / .dpk / .inc); a missing or
/// unreadable one is tallied in FilesUnreadable, never raised.</param>
/// <param name="pFeatures">The features to count.</param>
/// <param name="pWantHits">Fill Hits with every occurrence.</param>
/// <returns>The report. Uncapped.</returns>
/// <remarks>Parses through TAstParseCache and clears it after each file, so
/// memory stays one tree; any entries the caller had cached are dropped too.
/// Not thread-safe (TAstParseCache is not).</remarks>
function CountSyntaxFeatures(const pFiles: TArray<string>; const pFeatures: TSyntaxFeatures;
  pWantHits: Boolean): TSyntaxCountReport;

/// <summary>The report as JSON: features[], files_scanned, files_unreadable,
/// files_with_parse_errors, totals{name: n}, files[{path, counts{name: n}}]
/// and, when pWithFiles / pWithHits, files[] / hits[{feature, path, line, col}].</summary>
/// <param name="pReport">The report.</param>
/// <param name="pWithFiles">Include files[].</param>
/// <param name="pWithHits">Include hits[].</param>
/// <returns>A new object; the caller frees it.</returns>
function SyntaxCountToJson(const pReport: TSyntaxCountReport; pWithFiles, pWithHits: Boolean): TJSONObject;

/// <summary>The `syntax-count` verb: parses its flags, collects the file list
/// and prints the report.</summary>
/// <param name="pArgs">The arguments after the verb: --db &lt;file.sqlite&gt;
/// and/or --file &lt;path&gt; (repeatable), [--feature a,b|all], [--per-file],
/// [--hits], [--json].</param>
/// <returns>0 = report printed (zero occurrences included); 2 = bad flags, no
/// file source, or a --db that does not open.</returns>
/// <remarks>--db reads files.path of that index only (every .pas/.dpr/.dpk/.inc
/// row); the index is opened read-only and never written.</remarks>
function RunSyntaxCountVerb(const pArgs: TArray<string>): Integer;

implementation

uses
  System.Generics.Collections, DRagLint.Diagnostics.ParseCache;

const
  CFeatureNames: array[TSyntaxFeature] of string = ('if-expr', 'is-not', 'not-in',
    'inline-var', 'inline-const', 'anon-method', 'multiline-string');
  CFeatureSince: array[TSyntaxFeature] of string = ('Delphi 13', 'Delphi 13', 'Delphi 13',
    'Delphi 10.3', 'Delphi 10.3', 'Delphi 2009', 'Delphi 12');
  CMultilineQuotes = 3; // a multiline string opens with ''' and a line break

function SyntaxFeatureName(pFeature: TSyntaxFeature): string;
begin
  Result:= CFeatureNames[pFeature];
end;

function SyntaxFeatureSince(pFeature: TSyntaxFeature): string;
begin
  Result:= CFeatureSince[pFeature];
end;

function TryParseSyntaxFeatures(const pList: string; out pFeatures: TSyntaxFeatures;
  out pBad: string): Boolean;
var
  LName: string;
  LFound: Boolean;
  F: TSyntaxFeature;
begin
  pFeatures:= [];
  pBad:= '';
  if (Trim(pList) = '') or SameText(Trim(pList), 'all') then
  begin
    pFeatures:= [Low(TSyntaxFeature)..High(TSyntaxFeature)];
    Exit(True);
  end;
  for LName in pList.Split([',']) do
  begin
    if Trim(LName) = '' then
      Continue;
    LFound:= False;
    for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
      if SameText(Trim(LName), CFeatureNames[F]) then
      begin
        Include(pFeatures, F);
        LFound:= True;
      end;
    if not LFound then
    begin
      pBad:= Trim(LName);
      pFeatures:= [];
      Exit(False);
    end;
  end;
  Result:= pFeatures <> [];
end;

{ True when ANode (an exprBinary) carries the operator tokens AFirst then ASecond
  as adjacent children: `a not in S` is exprBinary(lhs, kNot, kIn, rhs). }
function HasOperatorPair(const pNode: TTSNode; const pFirst, pSecond: string): Boolean;
var
  I: Integer;
begin
  for I:= 0 to pNode.ChildCount - 2 do
    if (pNode.Child(I).NodeType = pFirst) and (pNode.Child(I + 1).NodeType = pSecond) then
      Exit(True);
  Result:= False;
end;

{ `X is not T` is exprBinary(operator: kIs, rhs: exprUnary(operator: kNot)). The
  grammar has no other way to put a unary `not` right of `is` (`X is (not T)` is
  no Delphi), so the shape is the feature. }
function IsIsNot(const pNode: TTSNode): Boolean;
var
  LOp, LRhs: TTSNode;
begin
  LOp:= pNode.ChildByField('operator');
  LRhs:= pNode.ChildByField('rhs');
  Result:= (not LOp.IsNull) and (LOp.NodeType = 'kIs') and (not LRhs.IsNull) and
    (LRhs.NodeType = 'exprUnary') and (LRhs.ChildByField('operator').NodeType = 'kNot');
end;

{ A literalString whose text opens with ''' followed by a line break. A plain
  '''' (one quote character) also opens with three quotes, hence the break test. }
function IsMultilineString(const pNode: TTSNode; const pSrc: TBytes): Boolean;
var
  LStart, LEnd, I: Integer;
begin
  LStart:= Integer(pNode.StartByte);
  LEnd:= Integer(pNode.EndByte);
  if (LEnd - LStart <= CMultilineQuotes) or (LEnd > Length(pSrc)) then
    Exit(False);
  for I:= LStart to LStart + CMultilineQuotes - 1 do
    if pSrc[I] <> Ord('''') then
      Exit(False);
  I:= LStart + CMultilineQuotes;
  while (I < LEnd) and (pSrc[I] in [Ord(' '), 9]) do
    Inc(I);
  Result:= (I < LEnd) and (pSrc[I] in [10, 13]);
end;

{ The feature ANode is, or False. One node is at most one feature. }
function ClassifyNode(const pNode: TTSNode; const pSrc: TBytes; out pFeature: TSyntaxFeature): Boolean;
var
  LType: string;
begin
  Result:= True;
  LType:= pNode.NodeType;
  if LType = 'exprIf' then
    pFeature:= sfIfExpr
  else if (LType = 'exprBinary') and IsIsNot(pNode) then
    pFeature:= sfIsNot
  else if (LType = 'exprBinary') and HasOperatorPair(pNode, 'kNot', 'kIn') then
    pFeature:= sfNotIn
  else if (LType = 'varDef') or (LType = 'varAssignDef') then
    pFeature:= sfInlineVar
  else if LType = 'constInline' then
    pFeature:= sfInlineConst
  else if LType = 'lambda' then
    pFeature:= sfAnonMethod
  else if (LType = 'literalString') and IsMultilineString(pNode, pSrc) then
    pFeature:= sfMultilineString
  else
    Result:= False;
end;

procedure CountTreeFeatures(const pRoot: TTSNode; const pSrc: TBytes;
  const pFeatures: TSyntaxFeatures; var pCounts: TSyntaxCounts; const pFilePath: string;
  var pHits: TArray<TSyntaxHit>; pWantHits: Boolean);
var
  LCursor: TTSTreeCursor;
  LNode: TTSNode;
  LFeature: TSyntaxFeature;
  LHit: TSyntaxHit;
begin
  if pRoot.IsNull then
    Exit;
  { Iterative pre-order walk: a recursion would follow the grammar's nesting
    depth, which a long expression chain makes arbitrarily deep. }
  LCursor:= TTSTreeCursor.Create(pRoot);
  try
    repeat
      LNode:= LCursor.CurrentNode;
      if LNode.IsNamed and ClassifyNode(LNode, pSrc, LFeature) and (LFeature in pFeatures) then
      begin
        Inc(pCounts[LFeature]);
        if pWantHits then
        begin
          LHit.Feature:= LFeature;
          LHit.FilePath:= pFilePath;
          LHit.Line:= Integer(LNode.StartPoint.row) + 1;
          LHit.Col:= Integer(LNode.StartPoint.column) + 1;
          pHits:= pHits + [LHit];
        end;
      end;
      if LCursor.GotoFirstChild then
        Continue;
      while not LCursor.GotoNextSibling do
        if (not LCursor.GotoParent) or (LCursor.CurrentDepth = 0) then
          Exit;
    until False;
  finally
    LCursor.Free;
  end;
end;

function CountSyntaxFeatures(const pFiles: TArray<string>; const pFeatures: TSyntaxFeatures;
  pWantHits: Boolean): TSyntaxCountReport;
var
  LFile: string;
  LParsed: TParsedFile;
  LCounts: TSyntaxCounts;
  LRow: TSyntaxFileCount;
  LAny: Boolean;
  F: TSyntaxFeature;
begin
  Result:= Default(TSyntaxCountReport);
  Result.Features:= pFeatures;
  for LFile in pFiles do
  begin
    TAstParseCache.Clear;
    LParsed:= TAstParseCache.Get(LFile);
    if LParsed.Tree = nil then
    begin
      Inc(Result.FilesUnreadable);
      Continue;
    end;
    Inc(Result.FilesScanned);
    if LParsed.Tree.RootNode.HasError then
      Inc(Result.FilesWithParseErrors);
    LCounts:= Default(TSyntaxCounts);
    CountTreeFeatures(LParsed.Tree.RootNode, LParsed.Src, pFeatures, LCounts, LFile,
      Result.Hits, pWantHits);
    LAny:= False;
    for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
    begin
      Inc(Result.Totals[F], LCounts[F]);
      LAny:= LAny or (LCounts[F] > 0);
    end;
    if LAny then
    begin
      LRow.FilePath:= LFile;
      LRow.Counts:= LCounts;
      Result.Files:= Result.Files + [LRow];
    end;
  end;
  TAstParseCache.Clear;
end;

function CountsToJson(const pCounts: TSyntaxCounts; const pFeatures: TSyntaxFeatures): TJSONObject;
var
  F: TSyntaxFeature;
begin
  Result:= TJSONObject.Create;
  for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
    if F in pFeatures then
      Result.AddPair(CFeatureNames[F], TJSONNumber.Create(pCounts[F]));
end;

function SyntaxCountToJson(const pReport: TSyntaxCountReport; pWithFiles, pWithHits: Boolean): TJSONObject;
var
  LArr: TJSONArray;
  LObj: TJSONObject;
  LRow: TSyntaxFileCount;
  LHit: TSyntaxHit;
  F: TSyntaxFeature;
begin
  Result:= TJSONObject.Create;
  LArr:= TJSONArray.Create;
  for F:= Low(TSyntaxFeature) to High(TSyntaxFeature) do
    if F in pReport.Features then
      LArr.Add(CFeatureNames[F]);
  Result.AddPair('features', LArr);
  Result.AddPair('files_scanned', TJSONNumber.Create(pReport.FilesScanned));
  Result.AddPair('files_unreadable', TJSONNumber.Create(pReport.FilesUnreadable));
  Result.AddPair('files_with_parse_errors', TJSONNumber.Create(pReport.FilesWithParseErrors));
  Result.AddPair('totals', CountsToJson(pReport.Totals, pReport.Features));
  if pWithFiles then
  begin
    LArr:= TJSONArray.Create;
    for LRow in pReport.Files do
    begin
      LObj:= TJSONObject.Create;
      LObj.AddPair('path', LRow.FilePath);
      LObj.AddPair('counts', CountsToJson(LRow.Counts, pReport.Features));
      LArr.AddElement(LObj);
    end;
    Result.AddPair('files', LArr);
  end;
  if pWithHits then
  begin
    LArr:= TJSONArray.Create;
    for LHit in pReport.Hits do
    begin
      LObj:= TJSONObject.Create;
      LObj.AddPair('feature', CFeatureNames[LHit.Feature]);
      LObj.AddPair('path', LHit.FilePath);
      LObj.AddPair('line', TJSONNumber.Create(LHit.Line));
      LObj.AddPair('col', TJSONNumber.Create(LHit.Col));
      LArr.AddElement(LObj);
    end;
    Result.AddPair('hits', LArr);
  end;
end;

function RunSyntaxCountVerb(const pArgs: TArray<string>): Integer;
begin
  Result:= 2;
end;

end.