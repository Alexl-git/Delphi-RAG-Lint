unit DRagLint.FieldRepo.Alter;

{ drag-lint 1.54 -- lane TT-ALTER: the PURE diff engine of the per-table ALTER (design
  2026-11-22-field-repository-v2-design.md section 9, plan 2026-11-23-fr-alter-table.md): the repository's facts of
  one table against the live facts -> an ordered change set with exact DDL. Nothing here connects, reads or writes.

  Every BLOCKED text starts with a stable code and a colon (the BLOCK_ constants). }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DbProvider;

const
  /// <summary>Codes a BLOCKED text starts with.</summary>
  BLOCK_DEPENDENCY = 'dependency';
  BLOCK_CONSTRAINT = 'constraint';
  BLOCK_INDEX = 'index';
  BLOCK_COMPUTED = 'computed-by';
  BLOCK_IDENTITY = 'identity';
  BLOCK_GRANTS = 'column-grants';
  BLOCK_DOMAIN = 'domain';
  BLOCK_CHARSET = 'charset';
  BLOCK_SHRINK = 'refused-shrink';
  BLOCK_CONVERSION = 'refused-conversion';
  BLOCK_LOSSY = 'lossy';
  BLOCK_UNSUPPORTED = 'unsupported-type';
  BLOCK_DEFAULT = 'default';
  BLOCK_TRIGGERS = 'update-triggers';
  BLOCK_TEMP_NAME = 'temp-name';
  BLOCK_INCONSISTENT = 'repo-inconsistent';
  BLOCK_DIALECT = 'dialect';
  BLOCK_HOOK = 'hook';
  BLOCK_PENDING = 'pending-type-change';
  { set by the pre-checks }
  BLOCK_NULLS = 'nulls';
  BLOCK_ROWS = 'rows';
  BLOCK_CAST = 'cast-failures';
  BLOCK_LOSS = 'value-loss';

type
  /// <summary>Raised on a request that cannot be planned (unknown table, bad --rename / --order).</summary>
  EFrAlterError = class(Exception);

  /// <summary>One data column as the repository holds it.</summary>
  TFrRepoColumn = record
    Name: string;
    DomainName: string;
    DataType: TFrTypeFacts;
    NotNull: Boolean;
    /// <summary>DEFAULTVAL; '' when none. Used only for a NEW column.</summary>
    DefaultValue: string;
    /// <summary>Non-empty = the row contradicts itself; a type change is then blocked.</summary>
    Inconsistent: string;
  end;

  /// <summary>The repository's facts of one table.</summary>
  TFrRepoTable = record
    TableName: string;
    /// <summary>False = the repository has no data column row for the table.</summary>
    Found: Boolean;
    Columns: TArray<TFrRepoColumn>;
    /// <summary>Rows that are not data columns (calc, lookup, graphical): never added, never a reason to drop.</summary>
    OtherRows: TArray<string>;
    Domains: TArray<TFrDomainFacts>;
    SchemaReadAtUtc: string;
    SchemaDatabase: string;
  end;

  /// <summary>One explicit rename.</summary>
  TFrRename = record
    OldName: string;
    NewName: string;
  end;

  /// <summary>What the caller asked for beyond the diff.</summary>
  TFrAlterOptions = record
    /// <summary>Offers the add-copy-drop-rename path for refused type changes.</summary>
    SafePath: Boolean;
    Renames: TArray<TFrRename>;
    /// <summary>Wanted first columns in order; the others keep their relative order after them.</summary>
    Order: TArray<string>;
  end;

  /// <summary>What a change is.</summary>
  TFrAlterKind = (fakCreateDomain, fakRename, fakType, fakNullability, fakAdd, fakDrop, fakSafeType, fakOrder);

  /// <summary>A question to the live data, asked before anything is written.</summary>
  TFrPrecheck = record
    Sql: string;
    /// <summary>BLOCK_ code when the count is not zero; '' = information only.</summary>
    Code: string;
    /// <summary>Message with one %d for the count.</summary>
    Text: string;
    /// <summary>Set by the pre-check run; -1 = not run.</summary>
    Count: Int64;
  end;

  /// <summary>The statements of one safe-path change; three transactions (see DRagLint.FieldRepo.AlterApply).</summary>
  TFrSafeSteps = record
    Column: string;
    TempColumn: string;
    AddSql: string;
    CopySql: string;
    /// <summary>Must return 0, in the swap transaction, before the old column is dropped.</summary>
    MismatchSql: string;
    SwapSql: TArray<string>;
    /// <summary>Compensation: drops the temporary column.</summary>
    CleanupSql: string;
  end;

  /// <summary>One planned change: the shared change-set record plus how to do it.</summary>
  TFrAlterChange = record
    Change: TFrChange;
    Kind: TFrAlterKind;
    /// <summary>The column after the change ('' for a domain or the order).</summary>
    Column: string;
    /// <summary>Statements of a direct change; empty for the safe path.</summary>
    Ddl: TArray<string>;
    Safe: TFrSafeSteps;
    Prechecks: TArray<TFrPrecheck>;
    /// <summary>Ids that must be applied with (before) this one.</summary>
    DependsOn: TArray<Integer>;
    Notes: TArray<string>;
    /// <summary>Type the column must have afterwards (verification); FieldType 0 = not checked.</summary>
    ExpectType: TFrTypeFacts;
  end;

  /// <summary>An ordered plan for one table.</summary>
  TFrAlterPlan = record
    TableName: string;
    DatabaseName: string;
    DialectName: string;
    Changes: TArray<TFrAlterChange>;
    Notes: TArray<string>;
    /// <summary>Statements a hook adds before the first / after the last group (own transactions).</summary>
    HookBefore, HookAfter: TArray<string>;
    /// <summary>LiveFingerprint of the facts the plan was made from.</summary>
    LiveFingerprint: string;
    /// <summary>The plan as the shared change set (direction repo-to-db).</summary>
    /// <returns>The changes in id order.</returns>
    function ChangeSet: TFrChangeSet;
    /// <summary>Hash of everything the plan would execute plus the live fingerprint.</summary>
    /// <returns>A hex SHA-256.</returns>
    function Hash: string;
  end;

/// <summary>Plans the changes that make the live table match the repository.</summary>
/// <param name="pRepo">The repository's facts.</param>
/// <param name="pLive">The live facts.</param>
/// <param name="pOptions">Safe path, renames, order.</param>
/// <param name="pDialect">SQL text generator of the target database.</param>
/// <returns>Changes in execution order: domains, renames, types, nullability, adds, drops, safe types, order.</returns>
/// <exception cref="EFrAlterError">The table is missing on either side or is not a plain table; a rename or the order
/// names a column that is not there.</exception>
/// <remarks>Pure and deterministic. A change Firebird would refuse, or accept and lose data, is BLOCKED with a reason.
/// Drops, DROP NOT NULL and safe-path changes are never checked.</remarks>
function PlanAlter(const pRepo: TFrRepoTable; const pLive: TFrTableFacts; const pOptions: TFrAlterOptions;
  const pDialect: IFrDbDialect): TFrAlterPlan;

