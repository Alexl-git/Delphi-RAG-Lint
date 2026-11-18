unit DragLint.Plugin.SearchParse;

{ Pure (ToolsAPI/VCL-free) parsers turning drag-lint --json output into a
  uniform row model for the Search tab grid. Unit-tested by
  tests\searchparse\SearchParseTests.dpr. }

interface

uses
  System.SysUtils;

type
  /// <summary>One grid row. FilePath/Line drive navigation; Line=0 = not
  /// navigable (e.g. an Impact summary).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.SearchParse.pas), DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas), DragLint.Plugin.SearchParse.MakeRow (DragLint.Plugin.SearchParse.pas), DragLint.Plugin.SearchParse.ParseNameJson (DragLint.Plugin.SearchParse.pas), DragLint.Plugin.SearchParse.ParseTextJson (DragLint.Plugin.SearchParse.pas) (+1 more)</para>
  /// <para>Used in units: DragLint.Plugin.SearchForm, DragLint.Plugin.SearchParse</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSearchRow = record
    Category: string ;
    ColA    : string ;
    ColB    : string ;
    FilePath: string ;
    Line    : Integer;
  end;
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.SearchForm.pas), declaration (DragLint.Plugin.SearchParse.pas), DragLint.Plugin.SearchForm.TSearchHandler.Fill (DragLint.Plugin.SearchForm.pas), DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas), DragLint.Plugin.SearchParse.ParseNameJson (DragLint.Plugin.SearchParse.pas) (+2 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSearchRows = TArray<TSearchRow>;

/// <summary>Rows from `query --name --json` (array of symbol objects).</summary>
/// <param name="AJson"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->TSearchRows</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas)</para>
/// <para>Calls: DragLint.Plugin.SearchParse.MakeRow, TJSONArray, TJSONObject</para>
/// <seealso cref="DragLint.Plugin.SearchParse.MakeRow"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseNameJson(const AJson: string): TSearchRows;
/// <summary>Rows from `query --text --json` (array of literal-match objects).</summary>
/// <param name="AJson"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->TSearchRows</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas)</para>
/// <para>Calls: DragLint.Plugin.SearchParse.MakeRow, TJSONArray, TJSONObject</para>
/// <seealso cref="DragLint.Plugin.SearchParse.MakeRow"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseTextJson(const AJson: string): TSearchRows;
/// <summary>Rows from `usages --format json` (grouped object), flattened.</summary>
/// <param name="AJson"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->TSearchRows</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas)</para>
/// <para>Calls: DragLint.Plugin.SearchParse.ParseUsagesJson.AddGroup, DragLint.Plugin.SearchParse.ParseUsagesJson.AddImpact, ExtractFileName, Format, MakeRow, TJSONObject</para>
/// <seealso cref="DragLint.Plugin.SearchParse.ParseUsagesJson.AddGroup"/>
/// <seealso cref="DragLint.Plugin.SearchParse.ParseUsagesJson.AddImpact"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseUsagesJson(const AJson: string): TSearchRows;
/// <summary>True if a drag-lint symbol kind belongs to the UI kind filter
/// (''/'Any' match all).</summary>
/// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
/// <param name="AFilter"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SearchForm.TSearchHandler.ShowResult (DragLint.Plugin.SearchForm.pas)</para>
/// <para>Calls: DragLint.Plugin.SearchParse.KindMatchesFilter.In_, SameText</para>
/// <seealso cref="DragLint.Plugin.SearchParse.KindMatchesFilter.In_"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function KindMatchesFilter(const AKind, AFilter: string): Boolean;

const
  /// <summary>The engine's `usages --scope` words, in the order of the Search
  /// page's scope combo (the same four as the Find Usages panel).</summary>
  SEARCH_SCOPE_WORDS: array[0..3] of string = ('symbol', 'project', 'group', 'everywhere');
  /// <summary>Combo index the Search page starts on: Project, which is what a bare
  /// name answers anyway (no caret position binds a symbol).</summary>
  SEARCH_SCOPE_DEFAULT = 1;

/// <summary>The scope word of a scope-combo index.</summary>
/// <param name="AIndex">Combo ItemIndex; anything outside 0..3 (e.g. -1) is the default.</param>
/// <returns>symbol, project, group or everywhere.</returns>
function SearchScopeWord(AIndex: Integer): string;  // dl:ok unused-public-symbol@b38a -- public as the test seam: SearchParseTests pins the index -> word mapping
/// <summary>The scope part of a `usages` command line for the Search page.</summary>
/// <param name="AIndex">Combo ItemIndex.</param>
/// <param name="AGroupFile">Open project group file; used only for scope group.</param>
/// <returns>' --scope &lt;word&gt;', plus ' --group "&lt;file&gt;"' for group when a file is known.</returns>
function SearchUsagesScopeArgs(AIndex: Integer; const AGroupFile: string): string;
/// <summary>The Location column text of a row.</summary>
/// <param name="AFilePath">Full path of the row's file.</param>
/// <param name="ALine">1-based line; 0 = not navigable.</param>
/// <returns>'full\path.pas:123', or '' when ALine &lt;= 0.</returns>
function SearchLocationText(const AFilePath: string; ALine: Integer): string;
/// <summary>The engine's scope_note of a `usages --format json` answer.</summary>
/// <param name="AJson">The raw answer.</param>
/// <returns>The note, or '' when absent or not JSON.</returns>
function ParseUsagesScopeNote(const AJson: string): string;
implementation

uses
  System.JSON, System.Generics.Collections;

function SearchScopeWord(AIndex: Integer): string;
begin
  if (AIndex < Low(SEARCH_SCOPE_WORDS)) or (AIndex > High(SEARCH_SCOPE_WORDS)) then AIndex:= SEARCH_SCOPE_DEFAULT;
  Result:= SEARCH_SCOPE_WORDS[AIndex];
end;

function SearchUsagesScopeArgs(AIndex: Integer; const AGroupFile: string): string;
begin
  Result:= ' --scope ' + SearchScopeWord(AIndex);
  if (SearchScopeWord(AIndex) = 'group') and (AGroupFile <> '') then
    Result:= Result + Format(' --group "%s"', [AGroupFile]);
end;

function SearchLocationText(const AFilePath: string; ALine: Integer): string;
begin
  Result:= if ALine > 0 then Format('%s:%d', [AFilePath, ALine]) else '';
end;

function ParseUsagesScopeNote(const AJson: string): string;
var
  Root: TJSONValue;
begin
  Result:= '';
  Root:= TJSONObject.ParseJSONValue(AJson);
  try
    if Root is TJSONObject then TJSONObject(Root).TryGetValue<string>('scope_note', Result);
  finally
    Root.Free;
  end;
end;

function MakeRow(const ACat, AColA, AColB, AFile: string; ALine: Integer): TSearchRow;
begin
  Result.Category:= ACat; Result.ColA:= AColA; Result.ColB:= AColB;
  Result.FilePath:= AFile; Result.Line:= ALine;
end;

function ParseNameJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Arr: TJSONArray; i: Integer; O: TJSONObject;
  Nm, Kd, F: string; Ln: Integer; List: TList<TSearchRow>;
begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Arr:= TJSONArray(Root);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Nm:= ''; Kd:= ''; F:= ''; Ln:= 0;
      O.TryGetValue<string>('name', Nm);
      O.TryGetValue<string>('kind', Kd);
      O.TryGetValue<string>('file', F);
      O.TryGetValue<Integer>('start_line', Ln);
      List.Add(MakeRow('Symbol', Nm, Kd, F, Ln));
    end;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function ParseTextJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Arr: TJSONArray; i: Integer; O: TJSONObject;
  Tx, Sr, F: string; Ln: Integer; List: TList<TSearchRow>;
begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Arr:= TJSONArray(Root);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Tx:= ''; Sr:= ''; F:= ''; Ln:= 0;
      O.TryGetValue<string>('text', Tx);
      O.TryGetValue<string>('source', Sr);
      O.TryGetValue<string>('file_path', F);
      O.TryGetValue<Integer>('start_line', Ln);
      List.Add(MakeRow('Text', Tx, Sr, F, Ln));
    end;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function ParseUsagesJson(const AJson: string): TSearchRows;
var
  Root: TJSONValue; Obj: TJSONObject; List: TList<TSearchRow>;

  procedure AddGroup(const AKey, ACat: string);
  var Arr: TJSONArray; i: Integer; O: TJSONObject; F, QN: string; Ln: Integer;
  begin
    if not Obj.TryGetValue<TJSONArray>(AKey, Arr) then Exit;
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      F:= ''; QN:= ''; Ln:= 0;
      O.TryGetValue<string>('file', F);
      O.TryGetValue<string>('qname', QN);
      O.TryGetValue<Integer>('line', Ln);
      if QN <> '' then List.Add(MakeRow(ACat, QN, ExtractFileName(F), F, Ln))
      else List.Add(MakeRow(ACat, ExtractFileName(F), '', F, Ln));
    end;
  end;

  procedure AddImpact;
  var Arr: TJSONArray; i: Integer; O: TJSONObject; Dp, Ca, Un: Integer;
  begin
    if not Obj.TryGetValue<TJSONArray>('impact', Arr) then Exit;
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      O:= TJSONObject(Arr.Items[i]);
      Dp:= 0; Ca:= 0; Un:= 0;
      O.TryGetValue<Integer>('depth', Dp);
      O.TryGetValue<Integer>('callers', Ca);
      O.TryGetValue<Integer>('units', Un);
      List.Add(MakeRow('Impact', Format('depth %d: %d callers across %d units', [Dp, Ca, Un]), '', '', 0));
    end;
  end;

begin
  SetLength(Result, 0);
  Root:= TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONObject) then begin Root.Free; Exit; end;
  List:= TList<TSearchRow>.Create;
  try
    Obj:= TJSONObject(Root);
    AddGroup('declarations', 'Decl' );
    AddGroup('reads'       , 'Read' );
    AddGroup('writes'      , 'Write');
    AddGroup('calls'       , 'Call' );
    AddGroup('types'       , 'Type' );
    AddGroup('attributes'  , 'Attr' );
    AddGroup('events'      , 'Event');
    AddImpact;
    Result:= List.ToArray;
  finally
    List.Free; Root.Free;
  end;
end;

function KindMatchesFilter(const AKind, AFilter: string): Boolean;
  function In_(const A: array of string): Boolean;
  var s: string;
  begin
    Result:= False;
    for s in A do if SameText(AKind, s) then Exit(True);
  end;
begin
  if (AFilter = '') or SameText(AFilter, 'Any') then Exit(True);
  if SameText(AFilter, 'Method')     then Exit(In_(['method','function','procedure','constructor','destructor']));
  if SameText(AFilter, 'Type/Class') then Exit(In_(['class','record','interface','enum','type']));
  if SameText(AFilter, 'Field/Var')  then Exit(In_(['field','var']));
  if SameText(AFilter, 'Const')      then Exit(In_(['const']));
  if SameText(AFilter, 'Property')   then Exit(In_(['property']));
  if SameText(AFilter, 'Unit')       then Exit(In_(['unit','program','package']));
  Result:= True;
end;

end.
