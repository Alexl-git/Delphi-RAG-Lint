unit DRagLint.V156.OOA2.Support;

{ Wave v156 lane OOA-2 -- helpers of DRagLint.V156.OOA2 (private to the lane); both rules read the project index only.
    abstract-method-not-overridden -- a class nothing derives from that leaves an inherited abstract method open (G-16)
    handler-type-never-raised      -- `on EType do` where no code raises or builds EType or a descendant (G-22)
  A question the index does not answer completely (ancestor not indexed, overloaded name, abstract class,
  dl:shared unit) is answered "no finding". }

interface

uses
  System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  RULE_ABSTRACT_NOT_OVERRIDDEN = 'abstract-method-not-overridden';
  RULE_HANDLER_NEVER_RAISED = 'handler-type-never-raised';

/// <summary>Classes of the file that leave an abstract method of an indexed ancestor open (G-16).</summary>
/// <param name="ACtx">The file; needs its Store and FileId, else nothing is reported.</param>
/// <returns>One finding per such class, at its declaration; nil when none.</returns>
/// <remarks>Only a class nothing derives from, not `class abstract`, not in a `dl:shared` unit. The walk follows the
/// first (class) ancestor of each class while it is indexed; for each method name the nearest declaration decides, and an
/// overloaded name never counts as open. A static-method hide is treated as an override (conservative).</remarks>
function CheckAbstractNotOverridden(const ACtx: TV151FileCtx): TArray<TLintFinding>;

/// <summary>Exception handlers of the file whose type is a project class nothing raises or builds (G-22).</summary>
/// <param name="ACtx">The file; needs its Store and FileId, else nothing is reported.</param>
/// <returns>One finding per handler, at the handled type; nil when none.</returns>
/// <remarks>A type counts as used when the index holds, for it or any descendant, a reference that is neither a
/// handler, the handler's own type mention, nor a descendant's declaration (so raise, constructor call, factory,
/// variable, cast and class-reference mentions all count). A type declared in a `dl:shared` unit is never reported.</remarks>
function CheckHandlerNeverRaised(const ACtx: TV151FileCtx): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , DRagLint.Core.Interfaces
  , DRagLint.Storage.SQLite
  ;

const
  MAX_CHAIN = 64;
  MAX_NAMES_SHOWN = 3;
  SHARED_MARKER = 'dl:shared';

type
  /// <summary>What the nearest declaration of one method name says while walking up the chain.</summary>
  TOpenState = (osOpen, osClosed);

function NewQuery(const AStore: ISymbolStore; const ASql: string): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  Result.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
  Result.SQL.Text  := ASql;
end;

function ReadSource(const APath: string): string;
begin
  Result:= '';
  if (APath <> '') and TFile.Exists(APath) then
    Result:= TEncoding.UTF8.GetString(TFile.ReadAllBytes(APath));
end;

{ True when the unit text carries a dl:shared marker: other projects may raise or derive from its types. }
function IsSharedText(const AText: string): Boolean;
begin
  Result:= ContainsText(AText, SHARED_MARKER);
end;