/// <summary>Hash of the live facts; a difference at apply time means somebody changed the table meanwhile.</summary>
/// <param name="pLive">The facts.</param>
/// <returns>A hex SHA-256.</returns>
function LiveFingerprint(const pLive: TFrTableFacts): string;

/// <summary>True when two types are the same for the repository (precision is ignored: it holds none).</summary>
/// <param name="pLeft">One type.</param>
/// <param name="pRight">The other type.</param>
/// <returns>True when equal.</returns>
function SameType(const pLeft, pRight: TFrTypeFacts): Boolean;

/// <summary>Parses `--rename OLD=NEW[,OLD=NEW]`.</summary>
/// <param name="pText">The option value; '' = none.</param>
/// <returns>The renames, upper-case.</returns>
/// <exception cref="EFrAlterError">An item is not OLD=NEW.</exception>
function ParseRenames(const pText: string): TArray<TFrRename>;

implementation

uses
  System.StrUtils,
  System.Hash;

const
  FB_SMALLINT = 7;
  FB_INTEGER = 8;
  FB_FLOAT = 10;
  FB_CHAR = 14;
  FB_BIGINT = 16;
  FB_INT128 = 26;
  FB_DOUBLE = 27;
  FB_DATE = 12;
  FB_TIMESTAMP = 35;
  FB_VARCHAR = 37;
  FB_TIME_TZ = 28;
  FB_TIMESTAMP_TZ = 29;
  FB_BLOB = 261;
  SUB_OCTETS = 1;
  CHARSET_OCTETS = 'OCTETS';
  { width order of the exact numeric types; 0 = not exact }
  RANK_SMALLINT = 1;
  RANK_INTEGER = 2;
  RANK_BIGINT = 3;
  RANK_INT128 = 4;
  TEMP_SUFFIX = '_NEW';
  TEXT_NOT_NULL = 'NOT NULL';
  TEXT_NULL = 'NULL';
  KIND_INDEX = 'INDEX';
  ORDER_TARGET = 'column order';
  SAFE_HINT = ' (a safe path exists: --safe-path)';
  COUNT_NOT_RUN = -1;
  NO_HARD_REASON = '';

type
  TFrTypeVerdict = (tvSame, tvWiden, tvShrink, tvLossy, tvConvert, tvUnsupported);

  { One planning run. }
  TAlterPlanner = record
  private
    FRepo: TFrRepoTable;
    FLive: TFrTableFacts;
    FOptions: TFrAlterOptions;
    FDialect: IFrDbDialect;
    FPlan: TFrAlterPlan;
    { columns that get a safe-path change: name -> appended after the direct changes }
    FSafe: TArray<TFrAlterChange>;
    function AddChange(const pChange: TFrAlterChange): Integer;
    function NewChange(pKind: TFrAlterKind; pOp: TFrChangeOp; const pColumn, pProp, pOld, pNew: string): TFrAlterChange;
    function TypeText(const pType: TFrTypeFacts; const pDomain: string): string;
    function RenameTo(const pNew: string; out pOld: string): Boolean;
    function IsRenameSource(const pName: string): Boolean;
    function IsRepoName(const pName: string): Boolean;
    function IdOf(pKind: TFrAlterKind; const pColumn: string): Integer;
    function DomainOf(const pCol: TFrRepoColumn; out pDomain: TFrDomainFacts; out pInLive: Boolean; out pReason: string): Boolean;
    function ObjectReasons(const pColumn: string): TArray<string>;
    procedure CheckRequest;
    procedure PlanDomains;
    procedure PlanRenames;
    procedure PlanTypes;
    procedure PlanType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts);
    procedure PlanDirectType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
      const pDomain: TFrDomainFacts; pVerdict: TFrTypeVerdict);
    procedure PlanSafeType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
      const pDomain: TFrDomainFacts; const pHard: TArray<string>);
    function SafeReasons(const pColumn: string; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
      const pDomain: TFrDomainFacts): TArray<string>;
    function BuildSafeSteps(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts): TFrSafeSteps;
    procedure PlanNullability;
    procedure PlanAdds;
    procedure PlanDrops;
    procedure PlanOrder;
    function FinalNames: TArray<string>;
  public
    function Run: TFrAlterPlan;
  end;

function Precheck(const pSql, pCode, pText: string): TFrPrecheck;
begin
  Result.Sql := pSql;
  Result.Code := pCode;
  Result.Text := pText;
  Result.Count := COUNT_NOT_RUN;
end;

function Reason(const pCode, pText: string): string;
begin
  Result := pCode + ': ' + pText;
end;

function HasText(const pList: TArray<string>; const pText: string): Boolean;
begin
  Result := MatchText(pText, pList);
end;

function ExactRank(const pType: TFrTypeFacts): Integer;
begin
  case pType.FieldType of
    FB_SMALLINT: Result := RANK_SMALLINT;
    FB_INTEGER: Result := RANK_INTEGER;
    FB_BIGINT: Result := RANK_BIGINT;
    FB_INT128: Result := RANK_INT128;
  else
    Result := 0;
  end;
end;

function IsChar(const pType: TFrTypeFacts): Boolean;
begin
  Result := (pType.FieldType = FB_CHAR) or (pType.FieldType = FB_VARCHAR);
end;

function IsNumber(const pType: TFrTypeFacts): Boolean;
begin
  Result := (ExactRank(pType) > 0) or (pType.FieldType = FB_FLOAT) or (pType.FieldType = FB_DOUBLE);
end;

{ characters of a character type; the byte length when the repository knows no character length }
function CharsOf(const pType: TFrTypeFacts): Integer;
begin
  Result := if pType.CharLength > 0 then pType.CharLength else pType.ByteLength;
end;

{ Firebird 4 marks a binary column by its character set; the sub type stays 0 }
function IsOctets(const pType: TFrTypeFacts): Boolean;
begin
  Result := IsChar(pType) and ((pType.SubType = SUB_OCTETS) or SameText(pType.Charset, CHARSET_OCTETS));
end;

{ False when one side does not say: the repository holds no character set for a column without a domain }
function OctetsDiffer(const pLeft, pRight: TFrTypeFacts): Boolean;
begin
  Result := (IsOctets(pLeft) <> IsOctets(pRight)) and ((pLeft.Charset <> '') or (pLeft.SubType <> 0)) and
    ((pRight.Charset <> '') or (pRight.SubType <> 0));
end;

{ characters are compared with characters and bytes with bytes }
function SameLength(const pLeft, pRight: TFrTypeFacts): Boolean;
begin
  Result := if (pLeft.CharLength > 0) and (pRight.CharLength > 0) then pLeft.CharLength = pRight.CharLength
    else pLeft.ByteLength = pRight.ByteLength;
