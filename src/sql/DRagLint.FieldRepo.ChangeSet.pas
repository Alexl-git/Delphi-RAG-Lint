unit DRagLint.FieldRepo.ChangeSet;

{ drag-lint 1.53 -- lane FR-MODEL: the change-set record every sync produces and every UI confirms
  (design 2026-11-22-field-repository-v2-design.md section 3). 1.53 ships the type, the text / JSON rendering
  and the `--select` file parser; the producers and appliers (DB, DFM) arrive in 1.54. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised by the --select file parser (unknown id, blocked change named explicitly, bad line).</summary>
  EFrChangeSetError = class(Exception);

  /// <summary>What a change does to its target.</summary>
  TFrChangeOp = (fcoInsert, fcoUpdate, fcoDelete);

  /// <summary>Which way a sync flows; there is NO default direction (FU-3).</summary>
  TFrDirection = (fdDbToRepo, fdRepoToDb, fdDfmToRepo, fdRepoToDfm);

  /// <summary>One proposed change.</summary>
  TFrChange = record
    /// <summary>1-based, stable within one change set; what --select names.</summary>
    Id: Integer;
    /// <summary>Insert, update or delete.</summary>
    Op: TFrChangeOp;
    /// <summary>`DL_FIELDS_INFO MSCLIST|DIMNAME`, `uOrders.dfm qryOrdersQTY`, `MSCLIST.DIMABBR`.</summary>
    Target: string;
    /// <summary>Column / DFM property; '' for a whole-row insert or delete.</summary>
    Prop: string;
    /// <summary>Value before the change ('' for an insert).</summary>
    OldValue: string;
    /// <summary>Value after the change ('' for a delete).</summary>
    NewValue: string;
    /// <summary>Default from the confirm rules (all True today); False for a blocked change.</summary>
    Checked: Boolean;
    /// <summary>Non-empty = cannot be applied (for example Firebird refuses); never checked.</summary>
    Blocked: string;
  end;

  /// <summary>A direction plus its changes.</summary>
  TFrChangeSet = record
    /// <summary>The required direction.</summary>
    Direction: TFrDirection;
    /// <summary>The changes in id order.</summary>
    Changes: TArray<TFrChange>;
  end;

/// <summary>Command-line name of a direction: db-to-repo, repo-to-db, dfm-to-repo, repo-to-dfm.</summary>
/// <param name="pDirection">The direction.</param>
/// <returns>The name used in the header line and the JSON.</returns>
function FrDirectionName(pDirection: TFrDirection): string;

/// <summary>Renders a change set as ASCII text.</summary>
/// <param name="pSet">The change set.</param>
/// <returns>The header `direction DIR, N changes, B blocked`, then one line per change
/// `[id] op target prop: old -> new` (`[id] op target: old -> new` when Prop is empty) followed, for a blocked
/// change, by `  BLOCKED: reason`, for an unchecked unblocked one by `  (unchecked)`. The header ends `, U unchecked`
/// (U = not checked and not blocked). Non-ASCII, control characters and backslash in values are escaped.</returns>
function RenderChangeSetText(const pSet: TFrChangeSet): TArray<string>;

/// <summary>Renders a change set as JSON mirroring the record.</summary>
/// <param name="pSet">The change set.</param>
/// <returns>`{"direction","count","blocked","changes":[{"id","op","target","prop","old","new","checked","blocked"}]}`.</returns>
function RenderChangeSetJson(const pSet: TFrChangeSet): string;

/// <summary>Resolves a `--select` file against a change set.</summary>
/// <param name="pSet">The change set.</param>
/// <param name="pLines">The file's lines: one id per line, or `all`; blank lines and lines starting `#` are ignored.</param>
/// <returns>The selected changes in id order, without duplicates. `all` selects every change that is not blocked.</returns>
/// <exception cref="EFrChangeSetError">An unknown id, a line that is not an id or `all`, or a blocked change named
/// by id (nothing is selected then; the caller applies nothing).</exception>
/// <remarks>A blocked change is never selected by `all`. Without `--apply` the caller writes nothing anyway.</remarks>
function SelectChanges(const pSet: TFrChangeSet; const pLines: TArray<string>): TArray<TFrChange>;

/// <summary>The itemised log line of an applied change (FU-9).</summary>
/// <param name="pChange">The applied change.</param>
/// <returns>`replacing &lt;old&gt; with &lt;new&gt;` (ASCII-escaped like the text rendering).</returns>
function ApplyLogLine(const pChange: TFrChange): string;

implementation

uses
  System.Classes,
  System.JSON,
  System.Generics.Collections;

const
  OP_NAMES: array[TFrChangeOp] of string = ('insert', 'update', 'delete');
  DIR_NAMES: array[TFrDirection] of string = ('db-to-repo', 'repo-to-db', 'dfm-to-repo', 'repo-to-dfm');
  SELECT_ALL = 'all';
  COMMENT_PREFIX = '#';
  ASCII_LAST = $7E;
  ASCII_FIRST = $20;
  HEX_DIGITS = 4;

function FrDirectionName(pDirection: TFrDirection): string;
begin
  Result := DIR_NAMES[pDirection];
end;

function EscapeValue(const pValue: string): string;
var
  VC: Char;
  VB: TStringBuilder;
begin
  VB := TStringBuilder.Create;
  try
    for VC in pValue do
      if VC = '\' then
        VB.Append('\\')
      else if VC = #9 then
        VB.Append('\t')
      else if VC = #10 then
        VB.Append('\n')
      else if VC = #13 then
        VB.Append('\r')
      else if (Ord(VC) < ASCII_FIRST) or (Ord(VC) > ASCII_LAST) then
        VB.Append('\u').Append(IntToHex(Ord(VC), HEX_DIGITS))
      else
        VB.Append(VC);
    Result := VB.ToString;
  finally
    VB.Free;
  end;
end;

function BlockedCount(const pSet: TFrChangeSet): Integer;
var
  VChange: TFrChange;
begin
  Result := 0;
  for VChange in pSet.Changes do
    if VChange.Blocked <> '' then
      Inc(Result);
end;

function UncheckedCount(const pSet: TFrChangeSet): Integer;
var
  VChange: TFrChange;
begin
  Result := 0;
  for VChange in pSet.Changes do
    if (not VChange.Checked) and (VChange.Blocked = '') then
      Inc(Result);
end;

function RenderChangeSetText(const pSet: TFrChangeSet): TArray<string>;
var
  VChange: TFrChange;
  VLine: string;
begin
  Result := [Format('direction %s, %d changes, %d blocked, %d unchecked', [FrDirectionName(pSet.Direction),
    Length(pSet.Changes), BlockedCount(pSet), UncheckedCount(pSet)])];
  for VChange in pSet.Changes do
  begin
    VLine := Format('[%d] %s %s', [VChange.Id, OP_NAMES[VChange.Op], EscapeValue(VChange.Target)]);
    if VChange.Prop <> '' then
      VLine := VLine + ' ' + EscapeValue(VChange.Prop);
    VLine := VLine + ': ' + EscapeValue(VChange.OldValue) + ' -> ' + EscapeValue(VChange.NewValue);
    Result := Result + [VLine];
    if VChange.Blocked <> '' then
      Result := Result + ['  BLOCKED: ' + EscapeValue(VChange.Blocked)]
    else if not VChange.Checked then
      Result := Result + ['  (unchecked)'];
  end;
end;

function RenderChangeSetJson(const pSet: TFrChangeSet): string;
var
  VRoot, VItem: TJSONObject;
  VList: TJSONArray;
  VChange: TFrChange;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('direction', FrDirectionName(pSet.Direction));
    VRoot.AddPair('count', TJSONNumber.Create(Length(pSet.Changes)));
    VRoot.AddPair('blocked', TJSONNumber.Create(BlockedCount(pSet)));
    VList := TJSONArray.Create;
    VRoot.AddPair('changes', VList);
    for VChange in pSet.Changes do
    begin
      VItem := TJSONObject.Create;
      VItem.AddPair('id', TJSONNumber.Create(VChange.Id));
      VItem.AddPair('op', OP_NAMES[VChange.Op]);
      VItem.AddPair('target', VChange.Target);
      VItem.AddPair('prop', VChange.Prop);
      VItem.AddPair('old', VChange.OldValue);
      VItem.AddPair('new', VChange.NewValue);
      VItem.AddPair('checked', TJSONBool.Create(VChange.Checked and (VChange.Blocked = '')));
      VItem.AddPair('blocked', VChange.Blocked);
      VList.AddElement(VItem);
    end;
    Result := VRoot.ToJSON;
  finally
    VRoot.Free;
  end;
end;

function FindChange(const pSet: TFrChangeSet; pId: Integer; out pChange: TFrChange): Boolean;
var
  VChange: TFrChange;
begin
  Result := False;
  pChange := Default(TFrChange);
  for VChange in pSet.Changes do
    if VChange.Id = pId then
    begin
      pChange := VChange;
      Exit(True);
    end;
end;

function SelectChanges(const pSet: TFrChangeSet; const pLines: TArray<string>): TArray<TFrChange>;
var
  VLine, VText: string;
  VId: Integer;
  VChange, VOther: TFrChange;
  VIds: TList<Integer>;
  VAll: Boolean;
begin
  Result := nil;
  VIds := TList<Integer>.Create;
  try
    VAll := False;
    for VLine in pLines do
    begin
      VText := Trim(VLine);
      if (VText = '') or VText.StartsWith(COMMENT_PREFIX) then
        Continue;
      if SameText(VText, SELECT_ALL) then
        VAll := True
      else if TryStrToInt(VText, VId) then
      begin
        if not FindChange(pSet, VId, VChange) then
          raise EFrChangeSetError.CreateFmt('unknown change id %d', [VId]);
        if VChange.Blocked <> '' then
          raise EFrChangeSetError.CreateFmt('change %d is blocked: %s', [VId, VChange.Blocked]);
        if VIds.IndexOf(VId) < 0 then
          VIds.Add(VId);
      end
      else
        raise EFrChangeSetError.CreateFmt('not a change id or "all": %s', [VText]);
    end;
    for VOther in pSet.Changes do
      if (VOther.Blocked = '') and (VAll or (VIds.IndexOf(VOther.Id) >= 0)) then
        Result := Result + [VOther];
  finally
    VIds.Free;
  end;
end;

function ApplyLogLine(const pChange: TFrChange): string;
begin
  Result := 'replacing ' + EscapeValue(pChange.OldValue) + ' with ' + EscapeValue(pChange.NewValue);
end;

end.