function NewFinding(const ACtx: TV151FileCtx; const ARule, AMessage: string; ALine, ACol, AEndLine, AEndCol: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := 'warning';
  Result.Message  := AMessage;
  Result.FilePath := ACtx.Path;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := AEndLine;
  Result.EndCol   := AEndCol;
end;

{ `class abstract` is not in the index: the declaration lines say it. }
function DeclaredAbstract(const ALines: TArray<string>; ALine: Integer): Boolean;
const
  LOOK_AHEAD = 2;
var
  I: Integer;
  Text: string;
begin
  Text:= '';
  for I:= ALine - 1 to ALine - 1 + LOOK_AHEAD do
    if (I >= 0) and (I < Length(ALines)) then Text:= Text + ' ' + ALines[I];
  Result:= TRegEx.IsMatch(Text, '\bclass\s+(abstract|sealed\s+abstract)\b', [roIgnoreCase]);
end;

{ The indexed class ancestor of a class, or 0. }
function ClassAncestor(const AStore: ISymbolStore; AClassId: Int64): Int64;
var
  Query: TFDQuery;
begin
  Result:= 0;
  Query:= NewQuery(AStore, 'SELECT ancestor_symbol_id FROM type_ancestors WHERE symbol_id = :s AND ordinal = 0 ' +
    'AND ancestor_kind = ''class'' AND ancestor_symbol_id IS NOT NULL');
  try
    Query.ParamByName('s').AsLargeInt:= AClassId;
    Query.Open;
    if not Query.Eof then Result:= Query.Fields[0].AsLargeInt;
  finally
    Query.Free;
  end;
end;

{ Records, per method name of one class, whether an override / body closes it; nil-safe on an already decided name. }
procedure ScanClass(const AStore: ISymbolStore; AClassId: Int64; const AClassName: string;
  const AStates: TDictionary<string, TOpenState>; const AOpenOwner: TDictionary<string, string>);
var
  Query: TFDQuery;
  Names: TDictionary<string, TOpenState>;
  Pair: TPair<string, TOpenState>;
  Key, Dir: string;
begin
  Names:= TDictionary<string, TOpenState>.Create;
  Query:= nil;
  try
    Query:= NewQuery(AStore, 'SELECT name, COALESCE(directives, '''') FROM symbols WHERE parent_id = :p AND kind = ''method''');
    Query.ParamByName('p').AsLargeInt:= AClassId;
    Query.Open;
    while not Query.Eof do
    begin
      Key:= LowerCase(Query.Fields[0].AsString);
      Dir:= ' ' + LowerCase(Query.Fields[1].AsString) + ' ';
      if ContainsStr(Dir, ' overload ') then
        Names.AddOrSetValue(Key, osClosed)
      else if ContainsStr(Dir, ' abstract ') and (not ContainsStr(Dir, ' override ')) then
      begin
        if not Names.ContainsKey(Key) then Names.Add(Key, osOpen);
      end
      else
        Names.AddOrSetValue(Key, osClosed);
      Query.Next;
    end;
    for Pair in Names do
      if not AStates.ContainsKey(Pair.Key) then
      begin
        AStates.Add(Pair.Key, Pair.Value);
        if Pair.Value = osOpen then AOpenOwner.AddOrSetValue(Pair.Key, AClassName);
      end;
  finally
    Query.Free;
    Names.Free;
  end;
end;

type
  /// <summary>One candidate row read from the index: a class or a handler position.</summary>
  TSpot = record
    Id: Int64;
    Name: string;
    Line, Col, EndLine, EndCol: Integer;
  end;

function ReadSpots(const AStore: ISymbolStore; const ASql: string; AFileId: Int64): TArray<TSpot>;
var
  Query: TFDQuery;
  List: TList<TSpot>;
  Spot: TSpot;
begin
  List:= TList<TSpot>.Create;
  Query:= NewQuery(AStore, ASql);
  try
    Query.ParamByName('f').AsLargeInt:= AFileId;
    Query.Open;
    while not Query.Eof do
    begin
      Spot.Id     := Query.Fields[0].AsLargeInt;
      Spot.Name   := Query.Fields[1].AsString;
      Spot.Line   := Query.Fields[2].AsInteger;
      Spot.Col    := Query.Fields[3].AsInteger;
      Spot.EndLine:= Query.Fields[4].AsInteger;
      Spot.EndCol := Query.Fields[5].AsInteger;
      List.Add(Spot);
      Query.Next;
    end;
    Result:= List.ToArray;
  finally
    Query.Free;
    List.Free;
  end;
end;

{ The abstract method names a class leaves open, with the class that declared each; empty when none. }
function OpenMethods(const AStore: ISymbolStore; AClassId: Int64): TArray<string>;
var
  States: TDictionary<string, TOpenState>;
  Owners: TDictionary<string, string>;
  Names: TList<string>;
  Current: Int64;
  Depth: Integer;
  Pair: TPair<string, string>;
begin
  States:= TDictionary<string, TOpenState>.Create;
  Owners:= TDictionary<string, string>.Create;
  Names := TList<string>.Create;
  try
    Current:= AClassId;
    Depth  := 0;
    while (Current <> 0) and (Depth < MAX_CHAIN) do
    begin
      ScanClass(AStore, Current, '', States, Owners);
      Current:= ClassAncestor(AStore, Current);
      Inc(Depth);
    end;
    for Pair in Owners do Names.Add(Pair.Key);
    Names.Sort;
    Result:= Names.ToArray;
  finally
    Names.Free;
    Owners.Free;
    States.Free;
  end;
end;

function CheckAbstractNotOverridden(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Found: TList<TLintFinding>;
  Lines: TArray<string>;
  Text, Shown: string;
  Spot: TSpot;
  Open: TArray<string>;
begin
  Result:= nil;
  if (ACtx.Store = nil) or (ACtx.FileId = 0) then Exit;
  Text:= ReadSource(ACtx.Path);
  if (Text = '') or IsSharedText(Text) then Exit;
  Lines:= Text.Split([#10]);
  Found:= TList<TLintFinding>.Create;
  try
    for Spot in ReadSpots(ACtx.Store, 'SELECT c.id, c.name, c.start_line, c.start_col, c.end_line, c.end_col FROM symbols c ' +
        'WHERE c.file_id = :f AND c.kind = ''class'' AND NOT EXISTS (SELECT 1 FROM type_ancestors t WHERE t.ancestor_symbol_id = c.id) ' +
        'ORDER BY c.start_line', ACtx.FileId) do
    begin
      if DeclaredAbstract(Lines, Spot.Line) then Continue;
      Open:= OpenMethods(ACtx.Store, Spot.Id);
      if Length(Open) = 0 then Continue;
      Shown:= string.Join(', ', Copy(Open, 0, MAX_NAMES_SHOWN)) + IfThen(Length(Open) > MAX_NAMES_SHOWN, ', ...', '');
      Found.Add(NewFinding(ACtx, RULE_ABSTRACT_NOT_OVERRIDDEN,
        Format('Class %s leaves abstract method(s) of an ancestor open: %s; creating it raises EAbstractError', [Spot.Name, Shown]),
        Spot.Line, Spot.Col, Spot.EndLine, Spot.EndCol));
    end;
    if Found.Count > 0 then Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

{ True when the type, or a class derived from it, is referred to in a way that can raise or build it. }
function TypeIsUsed(const AStore: ISymbolStore; ATypeId: Int64): Boolean;
var
  Query: TFDQuery;
begin
  Query:= NewQuery(AStore, 'WITH RECURSIVE d(id) AS (SELECT :t UNION SELECT a.symbol_id FROM type_ancestors a JOIN d ON a.ancestor_symbol_id = d.id) ' +
    'SELECT COUNT(*) FROM refs r WHERE r.symbol_id IN (SELECT id FROM d) AND r.kind <> ''handle'' AND (r.kind <> ''type_use'' ' +
    'OR (NOT EXISTS (SELECT 1 FROM refs h WHERE h.kind = ''handle'' AND h.file_id = r.file_id AND h.start_line = r.start_line AND h.symbol_id = r.symbol_id) ' +
    'AND NOT EXISTS (SELECT 1 FROM symbols c JOIN type_ancestors a ON a.symbol_id = c.id WHERE c.file_id = r.file_id AND c.start_line = r.start_line AND a.ancestor_symbol_id = r.symbol_id)))');
  try
    Query.ParamByName('t').AsLargeInt:= ATypeId;
    Query.Open;
    Result:= Query.Fields[0].AsInteger > 0;
  finally
    Query.Free;
  end;
end;

{ The text of the file that declares a symbol; '' when unknown. }
function DeclaringSource(const AStore: ISymbolStore; ASymbolId: Int64): string;
var
  Query: TFDQuery;
begin
  Result:= '';
  Query:= NewQuery(AStore, 'SELECT f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id = :s');
  try
    Query.ParamByName('s').AsLargeInt:= ASymbolId;
    Query.Open;
    if not Query.Eof then Result:= ReadSource(Query.Fields[0].AsString);
  finally
    Query.Free;
  end;
end;

function CheckHandlerNeverRaised(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Found: TList<TLintFinding>;
  Spot: TSpot;
  Source: string;
begin
  Result:= nil;
  if (ACtx.Store = nil) or (ACtx.FileId = 0) then Exit;
  Found:= TList<TLintFinding>.Create;
  try
    for Spot in ReadSpots(ACtx.Store, 'SELECT s.id, s.name, r.start_line, r.start_col, r.end_line, r.end_col FROM refs r ' +
        'JOIN symbols s ON s.id = r.symbol_id WHERE r.file_id = :f AND r.kind = ''handle'' AND s.kind = ''class'' ORDER BY r.start_line, r.start_col', ACtx.FileId) do
    begin
      if TypeIsUsed(ACtx.Store, Spot.Id) then Continue;
      Source:= DeclaringSource(ACtx.Store, Spot.Id);
      if (Source = '') or IsSharedText(Source) then Continue;
      Found.Add(NewFinding(ACtx, RULE_HANDLER_NEVER_RAISED,
        Format('No code in the project raises or builds %s or a class derived from it: this handler never runs', [Spot.Name]),
        Spot.Line, Spot.Col, Spot.EndLine, Spot.EndCol));
    end;
    if Found.Count > 0 then Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

end.