end;

{ A comparison of two zoned values ignores the zone, so no scan could see that it is lost. }
function IsUnconvertible(const pType: TFrTypeFacts): Boolean;
begin
  Result := (pType.FieldType = FB_BLOB) or (pType.FieldType = FB_TIME_TZ) or (pType.FieldType = FB_TIMESTAMP_TZ) or IsOctets(pType);
end;

function SameType(const pLeft, pRight: TFrTypeFacts): Boolean;
begin
  Result := pLeft.FieldType = pRight.FieldType;
  if not Result then
    Exit;
  if IsChar(pLeft) then
    Result := SameLength(pLeft, pRight) and not OctetsDiffer(pLeft, pRight)
  else if pLeft.FieldType = FB_BLOB then
    Result := pLeft.SubType = pRight.SubType
  else
    Result := (pLeft.Scale = pRight.Scale) and ((ExactRank(pLeft) = 0) or (pLeft.SubType = pRight.SubType));
end;

function ExactVerdict(const pOld, pNew: TFrTypeFacts): TFrTypeVerdict;
begin
  if pOld.Scale <> pNew.Scale then
    Exit(if pNew.Scale > pOld.Scale then tvLossy else tvConvert);
  if ExactRank(pNew) < ExactRank(pOld) then
    Exit(tvShrink);
  Result := if pOld.SubType = pNew.SubType then tvWiden else tvConvert;
end;

{ What Firebird 4 makes of a type change (measured, plan 2026-11-23-fr-alter-table.md): tvLossy = it accepts the
  change and loses data; tvConvert = it refuses, or the change is not on the whitelist. }
function TypeVerdict(const pOld, pNew: TFrTypeFacts): TFrTypeVerdict;
begin
  if SameType(pOld, pNew) then
    Exit(tvSame);
  if IsUnconvertible(pOld) or IsUnconvertible(pNew) then
    Exit(tvUnsupported);
  if IsChar(pOld) and (pOld.FieldType = pNew.FieldType) then
    Exit(if CharsOf(pNew) > CharsOf(pOld) then tvWiden else tvShrink);
  if (ExactRank(pOld) > 0) and (ExactRank(pNew) > 0) then
    Exit(ExactVerdict(pOld, pNew));
  Result := tvConvert;
  if (pOld.FieldType = FB_FLOAT) and (pNew.FieldType = FB_DOUBLE) then
    Result := tvWiden
  else if (pOld.FieldType = FB_DOUBLE) and (pNew.FieldType = FB_FLOAT) then
    Result := tvShrink
  else if (pOld.FieldType = FB_TIMESTAMP) and (pNew.FieldType = FB_DATE) then
    Result := tvLossy;
end;

{ A default the repository may put into DDL: one literal or one context value, nothing else. }
function IsPlainDefault(const pText: string): Boolean;
const
  WORDS: array[0..8] of string = ('NULL', 'TRUE', 'FALSE', 'CURRENT_DATE', 'CURRENT_TIME', 'CURRENT_TIMESTAMP',
    'LOCALTIME', 'LOCALTIMESTAMP', 'CURRENT_USER');
var
  VText: string;
  VNumber: Double;
