unit FeatureGen.Json;

{ Canonical JSON for the feature registry: reads JSON files and writes them
  byte-for-byte like tools\FeatureRegistry.psm1 (ConvertTo-CanonicalJson /
  ConvertTo-CanonicalEntry): 2-space indent, CRLF, trailing CRLF, scalar-only
  arrays inline, key order from entry.schema.json. 7-bit ASCII only. }

interface

uses
  System.SysUtils
  , System.JSON
  ;

type
  /// <summary>Raised for unreadable JSON and for non-ASCII text in a value being written.</summary>
  EFeatureJson = class(Exception);

/// <summary>Reads and parses one JSON file (UTF-8).</summary>
/// <param name="pPath">Full path of the file.</param>
/// <returns>The parsed value. The caller owns it and must Free it.</returns>
/// <exception cref="EFeatureJson">The file is missing or is not valid JSON.</exception>
function ReadJsonFile(const pPath: string): TJSONValue;

/// <summary>Reads the canonical top-level entry key order: the order of "properties" in entry.schema.json.</summary>
/// <param name="pSchemaPath">Full path of entry.schema.json.</param>
/// <returns>Property names in schema file order.</returns>
/// <exception cref="EFeatureJson">The schema is unreadable or has no properties object.</exception>
function EntryKeyOrder(const pSchemaPath: string): TArray<string>;

/// <summary>Renders a value exactly as the PowerShell canonical writer does.</summary>
/// <param name="pValue">Value to render; not modified.</param>
/// <param name="pKeyOrder">Non-empty: pValue is a registry entry - top-level keys follow this order then ordinal, empty values are dropped (surfaces stays, as []), related/aliases are sorted unique, surface/example/lastVerified/flag/question/verified keys use their fixed orders. Empty: generic mode, objects keep document order and nothing is dropped.</param>
/// <returns>The text, CRLF line ends, ending in CRLF.</returns>
/// <remarks>Raises EFeatureJson: A string holds a character above 127.</remarks>
function CanonicalJson(const pValue: TJSONValue; const pKeyOrder: TArray<string>): string;

/// <summary>Reads one member of an object as text.</summary>
/// <param name="pObj">Object to read; nil or a non-object reads as absent.</param>
/// <param name="pName">Member name (ordinal match).</param>
/// <returns>The string value; numbers and booleans as their JSON text; '' when absent, null or an array/object.</returns>
function Prop(const pObj: TJSONValue; const pName: string): string;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

type
  TCtx = (cxPlain, cxEntry, cxSurface, cxExample, cxLastVerified, cxFlag, cxQuestion, cxVerified);

function ReadJsonFile(const pPath: string): TJSONValue;
begin
  if not TFile.Exists(pPath) then
    raise EFeatureJson.CreateFmt('JSON file not found: %s', [pPath]);
  Result := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(TFile.ReadAllBytes(pPath)), True, False);
  if Result = nil then
    raise EFeatureJson.CreateFmt('Not valid JSON: %s', [pPath]);
end;

function EntryKeyOrder(const pSchemaPath: string): TArray<string>;
var
  lRoot: TJSONValue;
  lProps: TJSONValue;
  i: Integer;
begin
  lRoot := ReadJsonFile(pSchemaPath);
  try
    if lRoot is TJSONObject then
      lProps := TJSONObject(lRoot).GetValue('properties')
    else
      lProps := nil;
    if lProps is not TJSONObject then
      raise EFeatureJson.CreateFmt('No "properties" object in %s', [pSchemaPath]);
    SetLength(Result, TJSONObject(lProps).Count);
    for i := 0 to TJSONObject(lProps).Count - 1 do
      Result[i] := TJSONObject(lProps).Pairs[i].JsonString.Value;
  finally
    lRoot.Free;
  end;
end;

function Prop(const pObj: TJSONValue; const pName: string): string;
var
  lV: TJSONValue;
begin
  Result := '';
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue(pName);
  if lV = nil then
    Exit;
  if lV is TJSONString then
    Result := TJSONString(lV).Value
  else if (lV is TJSONNumber) or (lV is TJSONBool) then
    Result := lV.ToString;
end;

