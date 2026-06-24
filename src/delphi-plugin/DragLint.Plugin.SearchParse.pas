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
  TSearchRow = record
    Category: string ;
    ColA    : string ;
    ColB    : string ;
    FilePath: string ;
    Line    : Integer;
  end;
  TSearchRows = TArray<TSearchRow>;

/// <summary>Rows from `query --name --json` (array of symbol objects).</summary>
function ParseNameJson(const AJson: string): TSearchRows;
/// <summary>Rows from `query --text --json` (array of literal-match objects).</summary>
function ParseTextJson(const AJson: string): TSearchRows;
/// <summary>Rows from `usages --format json` (grouped object), flattened.</summary>
function ParseUsagesJson(const AJson: string): TSearchRows;
/// <summary>True if a drag-lint symbol kind belongs to the UI kind filter
/// (''/'Any' match all).</summary>
function KindMatchesFilter(const AKind, AFilter: string): Boolean;

implementation

uses
  System.JSON, System.Generics.Collections;

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