begin
  VText := Trim(pText);
  if VText = '' then
    Exit(False);
  if MatchText(VText, WORDS) then
    Exit(True);
  if (Length(VText) >= 2) and VText.StartsWith('''') and VText.EndsWith('''') then
    Exit(not StringReplace(Copy(VText, 2, Length(VText) - 2), '''''', '', [rfReplaceAll]).Contains(''''));
  Result := TryStrToFloat(VText, VNumber, TFormatSettings.Invariant);
end;

function LiveFingerprint(const pLive: TFrTableFacts): string;
var
  VText: TStringBuilder;
  VCol: TFrColumnFacts;
  VKey: TFrKeyFacts;
  VDep: TFrDependency;
  VDom: TFrDomainFacts;

  procedure AddType(const pType: TFrTypeFacts);
  begin
    VText.AppendFormat('%d/%d/%d/%d/%d/%d/%s/%s|', [pType.FieldType, pType.SubType, pType.ByteLength, pType.CharLength,
      pType.Scale, pType.Precision, pType.Charset, pType.Collation]);
  end;

begin
  VText := TStringBuilder.Create;
  try
    VText.AppendFormat('%s|%s|', [pLive.TableName, pLive.NotPlainTable]);
    for VCol in pLive.Columns do
    begin
      VText.AppendFormat('c %s|%d|%s|%s|%s|%d%d%d%d|', [VCol.Name, VCol.Position, VCol.DomainName, VCol.DefaultSource,
        VCol.ComputedSource, Ord(VCol.ColumnNotNull), Ord(VCol.DomainNotNull), Ord(VCol.IsIdentity), Ord(VCol.HasColumnGrants)]);
      AddType(VCol.DataType);
    end;
    for VDom in pLive.Domains do
    begin
      VText.AppendFormat('d %s|%d|%s|%s|', [VDom.Name, Ord(VDom.NotNull), VDom.DefaultSource, VDom.CheckSource]);
      AddType(VDom.DataType);
    end;
    for VKey in pLive.Keys do
      VText.AppendFormat('k %s|%s|%s|', [VKey.Name, VKey.Kind, string.Join(',', VKey.Columns)]);
    for VDep in pLive.Dependencies do
      VText.AppendFormat('p %s|%s|%s|', [VDep.ColumnName, VDep.DependentName, VDep.KindText]);
    VText.Append('t ').Append(string.Join(',', pLive.UpdateTriggers));
    Result := THashSHA2.GetHashString(VText.ToString);
  finally
    VText.Free;
  end;
end;

function ParseRenames(const pText: string): TArray<TFrRename>;
var
  VItem: string;
  VParts: TArray<string>;
  VRename: TFrRename;
begin
  Result := nil;
  for VItem in pText.Split([','], TStringSplitOptions.ExcludeEmpty) do
  begin
    VParts := VItem.Split(['=']);
    if (Length(VParts) <> 2) or (Trim(VParts[0]) = '') or (Trim(VParts[1]) = '') then
      raise EFrAlterError.CreateFmt('--rename takes OLD=NEW[,OLD=NEW], not "%s"', [VItem]);
    VRename.OldName := Trim(VParts[0]).ToUpper;
    VRename.NewName := Trim(VParts[1]).ToUpper;
    Result := Result + [VRename];
  end;
end;

{ TFrAlterPlan }

function TFrAlterPlan.ChangeSet: TFrChangeSet;
var
  VChange: TFrAlterChange;
begin
  Result := Default(TFrChangeSet);
  Result.Direction := fdRepoToDb;
  for VChange in Changes do
    Result.Changes := Result.Changes + [VChange.Change];
end;

function TFrAlterPlan.Hash: string;
var
  VText: TStringBuilder;
  VChange: TFrAlterChange;
begin
  VText := TStringBuilder.Create;
  try
    VText.Append(TableName).Append('|').Append(DatabaseName).Append('|').Append(LiveFingerprint).Append('|');
    VText.Append(string.Join(';', HookBefore)).Append('|').Append(string.Join(';', HookAfter));
    for VChange in Changes do
    begin
      VText.AppendFormat('|%d|', [VChange.Change.Id]).Append(string.Join(';', VChange.Ddl));
      VText.Append('|').Append(VChange.Safe.AddSql).Append('|').Append(VChange.Safe.CopySql).Append('|');
      VText.Append(VChange.Safe.MismatchSql).Append('|').Append(string.Join(';', VChange.Safe.SwapSql));
    end;
    Result := THashSHA2.GetHashString(VText.ToString);
  finally
    VText.Free;
  end;
end;

{ TAlterPlanner }

function TAlterPlanner.NewChange(pKind: TFrAlterKind; pOp: TFrChangeOp; const pColumn, pProp, pOld, pNew: string): TFrAlterChange;
begin
  Result := Default(TFrAlterChange);
  Result.Kind := pKind;
  Result.Column := pColumn;
  Result.Change.Op := pOp;
  Result.Change.Target := FRepo.TableName + '.' + pColumn;
  Result.Change.Prop := pProp;
  Result.Change.OldValue := pOld;
  Result.Change.NewValue := pNew;
  Result.Change.Checked := True;
end;

function TAlterPlanner.AddChange(const pChange: TFrAlterChange): Integer;
var
  VChange: TFrAlterChange;
begin
  VChange := pChange;
  Result := Length(FPlan.Changes) + 1;
  VChange.Change.Id := Result;
  if VChange.Change.Blocked <> '' then
    VChange.Change.Checked := False;
  FPlan.Changes := FPlan.Changes + [VChange];
end;

function TAlterPlanner.TypeText(const pType: TFrTypeFacts; const pDomain: string): string;
begin
  Result := FDialect.TypeClause(pType, False);
  if Result = '' then
    Result := Format('type %d/%d', [pType.FieldType, pType.SubType]);
  if pDomain <> '' then
    Result := pDomain + ' (' + Result + ')';
end;

function TAlterPlanner.RenameTo(const pNew: string; out pOld: string): Boolean;
var
  VRename: TFrRename;
begin
  Result := False;
  pOld := '';
  for VRename in FOptions.Renames do
    if SameText(VRename.NewName, pNew) then
    begin
      pOld := VRename.OldName;
      Exit(True);
    end;
end;

function TAlterPlanner.IsRenameSource(const pName: string): Boolean;
var
  VRename: TFrRename;
begin
  Result := False;
  for VRename in FOptions.Renames do
    if SameText(VRename.OldName, pName) then
      Exit(True);
end;

function TAlterPlanner.IsRepoName(const pName: string): Boolean;
var
  VCol: TFrRepoColumn;
begin
  Result := HasText(FRepo.OtherRows, pName);
  if not Result then
    for VCol in FRepo.Columns do
      if SameText(VCol.Name, pName) then
        Exit(True);
end;

function TAlterPlanner.IdOf(pKind: TFrAlterKind; const pColumn: string): Integer;
var
  VChange: TFrAlterChange;
begin
  Result := 0;
  for VChange in FPlan.Changes do
    if (VChange.Kind = pKind) and SameText(VChange.Column, pColumn) then
      Exit(VChange.Change.Id);
end;

procedure TAlterPlanner.CheckRequest;
var
  VRename: TFrRename;
  VCol: TFrColumnFacts;
  VName: string;
  VKnown: TArray<string>;
begin
  if not FRepo.Found then
    raise EFrAlterError.CreateFmt('the repository has no data column of table %s', [FRepo.TableName]);
  if not FLive.Exists then
    raise EFrAlterError.CreateFmt('the database has no table %s (alter-table never creates one)', [FRepo.TableName]);
  if FLive.NotPlainTable <> '' then
    raise EFrAlterError.CreateFmt('%s is %s: only a plain table can be altered', [FRepo.TableName, FLive.NotPlainTable]);
  { names are matched without case, so a delimited lower-case name could be taken for its upper-case twin }
  for VCol in FLive.Columns do
    if VCol.Name <> VCol.Name.ToUpper then
      raise EFrAlterError.CreateFmt('column "%s" has a delimited mixed-case name: the table is not handled', [VCol.Name]);
  for VRename in FOptions.Renames do
  begin
    if not FLive.FindColumn(VRename.OldName, VCol) then
      raise EFrAlterError.CreateFmt('--rename: the table has no column %s', [VRename.OldName]);
    if FLive.FindColumn(VRename.NewName, VCol) then
      raise EFrAlterError.CreateFmt('--rename: the table already has a column %s', [VRename.NewName]);
    if IsRepoName(VRename.OldName) or not IsRepoName(VRename.NewName) then
      raise EFrAlterError.CreateFmt('--rename %s=%s: the repository must hold the new name and not the old one',
        [VRename.OldName, VRename.NewName]);
  end;
  VKnown := FinalNames;
  for VName in FOptions.Order do
    if not HasText(VKnown, VName) then
      raise EFrAlterError.CreateFmt('--order: %s is not a column of the table after the changes', [VName]);
end;

{ Column names after renames and adds, before drops, in table order. }
function TAlterPlanner.FinalNames: TArray<string>;
var
  VCol: TFrColumnFacts;
  VRename: TFrRename;
  VRepoCol: TFrRepoColumn;
  VName, VOld: string;
begin
  Result := nil;
  for VCol in FLive.Columns do
  begin
    VName := VCol.Name;
    for VRename in FOptions.Renames do
      if SameText(VRename.OldName, VCol.Name) then
        VName := VRename.NewName;
    Result := Result + [VName];
  end;
  for VRepoCol in FRepo.Columns do
    if (not FLive.FindColumn(VRepoCol.Name, VCol)) and not RenameTo(VRepoCol.Name, VOld) then
      Result := Result + [VRepoCol.Name];
end;

{ The domain a repository column is declared with. False + pReason = it cannot be used. }
function TAlterPlanner.DomainOf(const pCol: TFrRepoColumn; out pDomain: TFrDomainFacts; out pInLive: Boolean;
  out pReason: string): Boolean;
var
  VItem, VLive: TFrDomainFacts;
  VInRepo: Boolean;
begin
  pReason := '';
  pDomain := Default(TFrDomainFacts);
  VInRepo := False;
  for VItem in FRepo.Domains do
    if SameText(VItem.Name, pCol.DomainName) then
    begin
      pDomain := VItem;
      VInRepo := True;
    end;
  pInLive := FLive.FindDomain(pCol.DomainName, VLive);
  if not VInRepo and not pInLive then
    pReason := Reason(BLOCK_DOMAIN, Format('domain %s is neither in the repository nor in the database', [pCol.DomainName]))
  else if VInRepo and pInLive and (not SameType(pDomain.DataType, VLive.DataType) or (pDomain.NotNull <> VLive.NotNull)
    or (pDomain.CheckSource <> VLive.CheckSource)) then
    pReason := Reason(BLOCK_DOMAIN, Format('domain %s differs between the repository and the database; ALTER DOMAIN ' +
      'touches other tables and is not done here', [pCol.DomainName]))
  else if pInLive then
    pDomain := VLive;
  if (pReason = '') and not SameType(pDomain.DataType, pCol.DataType) then
    pReason := Reason(BLOCK_INCONSISTENT, Format('%s is declared with domain %s (%s) but its row says %s: give it ' +
      'another DOMAIN_NAME', [pCol.Name, pCol.DomainName, TypeText(pDomain.DataType, ''), TypeText(pCol.DataType, '')]));
  Result := pReason = '';
end;

{ A character column whose length the repository knows in bytes only: a DDL length is in characters. }
function LengthReason(const pCol: TFrRepoColumn): string;
begin
  Result := if (pCol.DomainName = '') and IsChar(pCol.DataType) and (pCol.DataType.CharLength <= 0) then
    Reason(BLOCK_INCONSISTENT, 'the row holds no character length (CHAR_LENGTH, STRING_SIZE)') else '';
end;

{ What hangs on a column: every type change and every drop of such a column is blocked. }
function TAlterPlanner.ObjectReasons(const pColumn: string): TArray<string>;
var
  VDep: TFrDependency;
  VKey: TFrKeyFacts;
begin
  Result := nil;
  for VDep in FLive.Dependencies do
    if SameText(VDep.ColumnName, pColumn) then
      case VDep.Kind of
        fdkComputed: Result := Result + [Reason(BLOCK_COMPUTED, 'a computed column uses it')];
        fdkCheck: Result := Result + [Reason(BLOCK_CONSTRAINT, 'check ' + VDep.DependentName + ' uses it')];
        fdkExpressionIndex: Result := Result + [Reason(BLOCK_INDEX, 'expression index ' + VDep.DependentName + ' uses it')];
      else
        Result := Result + [Reason(BLOCK_DEPENDENCY, VDep.KindText + ' ' + VDep.DependentName + ' uses it')];
      end;
  for VKey in FLive.Keys do
    if HasText(VKey.Columns, pColumn) then
      Result := Result + [if VKey.Kind = KIND_INDEX then Reason(BLOCK_INDEX, 'index ' + VKey.Name)
        else Reason(BLOCK_CONSTRAINT, VKey.Kind + ' ' + VKey.Name)];
end;

procedure TAlterPlanner.PlanDomains;
var
  VCol: TFrRepoColumn;
  VDomain: TFrDomainFacts;
  VInLive: Boolean;
  VReason: string;
  VChange: TFrAlterChange;
begin
  for VCol in FRepo.Columns do
    if (VCol.DomainName <> '') and (IdOf(fakCreateDomain, VCol.DomainName) = 0) and
      DomainOf(VCol, VDomain, VInLive, VReason) and not VInLive then
    begin
      VChange := NewChange(fakCreateDomain, fcoInsert, VCol.DomainName, '', '', TypeText(VDomain.DataType, ''));
      VChange.Change.Target := 'domain ' + VCol.DomainName;
      VChange.Ddl := [FDialect.CreateDomain(VDomain)];
      if FDialect.TypeClause(VDomain.DataType, True) = '' then
        VChange.Change.Blocked := Reason(BLOCK_UNSUPPORTED, 'the domain type cannot be written as DDL');
      AddChange(VChange);
    end;
end;

procedure TAlterPlanner.PlanRenames;
var
  VRename: TFrRename;
  VChange: TFrAlterChange;
  VReason: string;
  VDep: TFrDependency;
  VKey: TFrKeyFacts;
begin
  for VRename in FOptions.Renames do
  begin
    VChange := NewChange(fakRename, fcoUpdate, VRename.NewName, 'NAME', VRename.OldName, VRename.NewName);
    VChange.Change.Target := FRepo.TableName + '.' + VRename.OldName;
    VChange.Ddl := [FDialect.RenameColumn(FRepo.TableName, VRename.OldName, VRename.NewName)];
    VReason := NO_HARD_REASON;
    for VDep in FLive.Dependencies do
      if (VReason = '') and SameText(VDep.ColumnName, VRename.OldName) then
        VReason := Reason(BLOCK_DEPENDENCY, VDep.KindText + ' ' + VDep.DependentName + ' uses it');
    { Firebird 4 renames an indexed column but refuses one in a key constraint }
    for VKey in FLive.Keys do
      if (VReason = '') and (VKey.Kind <> KIND_INDEX) and HasText(VKey.Columns, VRename.OldName) then
        VReason := Reason(BLOCK_CONSTRAINT, VKey.Kind + ' ' + VKey.Name);
    VChange.Change.Blocked := VReason;
    AddChange(VChange);
  end;
end;

procedure TAlterPlanner.PlanTypes;
var
  VCol: TFrRepoColumn;
  VLive: TFrColumnFacts;
  VOld: string;
begin
  for VCol in FRepo.Columns do
  begin
    if not RenameTo(VCol.Name, VOld) then
      VOld := VCol.Name;
    if FLive.FindColumn(VOld, VLive) then
      PlanType(VCol, VLive);
  end;
end;

function VerdictReason(pVerdict: TFrTypeVerdict; const pOld, pNew: string): string;
begin
  case pVerdict of
    tvShrink: Result := Reason(BLOCK_SHRINK, Format('Firebird refuses to shrink %s to %s', [pOld, pNew]));
    tvLossy: Result := Reason(BLOCK_LOSSY, Format('Firebird would accept %s to %s and lose data', [pOld, pNew]));
    tvConvert: Result := Reason(BLOCK_CONVERSION, Format('%s to %s is not a widening', [pOld, pNew]));
    tvUnsupported: Result := Reason(BLOCK_UNSUPPORTED, Format('%s to %s is not handled', [pOld, pNew]));
  else
    Result := '';
  end;
end;

procedure TAlterPlanner.PlanType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts);
var
  VTarget: TFrTypeFacts;
  VDomain: TFrDomainFacts;
  VInLive: Boolean;
  VDomainReason: string;
  VVerdict: TFrTypeVerdict;
  VHard: TArray<string>;
  VChange: TFrAlterChange;
begin
  VTarget := pCol.DataType;
  VDomain := Default(TFrDomainFacts);
  VDomainReason := '';
  if pCol.DomainName <> '' then
    DomainOf(pCol, VDomain, VInLive, VDomainReason);
  VVerdict := TypeVerdict(pLive.DataType, VTarget);
  if (VVerdict = tvSame) and (pCol.Inconsistent = '') and
    ((pCol.DomainName = '') or SameText(pCol.DomainName, pLive.DomainName)) and (VDomainReason = '') then
    Exit;
  VHard := ObjectReasons(pLive.Name);
  if pCol.Inconsistent <> '' then
    VHard := VHard + [Reason(BLOCK_INCONSISTENT, pCol.Inconsistent)];
  if VDomainReason <> '' then
    VHard := VHard + [VDomainReason];
  if pLive.ComputedSource <> '' then
    VHard := VHard + [Reason(BLOCK_COMPUTED, 'it is a COMPUTED BY column')];
  if pLive.IsIdentity then
    VHard := VHard + [Reason(BLOCK_IDENTITY, 'it is an identity column')];
  if (pCol.DomainName = '') and (pLive.DomainName <> '') then
    VHard := VHard + [Reason(BLOCK_DOMAIN, Format('the column uses domain %s, the repository names none: the domain ' +
      'would be lost', [pLive.DomainName]))];
  if (VDomain.CheckSource <> '') then
    VHard := VHard + [Reason(BLOCK_DOMAIN, Format('domain %s has a CHECK that existing rows are not tested against',
      [VDomain.Name]))];
  if IsChar(VDomain.DataType) and (VDomain.DataType.Charset <> '') and (pLive.DataType.Charset <> '') and
    not SameText(VDomain.DataType.Charset, pLive.DataType.Charset) then
    VHard := VHard + [Reason(BLOCK_CHARSET, Format('%s to %s', [pLive.DataType.Charset, VDomain.DataType.Charset]))];
  if (VVerdict <> tvSame) and (LengthReason(pCol) <> '') then
    VHard := VHard + [LengthReason(pCol)];
  if FDialect.TypeClause(VTarget, False) = '' then
    VHard := VHard + [Reason(BLOCK_UNSUPPORTED, 'the type cannot be written as DDL')];
  if VVerdict = tvUnsupported then
    VHard := VHard + [VerdictReason(VVerdict, TypeText(pLive.DataType, ''), TypeText(VTarget, ''))];
  if (VVerdict in [tvSame, tvWiden]) and (Length(VHard) = 0) then
    PlanDirectType(pCol, pLive, VTarget, VDomain, VVerdict)
  else if FOptions.SafePath and (VVerdict in [tvShrink, tvLossy, tvConvert]) then
    PlanSafeType(pCol, pLive, VTarget, VDomain, VHard)
  else
  begin
    VChange := NewChange(fakType, fcoUpdate, pCol.Name, 'TYPE', TypeText(pLive.DataType, pLive.DomainName),
      TypeText(VTarget, pCol.DomainName));
    if VVerdict in [tvShrink, tvLossy, tvConvert] then
    begin
      VHard := [VerdictReason(VVerdict, TypeText(pLive.DataType, ''), TypeText(VTarget, ''))] + VHard;
      if (Length(VHard) = 1) and (Length(SafeReasons(pCol.Name, pLive, VTarget, VDomain)) = 0) then
        VHard[0] := VHard[0] + SAFE_HINT;
    end;
    VChange.Change.Blocked := string.Join('; ', VHard);
    AddChange(VChange);
  end;
end;

procedure TAlterPlanner.PlanDirectType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
  const pDomain: TFrDomainFacts; pVerdict: TFrTypeVerdict);
var
  VChange: TFrAlterChange;
  VText: string;
  VDependency: Integer;
begin
  VChange := NewChange(fakType, fcoUpdate, pCol.Name, 'TYPE', TypeText(pLive.DataType, pLive.DomainName),
    TypeText(pTarget, pCol.DomainName));
  { no CHARACTER SET here: Firebird 4 keeps the column's character set and collation when the clause is absent }
  VText := if pCol.DomainName <> '' then FDialect.QuoteIdent(pCol.DomainName) else FDialect.TypeClause(pTarget, False);
  VChange.Ddl := [FDialect.AlterType(FRepo.TableName, pCol.Name, VText)];
  VChange.ExpectType := pTarget;
  { a NOT NULL only the old domain gave goes away with it; dropping a NOT NULL is never a side effect }
  if pLive.DomainNotNull and not pLive.ColumnNotNull and not pDomain.NotNull then
  begin
    VChange.Ddl := VChange.Ddl + [FDialect.SetNotNull(FRepo.TableName, pCol.Name, True)];
    if fdcSetNotNull not in FDialect.Capabilities then
      VChange.Change.Blocked := Reason(BLOCK_DIALECT, FDialect.Name + ' cannot keep the NOT NULL of domain ' + pLive.DomainName);
  end;
  if pDomain.NotNull and not pLive.NotNull then
    VChange.Prechecks := [Precheck(FDialect.CountNulls(FRepo.TableName, pLive.Name), BLOCK_NULLS,
      '%d row(s) are NULL and the domain is NOT NULL')];
  if pVerdict = tvSame then
    VChange.Notes := ['only the domain changes; the type stays'];
  for VDependency in [IdOf(fakCreateDomain, pCol.DomainName), IdOf(fakRename, pCol.Name)] do
    if VDependency > 0 then
      VChange.DependsOn := VChange.DependsOn + [VDependency];
  AddChange(VChange);
end;

{ pColumn = the column's name after the changes: the temporary name is made from it }
function TAlterPlanner.SafeReasons(const pColumn: string; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
  const pDomain: TFrDomainFacts): TArray<string>;
var
  VOther: TFrColumnFacts;
  VTemp: string;
begin
  Result := nil;
  VTemp := pColumn + TEMP_SUFFIX;
  if fdcSafePath not in FDialect.Capabilities then
    Result := Result + [Reason(BLOCK_DIALECT, FDialect.Name + ' has no safe path')];
  if pLive.HasColumnGrants then
    Result := Result + [Reason(BLOCK_GRANTS, 'the column has its own GRANTs; they would be lost')];
  if Length(FLive.UpdateTriggers) > 0 then
    Result := Result + [Reason(BLOCK_TRIGGERS, 'the copy would fire ' + string.Join(', ', FLive.UpdateTriggers))];
  if FLive.FindColumn(VTemp, VOther) then
    Result := Result + [Reason(BLOCK_TEMP_NAME, VTemp + ' already exists (left by an interrupted run?)')]
  else if HasText(FinalNames, VTemp) then
    Result := Result + [Reason(BLOCK_TEMP_NAME, VTemp + ' is a column of the planned table')];
  if Length(VTemp) > FDialect.MaxIdentifier then
    Result := Result + [Reason(BLOCK_TEMP_NAME, VTemp + ' is longer than an identifier may be')];
  if (pLive.DefaultSource <> '') and not ((IsChar(pLive.DataType) and IsChar(pTarget)) or
    (IsNumber(pLive.DataType) and IsNumber(pTarget))) then
    Result := Result + [Reason(BLOCK_DEFAULT, 'the column has ' + pLive.DefaultSource + ', which may not fit the new type')];
  if pDomain.NotNull then
    Result := Result + [Reason(BLOCK_DOMAIN, Format('domain %s is NOT NULL: the copy cannot start empty', [pDomain.Name]))];
end;

{ The type the copy gets: text keeps the character set and collation of the old column. }
function CopyType(const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts): TFrTypeFacts;
begin
  Result := pTarget;
  if IsChar(pTarget) and IsChar(pLive.DataType) then
  begin
    Result.Charset := pLive.DataType.Charset;
    Result.Collation := pLive.DataType.Collation;
  end;
end;

{ pTarget = the CopyType }
function TAlterPlanner.BuildSafeSteps(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts;
  const pTarget: TFrTypeFacts): TFrSafeSteps;
var
  VTable, VDefinition: string;
begin
  VTable := FRepo.TableName;
  Result := Default(TFrSafeSteps);
  Result.Column := pCol.Name;
  Result.TempColumn := pCol.Name + TEMP_SUFFIX;
  VDefinition := if pCol.DomainName <> '' then FDialect.QuoteIdent(pCol.DomainName) else FDialect.TypeClause(pTarget, True);
  if (pCol.DomainName = '') and (pTarget.Collation <> '') then
    VDefinition := VDefinition + ' COLLATE ' + FDialect.QuoteIdent(pTarget.Collation);
  Result.AddSql := FDialect.AddColumn(VTable, Result.TempColumn, VDefinition);
  Result.CopySql := FDialect.CopyColumn(VTable, pCol.Name, Result.TempColumn, pTarget);
  Result.MismatchSql := FDialect.CountMismatches(VTable, pCol.Name, Result.TempColumn, pLive.DataType, pTarget);
  Result.CleanupSql := FDialect.DropColumn(VTable, Result.TempColumn);
  Result.SwapSql := [FDialect.DropColumn(VTable, pCol.Name), FDialect.RenameColumn(VTable, Result.TempColumn, pCol.Name)];
  if fdcColumnPosition in FDialect.Capabilities then
    Result.SwapSql := Result.SwapSql + [FDialect.SetPosition(VTable, pCol.Name, pLive.Position + 1)];
  if pLive.NotNull then
    Result.SwapSql := Result.SwapSql + [FDialect.SetNotNull(VTable, pCol.Name, True)];
  if pLive.DefaultSource <> '' then
    Result.SwapSql := Result.SwapSql + [FDialect.SetDefault(VTable, pCol.Name, pLive.DefaultSource)];
  if pLive.Description <> '' then
    Result.SwapSql := Result.SwapSql + [FDialect.CommentColumn(VTable, pCol.Name, pLive.Description)];
end;

procedure TAlterPlanner.PlanSafeType(const pCol: TFrRepoColumn; const pLive: TFrColumnFacts; const pTarget: TFrTypeFacts;
  const pDomain: TFrDomainFacts; const pHard: TArray<string>);
var
  VChange: TFrAlterChange;
  VReasons: TArray<string>;
  VCopy: TFrTypeFacts;
  VDependency: Integer;
begin
  VChange := NewChange(fakSafeType, fcoUpdate, pCol.Name, 'TYPE', TypeText(pLive.DataType, pLive.DomainName),
    TypeText(pTarget, pCol.DomainName));
  VChange.Change.Checked := False;
  VChange.ExpectType := pTarget;
  VReasons := pHard + SafeReasons(pCol.Name, pLive, pTarget, pDomain);
  if Length(VReasons) > 0 then
    VChange.Change.Blocked := string.Join('; ', VReasons)
  else
  begin
    VCopy := CopyType(pLive, pTarget);
    VChange.Safe := BuildSafeSteps(pCol, pLive, VCopy);
    VChange.Notes := ['safe path: ADD, COPY and SWAP are three separate transactions; the old column is dropped only ' +
      'after every row was compared'];
    VChange.Prechecks := [
      Precheck(FDialect.CountCastFailures(FRepo.TableName, pLive.Name, VCopy), BLOCK_CAST, '%d value(s) do not fit the new type'),
      Precheck(FDialect.CountLosses(FRepo.TableName, pLive.Name, pLive.DataType, VCopy), BLOCK_LOSS, '%d value(s) would change')];
    for VDependency in [IdOf(fakCreateDomain, pCol.DomainName), IdOf(fakRename, pCol.Name)] do
      if VDependency > 0 then
        VChange.DependsOn := VChange.DependsOn + [VDependency];
  end;
  FSafe := FSafe + [VChange];
end;

procedure TAlterPlanner.PlanNullability;
var
  VCol: TFrRepoColumn;
  VLive: TFrColumnFacts;
  VOld: string;
  VChange, VSafe: TFrAlterChange;
  VPending: Boolean;
begin
  for VCol in FRepo.Columns do
  begin
    if not RenameTo(VCol.Name, VOld) then
      VOld := VCol.Name;
    if not FLive.FindColumn(VOld, VLive) or (VCol.NotNull = VLive.NotNull) or FLive.IsPrimaryKey(VLive.Name) then
      Continue;
    VChange := NewChange(fakNullability, fcoUpdate, VCol.Name, 'NULLABILITY',
      if VLive.NotNull then TEXT_NOT_NULL else TEXT_NULL, if VCol.NotNull then TEXT_NOT_NULL else TEXT_NULL);
    VChange.Ddl := [FDialect.SetNotNull(FRepo.TableName, VCol.Name, VCol.NotNull)];
    VPending := False;
    for VSafe in FSafe do
      VPending := VPending or SameText(VSafe.Column, VCol.Name);
    if VCol.NotNull then
      VChange.Prechecks := [Precheck(FDialect.CountNulls(FRepo.TableName, VLive.Name), BLOCK_NULLS, '%d row(s) are NULL')]
    else
    begin
      VChange.Change.Checked := False;
      VChange.Notes := ['weak evidence: refresh-schema stores the domain''s NOT NULL only, not the column''s own'];
    end;
    if fdcSetNotNull not in FDialect.Capabilities then
      VChange.Change.Blocked := Reason(BLOCK_DIALECT, FDialect.Name + ' cannot change NOT NULL')
    else if VLive.ComputedSource <> '' then
      VChange.Change.Blocked := Reason(BLOCK_COMPUTED, 'it is a COMPUTED BY column')
    else if VLive.IsIdentity then
      VChange.Change.Blocked := Reason(BLOCK_IDENTITY, 'it is an identity column')
    else if VLive.DomainNotNull then
      VChange.Change.Blocked := Reason(BLOCK_DOMAIN, Format('NOT NULL comes from domain %s', [VLive.DomainName]))
    else if VPending then
      VChange.Change.Blocked := Reason(BLOCK_PENDING, 'apply the type change first, then run again');
    if IdOf(fakRename, VCol.Name) > 0 then
      VChange.DependsOn := [IdOf(fakRename, VCol.Name)];
    AddChange(VChange);
  end;
end;

procedure TAlterPlanner.PlanAdds;
var
  VCol: TFrRepoColumn;
  VLive: TFrColumnFacts;
  VDomain: TFrDomainFacts;
  VInLive, VHasDefault: Boolean;
  VOld, VDefinition, VReason: string;
  VChange: TFrAlterChange;
begin
  for VCol in FRepo.Columns do
  begin
    if FLive.FindColumn(VCol.Name, VLive) or RenameTo(VCol.Name, VOld) then
      Continue;
    VReason := if VCol.Inconsistent <> '' then Reason(BLOCK_INCONSISTENT, VCol.Inconsistent) else '';
    VDomain := Default(TFrDomainFacts);
    VChange := NewChange(fakAdd, fcoInsert, VCol.Name, '', '', TypeText(VCol.DataType, VCol.DomainName));
    VChange.ExpectType := VCol.DataType;
    if (VCol.DomainName <> '') and (VReason = '') then
      DomainOf(VCol, VDomain, VInLive, VReason);
    VDefinition := if VCol.DomainName <> '' then FDialect.QuoteIdent(VCol.DomainName) else FDialect.TypeClause(VCol.DataType, True);
    if VReason = '' then
      VReason := LengthReason(VCol);
    if (VReason = '') and (FDialect.TypeClause(VCol.DataType, False) = '') then
      VReason := Reason(BLOCK_UNSUPPORTED, 'the type cannot be written as DDL');
    VHasDefault := VDomain.DefaultSource <> '';
    if IsPlainDefault(VCol.DefaultValue) then
    begin
      VDefinition := VDefinition + ' DEFAULT ' + Trim(VCol.DefaultValue);
      VHasDefault := True;
      VChange.Change.NewValue := VChange.Change.NewValue + ' DEFAULT ' + Trim(VCol.DefaultValue);
    end
    else if VCol.DefaultValue <> '' then
      VChange.Notes := ['DEFAULTVAL is not a plain literal and is not used: ' + VCol.DefaultValue];
    if VCol.NotNull and not VDomain.NotNull then
      VDefinition := VDefinition + ' NOT NULL';
    if VCol.NotNull or VDomain.NotNull then
    begin
      VChange.Change.NewValue := VChange.Change.NewValue + ' NOT NULL';
      if not VHasDefault then
        VChange.Prechecks := [Precheck(FDialect.CountRows(FRepo.TableName), BLOCK_ROWS,
          '%d existing row(s) would have no value for a NOT NULL column without default')];
    end;
    VChange.Ddl := [FDialect.AddColumn(FRepo.TableName, VCol.Name, VDefinition)];
    if IdOf(fakCreateDomain, VCol.DomainName) > 0 then
      VChange.DependsOn := [IdOf(fakCreateDomain, VCol.DomainName)];
    VChange.Change.Blocked := VReason;
    AddChange(VChange);
  end;
end;

procedure TAlterPlanner.PlanDrops;
var
  VLive: TFrColumnFacts;
  VChange: TFrAlterChange;
begin
  for VLive in FLive.Columns do
  begin
    if IsRepoName(VLive.Name) or IsRenameSource(VLive.Name) then
      Continue;
    VChange := NewChange(fakDrop, fcoDelete, VLive.Name, '', TypeText(VLive.DataType, VLive.DomainName), '');
    VChange.Change.Checked := False;
    VChange.Ddl := [FDialect.DropColumn(FRepo.TableName, VLive.Name)];
    VChange.Change.Blocked := string.Join('; ', ObjectReasons(VLive.Name));
    if VLive.ComputedSource = '' then
      VChange.Prechecks := [Precheck(FDialect.CountValues(FRepo.TableName, VLive.Name), '', '%d value(s) would be lost')];
    AddChange(VChange);
  end;
end;

procedure TAlterPlanner.PlanOrder;
var
  VFinal, VWanted: TArray<string>;
  VName: string;
  VChange: TFrAlterChange;
  i: Integer;
begin
  if Length(FOptions.Order) = 0 then
    Exit;
  VFinal := FinalNames;
  VWanted := nil;
  for VName in FOptions.Order do
    VWanted := VWanted + [VName.ToUpper];
  for VName in VFinal do
    if not HasText(VWanted, VName) then
      VWanted := VWanted + [VName];
  if SameText(string.Join(',', VFinal), string.Join(',', VWanted)) then
    Exit;
  VChange := NewChange(fakOrder, fcoUpdate, '', 'ORDER', string.Join(',', VFinal), string.Join(',', VWanted));
  VChange.Change.Target := FRepo.TableName + ' ' + ORDER_TARGET;
  if fdcColumnPosition not in FDialect.Capabilities then
    VChange.Change.Blocked := Reason(BLOCK_DIALECT, FDialect.Name + ' cannot move a column');
  for i := 0 to High(FOptions.Order) do
  begin
    VName := VWanted[i];
    VChange.Ddl := VChange.Ddl + [FDialect.SetPosition(FRepo.TableName, VName, i + 1)];
    if IdOf(fakAdd, VName) > 0 then
      VChange.DependsOn := VChange.DependsOn + [IdOf(fakAdd, VName)];
    if IdOf(fakRename, VName) > 0 then
      VChange.DependsOn := VChange.DependsOn + [IdOf(fakRename, VName)];
  end;
  AddChange(VChange);
end;

function TAlterPlanner.Run: TFrAlterPlan;
var
  VSafe: TFrAlterChange;
begin
  FPlan := Default(TFrAlterPlan);
  FPlan.TableName := FRepo.TableName;
  FPlan.DialectName := FDialect.Name;
  FPlan.LiveFingerprint := LiveFingerprint(FLive);
  CheckRequest;
  PlanDomains;
  PlanRenames;
  PlanTypes;
  PlanNullability;
  PlanAdds;
  PlanDrops;
  for VSafe in FSafe do
    AddChange(VSafe);
  PlanOrder;
  Result := FPlan;
end;

function PlanAlter(const pRepo: TFrRepoTable; const pLive: TFrTableFacts; const pOptions: TFrAlterOptions;
  const pDialect: IFrDbDialect): TFrAlterPlan;
var
  VPlanner: TAlterPlanner;
begin
  VPlanner := Default(TAlterPlanner);
  VPlanner.FRepo := pRepo;
  VPlanner.FLive := pLive;
  VPlanner.FOptions := pOptions;
  VPlanner.FDialect := pDialect;
  Result := VPlanner.Run;
end;

end.