function SurfaceOrder(const pType: string): TArray<string>;  // dl:ok cognitive-complexity@b9fa -- REVIEWED 2026-10-19: one routine per ported check or command, kept 1:1 with the PowerShell original so the golden parity tests compare like with like
begin
  if pType = 'cli' then
    Result := ['type', 'verb', 'sub', 'example', 'usage', 'flags', 'helpOrder', 'help']
  else if pType = 'ide-menu' then
    Result := ['type', 'path', 'steps']
  else if pType = 'ide-context' then
    Result := ['type', 'host', 'caption', 'steps']
  else if pType = 'ide-about' then
    Result := ['type', 'caption', 'steps']
  else if pType = 'tool-window' then
    Result := ['type', 'path', 'steps']
  else if pType = 'shortcut' then
    Result := ['type', 'keys']
  else if pType = 'lsp' then
    Result := ['type', 'method']
  else if pType = 'mcp' then
    Result := ['type', 'tool']
  else if pType = 'script' then
    Result := ['type', 'path', 'args']
  else if pType = 'exe' then
    Result := ['type', 'name', 'menu']
  else if pType = 'workflow' then
    Result := ['type', 'doc']
  else
    Result := ['type'];
end;

procedure SortOrdinal(var pItems: TArray<string>);
begin
  TArray.Sort<string>(pItems, TStringComparer.Ordinal);
end;

procedure AppendString(pSb: TStringBuilder; const pS: string);
var
  lCh: Char;
begin
  pSb.Append('"');
  for lCh in pS do
  begin
    if lCh = '"' then
      pSb.Append('\"')
    else if lCh = '\' then
      pSb.Append('\\')
    else if lCh = #10 then
      pSb.Append('\n')
    else if lCh = #13 then
      pSb.Append('\r')
    else if lCh = #9 then
      pSb.Append('\t')
    else if Ord(lCh) > 127 then  // dl:ok large-magic-number@14c9, magic-literal@14c9 -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
      raise EFeatureJson.CreateFmt('non-ASCII character U+%.4X in string: %s', [Ord(lCh), pS])
    else if Ord(lCh) < 32 then  // dl:ok magic-literal@e29e -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
      pSb.Append('\u' + LowerCase(IntToHex(Ord(lCh), 4)))  // dl:ok magic-literal@fb40 -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
    else
      pSb.Append(lCh);
  end;
  pSb.Append('"');
end;

function IsComplex(pV: TJSONValue): Boolean;
begin
  Result := (pV is TJSONObject) or (pV is TJSONArray);
end;

function IsEmptyValue(pV: TJSONValue): Boolean;
begin
  Result := (pV = nil) or (pV is TJSONNull)  // dl:ok boolean-expression-complexity@0115 -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
    or ((pV is TJSONString) and (TJSONString(pV).Value = ''))
    or ((pV is TJSONArray) and (TJSONArray(pV).Count = 0));
end;

procedure AppendValue(pSb: TStringBuilder; pV: TJSONValue; pLevel: Integer; pCtx: TCtx;
  const pKeyOrder: TArray<string>); forward;

procedure AppendArray(pSb: TStringBuilder; const pItems: TArray<TJSONValue>; pLevel: Integer; pItemCtx: TCtx);
var
  lPad: string;
  lComplex: Boolean;
  i: Integer;
begin
  lPad := StringOfChar(' ', 2 * pLevel);
  if Length(pItems) = 0 then
  begin
    pSb.Append('[]');
    Exit;
  end;
  lComplex := False;
  for i := 0 to High(pItems) do
    if IsComplex(pItems[i]) then
      lComplex := True;
  if not lComplex then
  begin
    pSb.Append('[');
    for i := 0 to High(pItems) do
    begin
      if i > 0 then
        pSb.Append(', ');
      AppendValue(pSb, pItems[i], pLevel, cxPlain, nil);
    end;
    pSb.Append(']');
    Exit;
  end;
  pSb.Append('[').Append(#13#10);
  for i := 0 to High(pItems) do
  begin
    pSb.Append(lPad).Append('  ');
    AppendValue(pSb, pItems[i], pLevel + 1, pItemCtx, nil);
    if i < High(pItems) then
      pSb.Append(',');
    pSb.Append(#13#10);
  end;
  pSb.Append(lPad).Append(']');
end;

function ArrayItems(pArr: TJSONArray): TArray<TJSONValue>;
var
  i: Integer;
begin
  SetLength(Result, pArr.Count);
  for i := 0 to pArr.Count - 1 do
    Result[i] := pArr.Items[i];
end;

{ Sorted ordinal, duplicates removed - Sort-OrdinalUnique. The strings live in pOwner. }
function SortedUniqueStrings(pArr: TJSONArray; pOwner: TObjectList<TJSONString>): TArray<TJSONValue>;
var
  lSet: TList<string>;
  lAll: TArray<string>;
  i: Integer;
  lS: TJSONString;
begin
  lSet := TList<string>.Create;
  try
    for i := 0 to pArr.Count - 1 do
      if not lSet.Contains(pArr.Items[i].Value) then
        lSet.Add(pArr.Items[i].Value);
    lAll := lSet.ToArray;
  finally
    lSet.Free;
  end;
  SortOrdinal(lAll);
  SetLength(Result, Length(lAll));
  for i := 0 to High(lAll) do
  begin
    lS := TJSONString.Create(lAll[i]);
    pOwner.Add(lS);
    Result[i] := lS;
  end;
end;

procedure AppendObject(pSb: TStringBuilder; pObj: TJSONObject; pLevel: Integer; pCtx: TCtx;  // dl:ok cyclomatic-complexity@ea70 -- REVIEWED 2026-10-19: one routine per ported check or command, kept 1:1 with the PowerShell original so the golden parity tests compare like with like
  const pKeyOrder: TArray<string>);
var
  lPad, lName, lType: string;
  lByName: TDictionary<string, TJSONValue>;
  lNames, lRest, lOrder: TArray<string>;
  lKeys: TList<string>;
  lOwner: TObjectList<TJSONString>;
  lEmptyArr: TJSONArray;
  lV: TJSONValue;
  i: Integer;
  lItemCtx: TCtx;
begin
  lPad := StringOfChar(' ', 2 * pLevel);
  lByName := TDictionary<string, TJSONValue>.Create(TStringComparer.Ordinal);
  lKeys := TList<string>.Create;
  lOwner := TObjectList<TJSONString>.Create(True);
  lEmptyArr := TJSONArray.Create;
  try
    SetLength(lNames, pObj.Count);
    for i := 0 to pObj.Count - 1 do
    begin
      lNames[i] := pObj.Pairs[i].JsonString.Value;
      lByName.AddOrSetValue(lNames[i], pObj.Pairs[i].JsonValue);
    end;
    case pCtx of
      cxEntry: lOrder := pKeyOrder;
      cxSurface:
        begin
          lType := Prop(pObj, 'type');
          lOrder := SurfaceOrder(lType);
        end;
      cxExample: lOrder := ['kind', 'text', 'path', 'note'];
      cxLastVerified: lOrder := ['date', 'by', 'build'];
      cxFlag: lOrder := ['name', 'arg', 'summary', 'default'];
      cxQuestion: lOrder := ['ask', 'command'];
      cxVerified: lOrder := ['date', 'by', 'build', 'surfaceHash'];
    else
      lOrder := nil;
    end;
    // ordered keys first (when present), then the rest: ordinal for entry mode and
    // nested fixed-order objects, document order for plain objects.
    for lName in lOrder do
      if lByName.ContainsKey(lName) and not lKeys.Contains(lName) then
        lKeys.Add(lName);
    SetLength(lRest, 0);
    for lName in lNames do
      if not lKeys.Contains(lName) then
      begin
        SetLength(lRest, Length(lRest) + 1);
        lRest[High(lRest)] := lName;
      end;
    if pCtx <> cxPlain then
      SortOrdinal(lRest);
    for lName in lRest do
      lKeys.Add(lName);
    if (pCtx = cxEntry) and not lKeys.Contains('surfaces') then
      lKeys.Add('surfaces');
    // entry mode drops empty values (surfaces excepted); nested ordered objects drop nulls
    for i := lKeys.Count - 1 downto 0 do
      if lByName.TryGetValue(lKeys[i], lV) then
      begin
        if (pCtx = cxEntry) and (lKeys[i] <> 'surfaces') and IsEmptyValue(lV) then
          lKeys.Delete(i)
        else if (pCtx in [cxSurface, cxExample, cxLastVerified, cxFlag, cxQuestion, cxVerified]) and (lV is TJSONNull) and (i < Length(lOrder)) then
          lKeys.Delete(i);
      end;
    if lKeys.Count = 0 then
    begin
      pSb.Append('{}');
      Exit;
    end;
    pSb.Append('{').Append(#13#10);
    for i := 0 to lKeys.Count - 1 do
    begin
      lName := lKeys[i];
      if not lByName.TryGetValue(lName, lV) then
        lV := lEmptyArr; // synthesized surfaces: []
      pSb.Append(lPad).Append('  ');
      AppendString(pSb, lName);
      pSb.Append(': ');
      if pCtx = cxEntry then
      begin
        if ((lName = 'related') or (lName = 'aliases')) and (lV is TJSONArray) then
          AppendArray(pSb, SortedUniqueStrings(TJSONArray(lV), lOwner), pLevel + 1, cxPlain)
        else if (lName = 'surfaces') and (lV is TJSONArray) then
          AppendArray(pSb, ArrayItems(TJSONArray(lV)), pLevel + 1, cxSurface)
        else if (lName = 'examples') and (lV is TJSONArray) then
          AppendArray(pSb, ArrayItems(TJSONArray(lV)), pLevel + 1, cxExample)
        else if (lName = 'lastVerified') and (lV is TJSONObject) then
          AppendObject(pSb, TJSONObject(lV), pLevel + 1, cxLastVerified, nil)
        else if (lName = 'accessReviewed') and (lV is TJSONObject) then
          AppendObject(pSb, TJSONObject(lV), pLevel + 1, cxLastVerified, nil)
        else if (lName = 'verified') and (lV is TJSONObject) then
          AppendObject(pSb, TJSONObject(lV), pLevel + 1, cxVerified, nil)
        else if (lName = 'questions') and (lV is TJSONArray) then
          AppendArray(pSb, ArrayItems(TJSONArray(lV)), pLevel + 1, cxQuestion)
        else
          AppendValue(pSb, lV, pLevel + 1, cxPlain, nil);
      end
      else if (pCtx = cxSurface) and (lName = 'flags') and (lV is TJSONArray) then
        AppendArray(pSb, ArrayItems(TJSONArray(lV)), pLevel + 1, cxFlag)
      else
      begin
        lItemCtx := cxPlain;
        AppendValue(pSb, lV, pLevel + 1, lItemCtx, nil);
      end;
      if i < lKeys.Count - 1 then
        pSb.Append(',');
      pSb.Append(#13#10);
    end;
    pSb.Append(lPad).Append('}');
  finally
    lEmptyArr.Free;
    lOwner.Free;
    lKeys.Free;
    lByName.Free;
  end;
end;

procedure AppendValue(pSb: TStringBuilder; pV: TJSONValue; pLevel: Integer; pCtx: TCtx;
  const pKeyOrder: TArray<string>);
begin
  if (pV = nil) or (pV is TJSONNull) then
    pSb.Append('null')
  else if pV is TJSONBool then
    pSb.Append(IfThen(TJSONBool(pV).AsBoolean, 'true', 'false'))
  else if pV is TJSONString then
    AppendString(pSb, TJSONString(pV).Value)
  else if pV is TJSONNumber then
    pSb.Append(pV.ToString)
  else if pV is TJSONObject then
    AppendObject(pSb, TJSONObject(pV), pLevel, pCtx, pKeyOrder)
  else if pV is TJSONArray then
    AppendArray(pSb, ArrayItems(TJSONArray(pV)), pLevel, cxPlain)
  else
    AppendString(pSb, pV.ToString);
end;

function CanonicalJson(const pValue: TJSONValue; const pKeyOrder: TArray<string>): string;
var
  lSb: TStringBuilder;
  lCtx: TCtx;
begin
  lSb := TStringBuilder.Create;
  try
    if (Length(pKeyOrder) > 0) and (pValue is TJSONObject) then
      lCtx := cxEntry
    else
      lCtx := cxPlain;
    AppendValue(lSb, pValue, 0, lCtx, pKeyOrder);
    lSb.Append(#13#10);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

end.
