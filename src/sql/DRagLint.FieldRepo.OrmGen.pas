unit DRagLint.FieldRepo.OrmGen;  // dl:ok unit-too-large@1be3 -- REVIEWED 2026-11-17 v152 TTGEN: holds the whole TableTools generator set ported line for line; output must stay byte-identical

{ drag-lint 1.52 -- lane TTGEN: ORM source generation from a field repository.

  Port of TableTools FieldsInfo.Model.pas (GenerateNewTableObject, GenerateNewServerObject,
  GenerateNewClientObject, GenerateSection1..15 / 1A / 2I / 2P / 8A / 9A, GenerateCLSection*,
  IsRegionStart / IsRegionEnd / UpdateFileRegions). The section generators are carried over
  line for line so their output stays byte-identical; what changed is only where the
  field list comes from: DL_FIELDS_INFO in the repository instead of FIB$FIELDS_INFO plus
  the live RDB$ index and generator queries (decisions in the lane report):
  * key fields = rows with PRIMARY_KEY set (TableTools: RDB$ PRIMARY KEY segments);
  * a key has a generator when its SEQUENCE_NAME is filled; the generator name is still
    'GEN_' + table + '_' + field, as TableTools built it;
  * tables = the distinct TABLE_NAME values of DL_FIELDS_INFO.
  Region update (repo update-orm) rewrites ONLY the lines between a DB-RAD region start and
  its end; every other byte of the file, line ends included, is kept as it was. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  FireDAC.Comp.Client;

const
  /// <summary>File-name prefix of a generated implementation unit (TableTools ORM_PAS_PREFIX).</summary>
  ORM_PAS_PREFIX = 'u';
  /// <summary>File-name prefix of a generated interface unit (TableTools ORM_INTF_PREFIX).</summary>
  ORM_INTF_PREFIX = 'i';
  /// <summary>Extension of every generated unit (TableTools writes upper case).</summary>
  ORM_FILE_EXT = '.PAS';

type
  /// <summary>Raised when a table has no rows in the repository or a file cannot be planned.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.FieldRepo.DataServiceGen.RunOrmGenVerb (DRagLint.FieldRepo.DataServiceGen.pas) ?, DRagLint.FieldRepo.OrmGen.CheckedTables (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField (DRagLint.FieldRepo.OrmGen.pas)</para>
  /// <para>Used in units: DRagLint.FieldRepo.DataServiceGen, DRagLint.FieldRepo.OrmGen</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EOrmGenError = class(Exception);

  /// <summary>One column of a table as the generators see it (a DL_FIELDS_INFO row,
  /// FIELD_KIND = 1, not calculated, not lookup).</summary>
  /// <remarks>
  /// Read-only after construction; owns its two documentation lists.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.OrmGen.pas) ?, DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create (DRagLint.FieldRepo.OrmGen.pas) ?, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas) ?, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField (DRagLint.FieldRepo.OrmGen.pas) ? (+22 more)</para>
  /// <para>Used in units: DRagLint.FieldRepo.OrmGen</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmField = class
  private
    FFieldName: string;
    FVarType: string;
    FFieldAsType: string;
    FEnumType: string;
    FDefaultVal: string;
    FIsEnum: Boolean;
    FFieldSize: Integer;
    FDocSummary: TStringList;
    FDocRemarks: TStringList;
  public
    /// <summary>Builds a field from repository values.</summary>
    /// <param name="pFieldName">FIELD_NAME, may contain '$'.</param>
    /// <param name="pVarType">VAR_TYPE (Delphi type of the property).</param>
    /// <param name="pFieldAsType">FIELD_AS_TYPE (TField accessor, e.g. AsInteger).</param>
    /// <param name="pEnumType">ENUMTYPE; used when pIsEnum is True.</param>
    /// <param name="pDefaultVal">DEFAULTVAL text.</param>
    /// <param name="pIsEnum">ISENUM.</param>
    /// <param name="pFieldSize">FIELD_SIZE; 0 when NULL.</param>
    /// <param name="pDocSummary">DOC_SUMMARY text; split into lines like TStringList.Text.</param>
    /// <param name="pDocRemarks">DOC_REMARKS text; split into lines like TStringList.Text.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>constructor</para>
    /// <para>Reads: FDocSummary, FDocRemarks   Writes: FFieldName, FVarType, FFieldAsType, FEnumType, FDefaultVal, FIsEnum, FFieldSize, FDocSummary (+1 more)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const pFieldName, pVarType, pFieldAsType, pEnumType, pDefaultVal: string;
      pIsEnum: Boolean; pFieldSize: Integer; const pDocSummary, pDocRemarks: string);
    /// <summary>Frees the documentation lists.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FDocSummary, FDocRemarks</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>FIELD_NAME with every '$' replaced by '_' (the Pascal identifier).</summary>
    /// <returns>The identifier form of the field name.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection1 (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection10 (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection11 (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection14 (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection15 (DRagLint.FieldRepo.OrmGen.pas) (+13 more)</para>
    /// <para>Returns: FFieldName.Replace('$', '_')</para>
    /// <para>Reads: FFieldName</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetCurrentFieldName: string;
    /// <summary>FIELD_NAME as stored.</summary>
    property FIELD_NAME: string read FFieldName;  // dl:ok property-accessor-name@bdba -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
    /// <summary>VAR_TYPE as stored.</summary>
    property VAR_TYPE: string read FVarType;  // dl:ok property-accessor-name@a78e -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
    /// <summary>FIELD_AS_TYPE as stored.</summary>
    property FIELD_AS_TYPE: string read FFieldAsType;  // dl:ok property-accessor-name@9cea -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
    /// <summary>ENUMTYPE as stored.</summary>
    property ENUMTYPE: string read FEnumType;
    /// <summary>DEFAULTVAL as stored.</summary>
    property DEFAULTVAL: string read FDefaultVal;
    /// <summary>ISENUM as stored.</summary>
    property ISENUM: Boolean read FIsEnum;
    /// <summary>FIELD_SIZE; 0 when NULL.</summary>
    property FIELD_SIZE: Integer read FFieldSize;  // dl:ok property-accessor-name@3101 -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
    /// <summary>DOC_SUMMARY lines; owned by the field.</summary>
    property DOC_SUMMARY: TStringList read FDocSummary;  // dl:ok property-accessor-name@7fcf -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
    /// <summary>DOC_REMARKS lines; owned by the field.</summary>
    property DOC_REMARKS: TStringList read FDocRemarks;  // dl:ok property-accessor-name@a9a7 -- REVIEWED 2026-11-17 v152 TTGEN: properties carry the DL_FIELDS_INFO column names so the ported generator code reads unchanged
  end;

  /// <summary>Generates ORM units (i/u/_SERVER/_CLIENT) for repository tables and
  /// regenerates the DB-RAD regions of existing ones.</summary>
  /// <remarks>Holds the field list of ONE table at a time (LoadTable); not thread-safe.
  /// Does not own the repository connection.</remarks>
  /// <summary>How region 9 (Save, _SERVER unit) binds its query parameters.</summary>
  /// <remarks>
  /// osfLegacy (the default, B33) = TableTools before 2026-05-19, the form the ORM3
  /// units carry: the FIELD_AS_TYPE accessor, .AsString for a TStringList, .AsByte for an enum,
  /// a timestamp without a NULL guard. osfCurrent = TableTools 2026-05-19: .Value, .AsWideMemo
  /// (FB-338), Set1Byte for an enum, Clear when the timestamp Year = 0.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.DataServiceGen.pas), declaration (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.PlanUpdateOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmSaveForm = (osfLegacy, osfCurrent);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.CheckedTables (DRagLint.FieldRepo.OrmGen.pas) ?, DRagLint.FieldRepo.OrmGen.PlanGenOrm (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.PlanUpdateOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
  /// <para>Used in units: DRagLint.FieldRepo.DataServiceGen, DRagLint.FieldRepo.OrmGen</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmGenerator = class  // dl:ok high-response@ce3d -- REVIEWED 2026-11-17 v152 TTGEN: one method per TableTools section generator, kept 1:1 with the source it ports
  private
    FRepo: TFDConnection;
    FFieldList: TObjectList<TOrmField>;
    FKeyFields: TList<string>;
    FKeyTypes: TList<string>;
    FKeyGens: TList<string>;
    FHasGenerator: Boolean;
    FGenName: string;
    FLoadedTable: string;
    FGuidProvider: TFunc<TGUID>;
    FSaveForm: TOrmSaveForm;
    /// <returns><!-- drag-lint:auto -->TGUID -- Observed: FGuidProvider().</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: CreateGUID, FGuidProvider</para>
    /// <para>Reads: FGuidProvider</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function NewGuid: TGUID;
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: AName.Replace('$', '_').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas) (+2 more)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetFieldName(const AName: string): string;
    /// <param name="pKeyField"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TOrmField -- Observed: F.</returns>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas) (+2 more)</para>
    /// <para>Reads: FFieldList, FLoadedTable</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LocateField(const pKeyField: string): TOrmField;
    /// <param name="AType"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection14 (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection15 (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsVarTypeCreatable(const AType: string): Boolean;
    /// <param name="InterfaceObject"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateInterfaceFooter(InterfaceObject: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection1(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.AccessorName, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.AccessorName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection1A(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.AccessorName, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.AccessorName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection2P(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.AccessorName, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.AccessorName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection2I(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.ZeroTime, Format, Trim</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 35 lines (full implementation)</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.ZeroTime"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection3(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection4(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection5(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection6(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableId"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.AccessorName, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.AccessorName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection7(SectionCode: TStringList; const TableId: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Complexity: 19 (cyclomatic, outer body), 66 lines (full implementation)</para>
    /// <para>Reads: FKeyFields, FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection8(SectionCode: TStringList; TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.ToLiteral, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, Format</para>
    /// <para>Reads: FKeyFields, FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.ToLiteral"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection8A(SectionCode: TStringList; TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Complexity: 26 (cyclomatic, outer body), 79 lines (full implementation)</para>
    /// <para>Reads: FKeyFields, FKeyGens, FFieldList, FSaveForm</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection9(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.ToLiteral, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Reads: FKeyFields, FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.ToLiteral"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection9A(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Complexity: 19 (cyclomatic, outer body), 86 lines (full implementation)</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection10(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, Format</para>
    /// <para>Complexity: 19 (cyclomatic, outer body), 86 lines (full implementation)</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection11(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.IsVarTypeCreatable, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.IsVarTypeCreatable"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection14(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.IsVarTypeCreatable, Format</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.IsVarTypeCreatable"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateSection15(SectionCode: TStringList);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Reads: FKeyFields</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateCLSectionKEY(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Reads: FKeyFields</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateCLSectionLOAD(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Reads: FKeyFields</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateCLSectionSAVE(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <exception cref="EOrmGenError"><!-- drag-lint:auto exc -->via DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField: Table &lt;%s&gt; key field &lt;%s&gt; is missing</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format</para>
    /// <para>Reads: FKeyFields</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateCLSectionDEL(SectionCode: TStringList; const TableName0: string);
    /// <param name="SectionCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <param name="TableName0"><!-- drag-lint:auto type -->const string</param>
    /// <param name="HasGenerator"><!-- drag-lint:auto type -->Boolean</param>
    /// <param name="GenName"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: Format</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateCLSectionNEXTID(SectionCode: TStringList; const TableName0: string; HasGenerator: Boolean; const GenName: string);
    /// <summary><!-- drag-lint:auto sum -->TableTools UpdateFileRegions: the per-id
    /// dispatch. Ids 12 and 13 fall through to "nothing" on purpose: TableTools'
    /// GenerateSection12 / 13 only build a string they never add (the lines that used it
    /// are commented out there), so both regions come out empty.</summary>
    /// <param name="pRegionId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="pIsInterface"><!-- drag-lint:auto type -->Boolean</param>
    /// <param name="pCode"><!-- drag-lint:auto type -->TStringList</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.UpdateRegions (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionNEXTID, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection1, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection10, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection11, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection14, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection15 (+12 more)</para>
    /// <para>Complexity: 23 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <para>Reads: FLoadedTable, FHasGenerator, FGenName</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionNEXTID"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateRegion(const pRegionId: string; pIsInterface: Boolean; pCode: TStringList);
  public
    /// <summary>Creates a generator over an open repository.</summary>
    /// <param name="pRepo">Open repository connection (OpenRepository); not owned; must outlive the generator.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.PlanGenOrm (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.PlanUpdateOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FRepo, FFieldList, FKeyFields, FKeyTypes, FKeyGens</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(pRepo: TFDConnection);
    /// <summary>Frees the field and key lists.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FKeyGens, FKeyTypes, FKeyFields, FFieldList</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>The tables the repository describes: distinct DL_FIELDS_INFO.TABLE_NAME, ordered.</summary>
    /// <returns>Table names as stored (may contain '$').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.CheckedTables (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Returns: L.ToArray</para>
    /// <para>Reads: FRepo</para>
    /// <para>SQL: reads DL_FIELDS_INFO</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TableNames: TArray<string>;
    /// <summary>Loads the generator field list of one table (TableTools BuildFieldList):
    /// rows with FIELD_KIND = 1 ordered by FIELD_NAME, calculated and lookup rows left out;
    /// key fields = PRIMARY_KEY rows; a key with a SEQUENCE_NAME has generator
    /// 'GEN_' + table + '_' + field.</summary>
    /// <param name="pTableName">Table name as stored in the repository.</param>
    /// <exception cref="EOrmGenError">The repository has no DL_FIELDS_INFO row at all for the table.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.PlanUpdateOrm (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewClientObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewServerObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.UpdateRegions (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmField.Create, DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName</para>
    /// <para>Reads: FFieldList, FKeyFields, FKeyTypes, FKeyGens, FRepo   Writes: FHasGenerator, FGenName, FLoadedTable</para>
    /// <para>SQL: reads DL_FIELDS_INFO</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmField.GetCurrentFieldName"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure LoadTable(const pTableName: string);
    /// <summary>Writes a new interface unit (i&lt;T&gt;) and implementation unit (u&lt;T&gt;)
    /// for a table (TableTools GenerateNewTableObject).</summary>
    /// <param name="TableName0">Table name as stored.</param>
    /// <param name="InterfaceObject">Receives the interface unit lines; not cleared.</param>
    /// <param name="PasObject">Receives the implementation unit lines; not cleared.</param>
    /// <exception cref="EOrmGenError">Unknown table.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.PlanGenOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateInterfaceFooter, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection1, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection10, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection11, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection14, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection15, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection1A, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection2I, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection2P, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection3 (+8 more)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateInterfaceFooter"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection1"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection10"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection11"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection14"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateNewTableObject(const TableName0: string; InterfaceObject, PasObject: TStringList);
    /// <summary>Writes a new server data-service unit (u&lt;T&gt;_SERVER) for a table.</summary>
    /// <param name="TableName0">Table name as stored.</param>
    /// <param name="PasObject">Receives the unit lines; not cleared.</param>
    /// <exception cref="EOrmGenError">Unknown table.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection8, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection8A, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection9, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection9A, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable, Format, SameText</para>
    /// <para>Reads: FGenName, FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection8"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection8A"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection9"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateSection9A"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateNewServerObject(const TableName0: string; PasObject: TStringList);
    /// <summary>Writes a new client data-service unit (u&lt;T&gt;_CLIENT) for a table.</summary>
    /// <param name="TableName0">Table name as stored.</param>
    /// <param name="PasObject">Receives the unit lines; not cleared.</param>
    /// <exception cref="EOrmGenError">Unknown table.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionNEXTID, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GetFieldName, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LocateField, Format, SameText</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 423 lines (full implementation)</para>
    /// <para>Reads: FHasGenerator, FGenName, FFieldList, FKeyFields</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionNEXTID"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionSAVE"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure GenerateNewClientObject(const TableName0: string; PasObject: TStringList);
    /// <summary>Regenerates every DB-RAD region of a unit's text for one table (TableTools
    /// UpdateFileRegions). Region ids 1, 1A, 2 (2I in an interface unit, 2P otherwise),
    /// 3..15, 8A, 9A, CL-KEY, CL-LOAD, CL-SAVE, CL-DEL, CL-NEXTID; an unknown id empties its
    /// region, as in TableTools. A start line without an end line keeps the rest of the file
    /// after the generated lines.</summary>
    /// <param name="pText">The unit text; any line-end style.</param>
    /// <param name="pTableName">Table name as stored.</param>
    /// <param name="pIsInterface">True for an i&lt;T&gt; unit (region 2 = interface form).</param>
    /// <param name="pRegionCount">Receives the number of DB-RAD regions found.</param>
    /// <returns>The new text: region start / end lines and every byte outside the regions are
    /// unchanged; generated lines end with CRLF.</returns>
    /// <exception cref="EOrmGenError">Unknown table.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.PlanUpdateOrm.One (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Calls: DRagLint.FieldRepo.OrmGen.IsOrmRegionEnd, DRagLint.FieldRepo.OrmGen.IsOrmRegionStart, DRagLint.FieldRepo.OrmGen.OrmJoinLines, DRagLint.FieldRepo.OrmGen.SplitRawLines, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable</para>
    /// <para>Returns: SB.ToString</para>
    /// <para>Reads: FLoadedTable</para>
    /// <para>Mutates: pRegionCount (out)</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.IsOrmRegionEnd"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.IsOrmRegionStart"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.OrmJoinLines"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.SplitRawLines"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateRegion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UpdateRegions(const pText, pTableName: string; pIsInterface: Boolean;
      out pRegionCount: Integer): string;
    /// <summary>Supplies the GUID of a new interface; nil = CreateGUID. Tests pin it.</summary>
    property GuidProvider: TFunc<TGUID> read FGuidProvider write FGuidProvider;
    /// <summary>Parameter binding form of region 9; osfLegacy unless set.</summary>
    property SaveForm: TOrmSaveForm read FSaveForm write FSaveForm;
    /// <summary>Number of generator fields of the loaded table (0 when every row of the table
    /// has a FIELD_KIND other than 1).</summary>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: FFieldList.Count.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.FieldRepo.OrmGen.PlanUpdateOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
    /// <para>Reads: FFieldList</para>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Destroy"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionDEL"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionKEY"/>
    /// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateCLSectionLOAD"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FieldCount: Integer;
  end;

  /// <summary>Kind of a planned file write.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.DataServiceGen.ReportPlan (DRagLint.FieldRepo.DataServiceGen.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmChangeKind = (ockNew, ockChanged, ockUnchanged);

  /// <summary>One file a generator verb would write.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.DataServiceGen.PlanVerb (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.DataServiceGen.ReportPlan (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.DataServiceGen.RunOrmGenVerb (DRagLint.FieldRepo.DataServiceGen.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.FieldRepo.DataServiceGen, DRagLint.FieldRepo.OrmGen</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmFileChange = record
    /// <summary>Full path of the file.</summary>
    FileName: string;
    /// <summary>New, changed or unchanged.</summary>
    Kind: TOrmChangeKind;
    /// <summary>Current file text ('' for a new file).</summary>
    OldText: string;
    /// <summary>Text the verb writes.</summary>
    NewText: string;
  end;

/// <summary>True when a line opens a DB-RAD region: a '{$REGION' whose name starts with
/// DB-RAD followed by an id (TableTools IsRegionStart accepted any name containing DB-RAD).</summary>
/// <param name="pLine">One source line without its line end.</param>
/// <param name="pRegionId">Receives the upper-case id ('2', '1A', 'CL-KEY'); '' when False.</param>
/// <returns>True for a '{$REGION 'DB-RAD &lt;id&gt;'}' line.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.OrmGen.TOrmGenerator.UpdateRegions (DRagLint.FieldRepo.OrmGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.RegionName</para>
/// <para>Returns: False; pRegionId &lt;&gt; ''</para>
/// <para>Mutates: pRegionId (out)</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.RegionName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsOrmRegionStart(const pLine: string; out pRegionId: string): Boolean;  // dl:ok unused-public-symbol@e22e -- REVIEWED 2026-11-17 v152 TTGEN: public API used by tests\fieldrepo\OrmGenTests.dpr and by CLI.Repo after the TTGEN handover

/// <summary>True when a line closes a DB-RAD region: a '{$ENDREGION' whose name starts with DB-RAD.</summary>
/// <param name="pLine">One source line without its line end.</param>
/// <returns>True for a '{$ENDREGION 'DB-RAD ...'}' line.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.OrmGen.OrmChangeDiff (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.UpdateRegions (DRagLint.FieldRepo.OrmGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.RegionName</para>
/// <para>Returns: RegionName(pLine, '{$ENDREGION').StartsWith(DB_RAD)</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.RegionName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsOrmRegionEnd(const pLine: string): Boolean;  // dl:ok unused-public-symbol@f4c6 -- REVIEWED 2026-11-17 v152 TTGEN: public API used by tests\fieldrepo\OrmGenTests.dpr and by CLI.Repo after the TTGEN handover

/// <summary>Plans repo update-orm: regenerates the DB-RAD regions of i&lt;T&gt;.PAS and
/// u&lt;T&gt;.PAS in pCodeDir, u&lt;T&gt;_SERVER.PAS in pServerDir and u&lt;T&gt;_CLIENT.PAS in
/// pClientDir for each table. A missing file is skipped and named in pSkipped; so is a table
/// without a FIELD_KIND = 1 row (TableTools would have emptied its regions).</summary>
/// <param name="pRepo">Open repository.</param>
/// <param name="pCodeDir">Folder of the i/u units (COMMON\OBJECTS).</param>
/// <param name="pServerDir">Folder of the _SERVER units; '' = skip them.</param>
/// <param name="pClientDir">Folder of the _CLIENT units; '' = skip them.</param>
/// <param name="pTables">Tables to update; empty = every repository table.</param>
/// <param name="pSkipped">Receives one line per file that does not exist; not cleared.</param>
/// <param name="pSaveForm">Region 9 parameter binding form (TOrmSaveForm).</param>
/// <returns>One entry per existing file, in table order (i, u, _SERVER, _CLIENT).</returns>
/// <exception cref="EOrmGenError">A named table is not in the repository.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanVerb (DRagLint.FieldRepo.DataServiceGen.pas)</para>
/// <para>Calls: ChangeOf, DRagLint.FieldRepo.OrmGen.CheckedTables, DRagLint.FieldRepo.OrmGen.PlanUpdateOrm.One, DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create, DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount, DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable, ReadUnitText</para>
/// <para>Returns: L.ToArray</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.CheckedTables"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.PlanUpdateOrm.One"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.FieldCount"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.LoadTable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanUpdateOrm(pRepo: TFDConnection; const pCodeDir, pServerDir, pClientDir: string;
  const pTables: TArray<string>; pSkipped: TStrings; pSaveForm: TOrmSaveForm = osfLegacy): TArray<TOrmFileChange>;

/// <summary>Plans writing one generated unit: compares the lines (joined with CRLF) with the
/// current file.</summary>
/// <param name="pFileName">Target file.</param>
/// <param name="pLines">The generated lines.</param>
/// <returns>ockNew when the file does not exist, else ockChanged / ockUnchanged.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanGenDataService (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.PlanGenOrm (DRagLint.FieldRepo.OrmGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.ChangeOf, DRagLint.FieldRepo.OrmGen.OrmJoinLines, DRagLint.FieldRepo.OrmGen.ReadUnitText</para>
/// <para>Returns: ChangeOf(pFileName, OldL, OrmJoinLines(pLines), Exists)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.ChangeOf"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.OrmJoinLines"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.ReadUnitText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OrmPlanFile(const pFileName: string; pLines: TStrings): TOrmFileChange;

/// <summary>Plans repo gen-orm: new i&lt;T&gt;.PAS and u&lt;T&gt;.PAS in pCodeDir per table.</summary>
/// <param name="pRepo">Open repository.</param>
/// <param name="pCodeDir">Target folder.</param>
/// <param name="pTables">Tables to generate; empty = every repository table.</param>
/// <param name="pGuidProvider">GUID source for the interfaces; nil = CreateGUID.</param>
/// <returns>Two entries per table (interface, implementation).</returns>
/// <exception cref="EOrmGenError">A named table is not in the repository.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.PlanVerb (DRagLint.FieldRepo.DataServiceGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.CheckedTables, DRagLint.FieldRepo.OrmGen.OrmPlanFile, DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create, DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject</para>
/// <para>Returns: L.ToArray</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.CheckedTables"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.OrmPlanFile"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.Create"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.TOrmGenerator.GenerateNewTableObject"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanGenOrm(pRepo: TFDConnection; const pCodeDir: string; const pTables: TArray<string>;
  const pGuidProvider: TFunc<TGUID>): TArray<TOrmFileChange>;

/// <summary>Writes every planned file whose Kind is not ockUnchanged as 7-bit ASCII
/// (TableTools TEncoding.ASCII); an existing file is first copied to &lt;file&gt;.BCK&lt;n&gt;
/// with the first free n (TableTools CreateBackupFile).</summary>
/// <param name="pChanges">The plan.</param>
/// <param name="pBackup">False skips the .BCKn copy.</param>
/// <returns>Number of files written.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.ReportPlan (DRagLint.FieldRepo.DataServiceGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.BackupFile, ExtractFilePath</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.BackupFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyOrmChanges(const pChanges: TArray<TOrmFileChange>; pBackup: Boolean): Integer;

/// <summary>Dry-run diff of one planned file: a '--- / +++' header and, for each changed
/// DB-RAD region (or the whole file when it is new), an '@@ line N @@' hunk with the old
/// lines prefixed '-' and the new ones '+'; lines a region keeps at its start or end are
/// left out of the hunk. Lines outside the regions that differ get a hunk of their own; a file
/// whose lines are equal but whose line ends differ gets '@@ line ends only @@'.</summary>
/// <param name="pChange">One planned file.</param>
/// <returns>'' for an unchanged file; else the diff text with CRLF line ends.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.ReportPlan (DRagLint.FieldRepo.DataServiceGen.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.OrmGen.IsOrmRegionEnd, DRagLint.FieldRepo.OrmGen.OrmChangeDiff.EmitHunk, DRagLint.FieldRepo.OrmGen.OrmSplitLines, Format</para>
/// <para>Returns: ''; SB.ToString</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 81 lines (full implementation)</para>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.IsOrmRegionEnd"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.OrmChangeDiff.EmitHunk"/>
/// <seealso cref="DRagLint.FieldRepo.OrmGen.OrmSplitLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OrmChangeDiff(const pChange: TOrmFileChange): string;

/// <summary>Splits text into lines like TStringList.Text (CR, LF and CRLF all end a line;
/// a final line end does not add an empty line).</summary>
/// <param name="pText">Any text.</param>
/// <returns>The lines without line ends.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.DataServiceGen.ReportPlan (DRagLint.FieldRepo.DataServiceGen.pas), DRagLint.FieldRepo.OrmGen.OrmChangeDiff (DRagLint.FieldRepo.OrmGen.pas)</para>
/// <para>Returns: SL.ToStringArray</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OrmSplitLines(const pText: string): TArray<string>;

/// <summary>Joins lines the way TStringList.SaveToFile does: every line followed by CRLF.</summary>
/// <param name="pLines">The lines.</param>
/// <returns>The text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FieldRepo.OrmGen.OrmPlanFile (DRagLint.FieldRepo.OrmGen.pas), DRagLint.FieldRepo.OrmGen.TOrmGenerator.UpdateRegions (DRagLint.FieldRepo.OrmGen.pas)</para>
/// <para>Returns: SB.ToString</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OrmJoinLines(const pLines: TStrings): string;  // dl:ok unused-public-symbol@f84e -- REVIEWED 2026-11-17 v152 TTGEN: public API used by tests\fieldrepo\OrmGenTests.dpr and by CLI.Repo after the TTGEN handover

implementation

uses
  System.IOUtils,
  Data.DB,
  FireDAC.Stan.Param;

const
  STPicture = 'TABZMemoryStream';
  CreatableTypes: array [0 .. 1] of string = (STPicture, 'TStringList');
  { TableTools ToLiteral: longest literal kept on one line. }
  MAX_LITERAL_CHUNK = 254;
  { TableTools column widths: PadRight of a field name / of a type name }
  PAD_NAME = 25;
  PAD_TYPE = 10;
  DB_RAD = 'DB-RAD';
  { opening of the VALUES list of section 9A (TableTools tested Length > 9; after the first
    ':FIELD' the length is at least 10, so '> Length(VALUES_OPEN)' decides the same) }
  VALUES_OPEN = 'VALUES (';

{ TableTools AccessorName: fields named NAME clash with TComponent.GetName/SetName
  (W1010), so they get a 'Z' prefix: GetZNAME / SetZNAME. }
function AccessorName(const AFieldName: string): string;
begin
  Result:= if SameText(AFieldName, 'NAME') then 'Z' + AFieldName.ToUpper else AFieldName;
end;

{ TableTools ToolsAPIHelper.ToLiteral: a Pascal string literal, split into '+'-joined
  chunks of at most 254 characters on separate lines. }
function ToLiteral(const ASB: TStringBuilder): string;
var
  I: Integer;
  L: Integer;
begin
  if ASB.Length <= MAX_LITERAL_CHUNK then
    Exit('''' + ASB.ToString + '''');
  Result:= '''''';
  I:= 0;
  while I < ASB.Length do
  begin
    L:= if I + MAX_LITERAL_CHUNK > ASB.Length then ASB.Length - I else MAX_LITERAL_CHUNK;
    Result:= Result + sLineBreak + '+''' + ASB.ToString(I, L) + '''';
    Inc(I, L);
  end;
end;

{ TableTools ToolsAPIHelper.ZeroTime: True when every character is a quote, '0', ':' or blank. }
function ZeroTime(const Astr: string): Boolean;
var
  C: Char;
begin
  Result:= True;
  for C in Astr do
    Result:= Result and string('''0: ').Contains(C);
end;

function OrmSplitLines(const pText: string): TArray<string>;
var
  SL: TStringList;
begin
  SL:= TStringList.Create;
  try
    SL.Text:= pText;
    Result:= SL.ToStringArray;
  finally
    SL.Free;
  end;
end;

function OrmJoinLines(const pLines: TStrings): string;
var
  SB: TStringBuilder;
  S: string;
begin
  SB:= TStringBuilder.Create;
  try
    for S in pLines do
      SB.Append(S).Append(#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

(* The region name of a {$REGION ...} / {$ENDREGION ...} line, upper case, quotes and
   braces removed; '' when the line is not that directive. *)
function RegionName(const pLine, pDirective: string): string;
var
  S: string;
begin
  S:= pLine.Trim.ToUpper;
  if not S.StartsWith(pDirective) then
    Exit('');
  Result:= S.Substring(Length(pDirective)).Replace('''', '').Replace('}', '').Trim;
end;

function IsOrmRegionStart(const pLine: string; out pRegionId: string): Boolean;
var
  Name: string;
begin
  pRegionId:= '';
  { TableTools accepted any region whose name CONTAINS DB-RAD, which emptied hand-written
    regions such as 'MicStream prototype -- hand-written, not DB-RAD' (ORM3 uFOLDERS.PAS);
    here the name must START with DB-RAD and carry an id }
  Name:= RegionName(pLine, '{$REGION');
  if not Name.StartsWith(DB_RAD) then
    Exit(False);
  pRegionId:= Name.Substring(Length(DB_RAD)).Trim;
  { TableTools: the "DB-RADa" spelling }
  if pRegionId.StartsWith('A') then
    pRegionId:= pRegionId.Substring(1).Trim;
  Result:= pRegionId <> '';
end;

function IsOrmRegionEnd(const pLine: string): Boolean;
begin
  Result:= RegionName(pLine, '{$ENDREGION').StartsWith(DB_RAD);
end;

{ TOrmField }

constructor TOrmField.Create(const pFieldName, pVarType, pFieldAsType, pEnumType, pDefaultVal: string;  // dl:ok too-many-parameters@40ab -- REVIEWED 2026-11-17 v152 TTGEN: one value per DL_FIELDS_INFO column the generators read
  pIsEnum: Boolean; pFieldSize: Integer; const pDocSummary, pDocRemarks: string);
begin
  inherited Create;
  FFieldName:= pFieldName;
  FVarType:= pVarType;
  FFieldAsType:= pFieldAsType;
  FEnumType:= pEnumType;
  FDefaultVal:= pDefaultVal;
  FIsEnum:= pIsEnum;
  FFieldSize:= pFieldSize;
  FDocSummary:= TStringList.Create;
  FDocSummary.Text:= pDocSummary;
  FDocRemarks:= TStringList.Create;
  FDocRemarks.Text:= pDocRemarks;
end;

destructor TOrmField.Destroy;
begin
  FDocSummary.Free;
  FDocRemarks.Free;
  inherited;
end;

function TOrmField.GetCurrentFieldName: string;
begin
  Result:= FFieldName.Replace('$', '_');
end;

{ TOrmGenerator }

constructor TOrmGenerator.Create(pRepo: TFDConnection);
begin
  inherited Create;
  FRepo:= pRepo;
  FFieldList:= TObjectList<TOrmField>.Create(True);
  FKeyFields:= TList<string>.Create;
  FKeyTypes:= TList<string>.Create;
  FKeyGens:= TList<string>.Create;
end;

destructor TOrmGenerator.Destroy;
begin
  FKeyGens.Free;
  FKeyTypes.Free;
  FKeyFields.Free;
  FFieldList.Free;
  inherited;
end;

function TOrmGenerator.NewGuid: TGUID;
begin
  if Assigned(FGuidProvider) then
    Exit(FGuidProvider());
  CreateGUID(Result);
end;

function TOrmGenerator.FieldCount: Integer;
begin
  Result:= FFieldList.Count;
end;

function TOrmGenerator.GetFieldName(const AName: string): string;
begin
  Result:= AName.Replace('$', '_');
end;

function TOrmGenerator.LocateField(const pKeyField: string): TOrmField;
var
  F: TOrmField;
begin
  for F in FFieldList do
    if F.FIELD_NAME.ToLower = pKeyField.ToLower then
      Exit(F);
  raise EOrmGenError.CreateFmt('Table <%s> key field <%s> is missing', [FLoadedTable, pKeyField]);
end;

function TOrmGenerator.IsVarTypeCreatable(const AType: string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in CreatableTypes do
    if S.ToUpper = AType.ToUpper then
      Result:= True;
end;

function TOrmGenerator.TableNames: TArray<string>;
var
  Q: TFDQuery;
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= FRepo;
      Q.Open('SELECT DISTINCT TABLE_NAME FROM DL_FIELDS_INFO ORDER BY TABLE_NAME');
      while not Q.Eof do
      begin
        L.Add(Q.Fields[0].AsString);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TOrmGenerator.LoadTable(const pTableName: string);
const
  { column positions of SQL_FIELDS, in its SELECT order }
  FC_NAME = 0;
  FC_VARTYPE = 1;
  FC_ASTYPE = 2;
  FC_ENUMTYPE = 3;
  FC_DEFAULT = 4;
  FC_ISENUM = 5;
  FC_SIZE = 6;
  FC_SUMMARY = 7;
  FC_REMARKS = 8;
  FC_CALC = 9;
  FC_LOOKUP = 10;
  FC_PK = 11;
  FC_SEQ = 12;

  SQL_FIELDS =
    'SELECT FIELD_NAME, VAR_TYPE, FIELD_AS_TYPE, ENUMTYPE, DEFAULTVAL, ISENUM, FIELD_SIZE, ' +
    'DOC_SUMMARY, DOC_REMARKS, ISCALCULATED, ISLOOKUP, PRIMARY_KEY, SEQUENCE_NAME ' +
    'FROM DL_FIELDS_INFO WHERE TABLE_NAME = :T AND FIELD_KIND = 1 ORDER BY FIELD_NAME';
var
  Q: TFDQuery;
  Field: TOrmField;
  S: string;
  Rows: Integer;
begin
  FFieldList.Clear;
  FKeyFields.Clear;
  FKeyTypes.Clear;
  FKeyGens.Clear;
  FHasGenerator:= False;
  FGenName:= '';
  FLoadedTable:= pTableName;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= FRepo;
    Rows:= FRepo.ExecSQLScalar('SELECT COUNT(*) FROM DL_FIELDS_INFO WHERE TABLE_NAME = :T', [pTableName]);
    Q.Open(SQL_FIELDS, [pTableName]);
    while not Q.Eof do
    begin
      { calculated / lookup fields have no real column: they never enter the list (TableTools 2026-05-19) }
      if not (Q.Fields[FC_CALC].AsBoolean or Q.Fields[FC_LOOKUP].AsBoolean) then
      begin
        Field:= TOrmField.Create(
          Q.Fields[FC_NAME].AsString.TrimRight,
          Q.Fields[FC_VARTYPE].AsString.TrimRight,
          Q.Fields[FC_ASTYPE].AsString.TrimRight,
          Q.Fields[FC_ENUMTYPE].AsString.TrimRight,
          Q.Fields[FC_DEFAULT].AsString.TrimRight,
          Q.Fields[FC_ISENUM].AsBoolean,
          Q.Fields[FC_SIZE].AsInteger,
          Q.Fields[FC_SUMMARY].AsString,
          Q.Fields[FC_REMARKS].AsString);
        FFieldList.Add(Field);
        if Q.Fields[FC_PK].AsBoolean then
        begin
          FKeyFields.Add(Field.FIELD_NAME);
          FKeyTypes.Add(Field.VAR_TYPE);
          S:= 'GEN_' + pTableName + '_' + Field.GetCurrentFieldName;
          if Q.Fields[FC_SEQ].AsString.Trim <> '' then
          begin
            FKeyGens.Add(S);
            FGenName:= S;
            FHasGenerator:= True;
          end
          else
            FKeyGens.Add('');
        end;
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  if Rows = 0 then
    raise EOrmGenError.CreateFmt('Table <%s> has no field rows in the repository', [pTableName]);
end;

procedure TOrmGenerator.GenerateInterfaceFooter(InterfaceObject: TStringList);
begin
  InterfaceObject.Add('end;'          );
  InterfaceObject.Add('  '            );
  InterfaceObject.Add('implementation');
  InterfaceObject.Add('  '            );
  InterfaceObject.Add('end.'          );
end;

procedure TOrmGenerator.GenerateNewServerObject(const TableName0: string; PasObject: TStringList);  // dl:ok method-too-long@51af -- REVIEWED 2026-11-17 v152 TTGEN: verbatim TableTools generator (one Add per emitted line); splitting it risks the byte-identical output
var
  SectionCode : TStringList;
  TableId   : string;
  GenName     : string;
  HasTimestamp: Boolean;
  HasEnum     : Boolean;
  TSField     : TOrmField;
begin
  TableId:= TableName0.Replace('$', '_');
  LoadTable(TableName0);
  GenName:= FGenName;

  HasTimestamp:= False;
  for TSField in FFieldList do if SameText(TSField.VAR_TYPE, 'TSQLTimeStamp') then
  begin
    HasTimestamp:= True;
    Break;
  end;

  HasEnum:= False;
  for TSField in FFieldList do if TSField.ISENUM then
  begin
    HasEnum:= True;
    Break;
  end;

  SectionCode:= TStringList.Create;
  try
    PasObject.Add(Format('unit u%s_SERVER; // 1', [TableId]));
    PasObject.Add('                           ');
    PasObject.Add('interface                  ');
    PasObject.Add('                           ');
    PasObject.Add('uses                       ');
    PasObject.Add('  System.Classes,          ');
    PasObject.Add('  System.SysUtils,         ');
    PasObject.Add('  Spring.Container.Common, ');
    PasObject.Add('  FIREDAC.Comp.Client,     ');
    PasObject.Add('  iLoggingServiceP,        ');
    PasObject.Add('  IuMicObject,             ');
    PasObject.Add(Format('  i%s, // 1          ', [TableId]));
    PasObject.Add('  MStreams                 ');
    PasObject.Add('                           ');
    PasObject.Add('	 ;                       ' );
    PasObject.Add('{$M+}                      ');
    PasObject.Add('                           ');
    PasObject.Add('type                       ');
    PasObject.Add(Format('  TDataService_%s_SERVER = class(TInterfacedObject, IDataService, IDataService<Imc%s>) // 2', [TableId, TableId]));
    PasObject.Add('	 private                           '                                                  );
    PasObject.Add('		FThreadStorage: IThreadStorage;  '                                                   );
    PasObject.Add('		FLog          : IABZLoggingSys; '                                                    );
    PasObject.Add('		FContext      : TLogContext;     '                                                   );
    PasObject.Add('		QRYLoad       : TFDQuery;        '                                                   );
    PasObject.Add('		QRYSave       : TFDCommand;      '                                                   );
    PasObject.Add('		CmdNextID     : TFDCommand;      '                                                   );
    PasObject.Add('		fTableName    : string;          '                                                   );
    PasObject.Add('		fGenName      : string;          '                                                   );
    PasObject.Add('    FQueriesPrepared: Boolean;       '                                                 );
    PasObject.Add('                                     '                                                 );
    PasObject.Add('		procedure PrepareLoadQuery;      '                                                   );
    PasObject.Add('		procedure PrepareSaveQuery;      '                                                   );
    PasObject.Add('    procedure EnsureQueriesPrepared; '                                                 );
    PasObject.Add('	 public                            '                                                  );
    PasObject.Add('		destructor Destroy; override;    '                                                   );
    PasObject.Add('		[Spring.Container.Common.Inject]                                  '                  );
    PasObject.Add('		constructor Create(const ThreadStorage: IThreadStorage; const ALog: IABZLoggingSys);');
    PasObject.Add('    // IDataService (Base / Threading)                                '                );
    PasObject.Add('		function GetThreadStorage: IThreadStorage;                        '                  );
    PasObject.Add('		procedure SetThreadStorage(const Value: IThreadStorage);          '                  );
    PasObject.Add('	 published                                                          '                 );
    PasObject.Add('		function NextID: Int64;                                           '                  );
    PasObject.Add(Format('    // IDataService<Imc%s> - Specific Methods // 1', [TableId]));
    PasObject.Add('    // This is the one where you actually do the work                 ');
    PasObject.Add(Format('		function Load(const Obj: Imc%s): boolean; overload; // 1', [TableId]));
    PasObject.Add(Format('		function Save(const Obj: Imc%s): boolean; overload; // 1', [TableId]));
    PasObject.Add('		// [Inject]                                                       '                  );
    PasObject.Add('		property ThreadStorage: IThreadStorage read GetThreadStorage write SetThreadStorage;');
    PasObject.Add('  end;                   '                                                             );
    PasObject.Add('                         '                                                             );
    PasObject.Add('implementation           '                                                             );
    PasObject.Add('                         '                                                             );
    PasObject.Add('uses                     '                                                             );
    PasObject.Add('  CommonExceptions,                '                                                   );
    PasObject.Add('  ExceptionLog7, // EurekaLog unit '                                                   );
    PasObject.Add('  CodeSiteLogging,                 '                                                   );
    PasObject.Add('  ECallStack,                      '                                                   );
    PasObject.Add('  FIREDAC.Stan.Error,              '                                                   );
    PasObject.Add('  FIREDAC.Stan.Param,              '                                                   );
    PasObject.Add('  FIREDAC.Dats              '                                                          );
    if HasTimestamp then
      PasObject.Add('  ,Data.SqlTimSt             ');
    if HasEnum then
      PasObject.Add('  , MSCTYPES               ' )
    else
      PasObject.Add('  // MSCTYPES               ' );
    PasObject  .Add('                         '    );
    PasObject  .Add('	 ;                     '     );
    PasObject  .Add('                         '    );
    PasObject.Add(Format('constructor TDataService_%s_SERVER.Create(const ThreadStorage: IThreadStorage; const ALog: IABZLoggingSys); // 1', [TableId]));
    PasObject.Add('begin                             ');
    PasObject.Add('  inherited Create;               ');
    PasObject.Add('  FThreadStorage:= ThreadStorage; ');
    PasObject.Add('  FLog          := ALog;          ');
    PasObject.Add('  FQueriesPrepared:= False;       ');
    PasObject.Add(Format('  fTableName    := ''%s''; //// ', [TableName0]));
    PasObject.Add(Format('  fGenName      := ''%s''; ////' , [GenName   ]));
    PasObject.Add('     // DON''T prepare queries here - do it on first use');
    PasObject.Add('end;                                                                ');
    PasObject.Add('                                                                    ');
    PasObject.Add(Format('destructor TDataService_%s_SERVER.Destroy; // 1', [TableId]));
    PasObject.Add('begin            ');
    PasObject.Add('  QRYLoad.Free;  ');
    PasObject.Add('  QRYSave.Free;  ');
    PasObject.Add('  CmdNextID.Free;');
    PasObject.Add('  inherited;     ');
    PasObject.Add('end;             ');
    PasObject.Add('                 ');
    PasObject.Add(Format('procedure TDataService_%s_SERVER.EnsureQueriesPrepared; // 1', [TableId]));
    PasObject.Add('begin                            '                         );
    PasObject.Add('  if FQueriesPrepared then Exit; '                         );
    PasObject.Add('                                 '                         );
    PasObject.Add('  PrepareLoadQuery;              '                         );
    PasObject.Add('  PrepareSaveQuery;              '                         );
    PasObject.Add('                                 '                         );
    PasObject.Add('  CmdNextID := TFDCommand.Create(FThreadStorage.DataBase);');
    PasObject.Add(Format('  CmdNextID.Name := NewName(FThreadStorage.DataBase, ''CmdNextID_%s_SERVER''); // 1', [TableId]));
    PasObject.Add('  CmdNextID.Connection := FThreadStorage.DataBase;        '                                           );
    PasObject.Add('  CmdNextID.CommandText.Clear; '                                                                      );
    PasObject.Add('  if fGenName.Trim <> '''' then'                                                                      );
    PasObject.Add('  begin                        '                                                                      );
    PasObject.Add('    CmdNextID.CommandText.Text := Format(''SELECT NEXT VALUE FOR %s FROM RDB$DATABASE'', [fGenName]);');
    PasObject.Add('    CmdNextID.Prepare;                                     '                                          );
    PasObject.Add('  end;                                                     '                                          );
    PasObject.Add('                                                           '                                          );
    PasObject.Add('  FQueriesPrepared := True;                                '                                          );
    PasObject.Add('end;                                                       '                                          );
    PasObject.Add('                                                           '                                          );
    PasObject.Add(Format('procedure TDataService_%s_SERVER.PrepareLoadQuery; // 1', [TableId]));
    PasObject.Add('begin                                                               ');
    PasObject.Add('  QRYLoad           := TFDQuery.Create(FThreadStorage.DataBase);    ');
    PasObject.Add('  QRYLoad.Connection:= FThreadStorage.DataBase;                     ');
    PasObject.Add(Format('  QRYLoad.Name      := NewName(FThreadStorage.DataBase, ''QRYLoad_%s_SERVER''); // 1', [TableId]));
    PasObject.Add('  if not FThreadStorage.DataBase.Connected then                     ');
    PasObject.Add('	 FThreadStorage.DataBase.Open;                                    ' );
    PasObject.Add('  QRYLoad.SQL.Clear;                                                ');
    PasObject.Add('	 {$REGION ''DB-RAD 8A''}                                          ' );
    SectionCode.Clear;
    GenerateSection8A(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                   );
    PasObject.Add       ('  {$ENDREGION ''DB-RAD 8A''}');
    PasObject.Add       ('end;                        ');
    PasObject.Add       ('                            ');
    PasObject.Add(Format('procedure TDataService_%s_SERVER.PrepareSaveQuery; // 1', [TableId]));
    PasObject.Add('begin                       '                                      );
    PasObject.Add('  QRYSave           := TFDCommand.Create(FThreadStorage.DataBase);');
    PasObject.Add(Format('  QRYSave.Name      := NewName(FThreadStorage.DataBase, ''QrySave_%s_SERVER''); // 1', [TableId]));
    PasObject.Add('  QRYSave.Connection:= FThreadStorage.DataBase;');
    PasObject.Add('  QRYSave.Transaction:= FThreadStorage.UpdateTransaction;');
    PasObject.Add('  QRYSave.CommandText.Clear;                   '          );
    PasObject.Add('  {$REGION ''DB-RAD 9A''}                      '          );
    SectionCode.Clear;
    GenerateSection9A(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                                                              );
    PasObject.Add       ('	 {$ENDREGION ''DB-RAD 9A''}                                           ');
    PasObject.Add       ('end;'                                                                   );
    PasObject.Add       ('    '                                                                   );
    PasObject.Add(Format('function TDataService_%s_SERVER.Load(const Obj: Imc%s): boolean;// 2', [TableId, TableId]));
    PasObject.Add('begin               '     );
    PasObject.Add('  Result  := False; '     );
    PasObject.Add('   EnsureQueriesPrepared;');
    PasObject.Add(Format('  FContext:= TLogContext.ForDB(''%s'', QRYLoad.SQL.Text); // 1', [TableId]));
    PasObject.Add('                                               '                           );
    PasObject.Add('  if not ThreadStorage.DataBase.Connected then '                           );
    PasObject.Add('  begin                                        '                           );
    PasObject.Add('	 FLog.Warning(''Database not connected, attempting to open'', FContext);' );
    PasObject.Add('	 try                                                                    ' );
    PasObject.Add('		ThreadStorage.DataBase.Open;                                          '  );
    PasObject.Add('	 except                                                                 ' );
    PasObject.Add('		on E: Exception do                                                    '  );
    PasObject.Add('		begin                                                                 '  );
    PasObject.Add('		  FLog.LogFireDACError(E, FContext);                                  '  );
    PasObject.Add('		  Exit;                                                               '  );
    PasObject.Add('		end;                                                                  '  );
    PasObject.Add('	 end;                                                                   ' );
    PasObject.Add('  end;                                                                    ');
    PasObject.Add('                                                                          ');
    PasObject.Add('  if QRYLoad.Active then                                                  ');
    PasObject.Add('	 QRYLoad.Close;                                                         ' );
    PasObject.Add('  FLog.Trace(''Load Start'', FContext);                                   ');
    PasObject.Add('  FThreadStorage.Transaction.StartTransaction;                            ');
    PasObject.Add('  try                                                                     ');
    PasObject.Add('	 {$REGION ''DB-RAD 8''}                                                 ' );
    SectionCode.Clear;
    GenerateSection8(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode);
    PasObject.Add('	 {$ENDREGION ''DB-RAD 8''}                                           ');
    PasObject.Add('   // CodeSite.Send(''  >> AFTER LOAD-ASSIGN QRYLoad.RecordCount=%d; Obj.VAR_TYPE=%s; Obj.ENUMTYPE=<%s>'', [QRYLoad.RecordCount, Obj.VAR_TYPE, Obj.ENUMTYPE]);');
    PasObject.Add('                                          ');
    PasObject.Add('	 if Result then                         ');
    PasObject.Add('	 begin                                  ');
    PasObject.Add('		FLog.Trace(''Load Commit'', FContext);');
    PasObject.Add('		FThreadStorage.Transaction.Commit;    ');
    PasObject.Add('		FLog.LogTransactionCommit(FContext);  ');
    PasObject.Add('		Obj.Modified:= False;                 ');
    PasObject.Add('		FLog.Trace(''Load OK - RecordCount >= 1'', FContext);');
    PasObject.Add('	 end                                    ');
    PasObject.Add('	 else                                   ');
    PasObject.Add('	 begin                                  ');
    PasObject.Add('		FThreadStorage.Transaction.Rollback;  ');
    PasObject.Add('		FLog.LogTransactionRollback(Format(''RecordCount=%d, expected 1'', [QRYLoad.RecordCount]), FContext);');
    PasObject.Add('		FLog.Warning(''Load returned unexpected RecordCount count'', FContext);                              ');
    PasObject.Add('	 end;                                   ');
    PasObject.Add('                                          ');
    PasObject.Add('  except                                  ');
    PasObject.Add('	 on E: EFDException do                  ');
    PasObject.Add('	 begin                                  ');
    PasObject.Add('		try                                   ');
    PasObject.Add('  		FContext.ErrorCode:= E.FDCode;      ');
    PasObject.Add('		  FThreadStorage.Transaction.Rollback;');
    PasObject.Add('		  FLog.LogTransactionRollback(E.Message, FContext);');
    PasObject.Add('		except                                             ');
    PasObject.Add('		  on ERollback: Exception do                       ');
    PasObject.Add(Format('			 FLog.LogFireDACError(ERollback, TLogContext.ForDB(''%s'', ''ROLLBACK: '' + ERollback.Message)); // 1', [TableId]));
    PasObject.Add('		end;                                               '                             );
    PasObject.Add('		FLog.LogFireDACError(E, FContext);                 '                             );
    PasObject.Add('		Result:= False;                                    '                             );
    PasObject.Add('	 end;                                                '                            );
    PasObject.Add('	 on E: Exception do                                  '                            );
    PasObject.Add('	 begin                                               '                            );
    PasObject.Add('		try                                                '                             );
    PasObject.Add('		  FThreadStorage.Transaction.Rollback;             '                             );
    PasObject.Add('		  FLog.LogTransactionRollback(E.Message, FContext);'                             );
    PasObject.Add('		except                                             '                             );
    PasObject.Add('		  on ERollback: Exception do                       '                             );
    PasObject.Add('			 FLog.LogException(ERollback, ''Rollback failed after Load error'', FContext);' );
    PasObject.Add('		end;                                                                            ');
    PasObject.Add(Format('		FLog.LogException(E, ''Unexpected error in %s Load'', FContext); // 1', [TableId]));
    PasObject.Add('		Result:= False;                                                                 '  );
    PasObject.Add('	 end;                                                                             ' );
    PasObject.Add('  end;                                                                              ');
    PasObject.Add('end;                                                                                ');
    PasObject.Add('                                                                                    ');
    PasObject.Add(Format('function TDataService_%s_SERVER.Save(const Obj: Imc%s): boolean; // 2', [TableId, TableId]));
    PasObject.Add('begin                                                                               ');
    PasObject.Add('  Result  := False;                                                                 ');
    PasObject.Add('   EnsureQueriesPrepared;'                                                           );
    PasObject.Add(Format('  FContext:= TLogContext.ForDB(''%s'', QRYSave.CommandText.Text); // 1', [TableId]));
    PasObject.Add('                                                                                    ');
    PasObject.Add('  if not ThreadStorage.DataBase.Connected then                                      ');
    PasObject.Add('  begin                                                                             ');
    PasObject.Add('	 FLog.Warning(''Database not connected, attempting to open'', FContext);          ' );
    PasObject.Add('	 try                                                                              ' );
    PasObject.Add('		ThreadStorage.DataBase.Open;                                                    '  );
    PasObject.Add('	 except                                                                           ' );
    PasObject.Add('		on E: Exception do                                                              '  );
    PasObject.Add('		begin                                                                           '  );
    PasObject.Add('		  FLog.LogFireDACError(E, FContext);                                            '  );
    PasObject.Add('		  Exit;                                                                         '  );
    PasObject.Add('		end;                                                                            '  );
    PasObject.Add('	 end;                                                                             ' );
    PasObject.Add('  end;                                                                              ');
    PasObject.Add('                                                                                    ');
    PasObject.Add('  FLog.Trace(''Save START'', FContext);                                             ');
    PasObject.Add('  FThreadStorage.UpdateTransaction.StartTransaction;                                ');
    PasObject.Add('  try                                                                               ');
    PasObject.Add('	 {$REGION ''DB-RAD 9''}                                                           ' );
    SectionCode.Clear;
    GenerateSection9(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                                                                                                  );
    PasObject.Add       ('	 {$ENDREGION ''DB-RAD 9''}                                           '                                     );
    PasObject.Add       ('	 QRYSave.Execute;                                   '                                                      );
    PasObject.Add       ('	 // UPDATE OR INSERT: RowsAffected=1 on INSERT, 2 when it'                                                 );
    PasObject.Add       ('	 // UPDATEs an existing row. A real failure raises'                                                        );
    PasObject.Add       ('	 // EFDException (handled below); any positive count = OK.'                                                );
    PasObject.Add       ('	 Result:= QRYSave.RowsAffected >= 1;                '                                                      );
    PasObject.Add       ('                                                      '                                                     );
    PasObject.Add       ('	 if Result then                                     '                                                      );
    PasObject.Add       ('	 begin                                              '                                                      );
    PasObject.Add       ('		FThreadStorage.UpdateTransaction.Commit;          '                                                       );
    PasObject.Add       ('		FLog.LogTransactionCommit(FContext);              '                                                       );
    PasObject.Add       ('		Obj.Modified:= False;                             '                                                       );
    PasObject.Add       ('		FLog.Trace(''Save OK'', FContext);                  '                                                     );
    PasObject.Add       ('	 end                                                '                                                      );
    PasObject.Add       ('	 else                                               '                                                      );
    PasObject.Add       ('	 begin                                              '                                                      );
    PasObject.Add       ('		FThreadStorage.UpdateTransaction.Rollback;        '                                                       );
    PasObject.Add       ('		FLog.LogTransactionRollback(Format(''RowsAffected=%d, expected >=1'', [QRYSave.RowsAffected]), FContext);');
    PasObject.Add       ('		FLog.Warning(''Save returned unexpected RowsAffected count'', FContext);                               '  );
    PasObject.Add       ('	 end;                                                                                                  '   );
    PasObject.Add       ('                                                                                                         '  );
    PasObject.Add       ('  except                                                                                                 '  );
    PasObject.Add       ('	 on E: EFDException do                                                                                 '   );
    PasObject.Add       ('	 begin                                                                                                 '   );
    PasObject.Add       ('		try                                                                                                  '    );
    PasObject.Add       ('  		FContext.ErrorCode:= E.FDCode;                                                                     '    );
    PasObject.Add       ('		  FThreadStorage.UpdateTransaction.Rollback;                                                         '    );
    PasObject.Add       ('		  FLog.LogTransactionRollback(E.Message, FContext);                                                  '    );
    PasObject.Add       ('		except                                                                                               '    );
    PasObject.Add       ('		  on ERollback: Exception do                                                                         '    );
    PasObject.Add(Format('			 FLog.LogFireDACError(ERollback, TLogContext.ForDB(''%s'', ''ROLLBACK: '' + ERollback.Message)); // 1', [TableId]));
    PasObject.Add('		end;                                               '                            );
    PasObject.Add('		FLog.LogFireDACError(E, FContext);                 '                            );
    PasObject.Add('		Result:= False;                                    '                            );
    PasObject.Add('	 end;                                                '                           );
    PasObject.Add('	 on E: Exception do                                  '                           );
    PasObject.Add('	 begin                                               '                           );
    PasObject.Add('		try                                                '                            );
    PasObject.Add('		  FThreadStorage.UpdateTransaction.Rollback;       '                            );
    PasObject.Add('		  FLog.LogTransactionRollback(E.Message, FContext);'                            );
    PasObject.Add('		except                                             '                            );
    PasObject.Add('		  on ERollback: Exception do                       '                            );
    PasObject.Add('			 FLog.LogException(ERollback, ''Rollback failed after Save error'', FContext);');
    PasObject.Add('		end;                                                                          ' );
    PasObject.Add(Format('		FLog.LogException(E, ''Unexpected error in %s Save'', FContext); // 1', [TableId]));
    PasObject.Add('		Result:= False; '  );
    PasObject.Add('	 end;             ' );
    PasObject.Add('  end;              ');
    PasObject.Add('end;                ');
    PasObject.Add('                    ');
    PasObject.Add(Format('function TDataService_%s_SERVER.GetThreadStorage: IThreadStorage; // 1', [TableId]));
    PasObject.Add('begin                     ');
    PasObject.Add('  Result:= FThreadStorage;');
    PasObject.Add('end;                      ');
    PasObject.Add('                          ');
    PasObject.Add(Format('function TDataService_%s_SERVER.NextID: Int64; // 1', [TableId]));
    PasObject.Add('var                              '               );
    PasObject.Add('  WasTransactionActive: boolean; '               );
    PasObject.Add('begin                            '               );
    PasObject.Add('  Result  := 0;                '                 );
    PasObject.Add('   EnsureQueriesPrepared;'                       );
    PasObject.Add('  if CmdNextID.CommandText.Text.Trim = '''' then');
    PasObject.Add('	 Exit;                                      '   );
    PasObject.Add(Format('  FContext:= TLogContext.ForDB(''%s'', CmdNextID.CommandText.Text); // 1', [TableId]));
    PasObject.Add('  // 1. Ensure we have a transaction context '                                                                      );
    PasObject.Add('  // Note: Generators increment even if you Rollback, but FireDAC needs the ''Active'' state to talk to the engine.');
    PasObject.Add('  WasTransactionActive:= FThreadStorage.Transaction.Active;                                                      '  );
    PasObject.Add('  if not WasTransactionActive then                                                                               '  );
    PasObject.Add('	 FThreadStorage.Transaction.StartTransaction;                                                                  '   );
    PasObject.Add('  try                                                                                                            '  );
    PasObject.Add('	 try                                                                                                           '   );
    PasObject.Add('		CmdNextID.Open; // 2. Execute the prepared command                                                           '    );
    PasObject.Add('		Result:= CmdNextID.Define.Rows[0].GetData(0); // 3. Direct engine access for maximum speed                   '    );
    PasObject.Add('	 finally                                                                                                       '   );
    PasObject.Add('		CmdNextID.Close; // 4. Always close the result set cursor to allow reuse of the command                      '    );
    PasObject.Add('	 end;                                                                                                          '   );
    PasObject.Add('	 if not WasTransactionActive then // 5. If we started the transaction just for this, we should close it.       '   );
    PasObject.Add('		FThreadStorage.Transaction.Commit; // Use Commit to be clean, though Rollback would keep the ID too!         '    );
    PasObject.Add('  except                                                                                                         '  );
    PasObject.Add('	 on E: EFDException do                                                                                         '   );
    PasObject.Add('	 begin                                                                                                         '   );
    PasObject.Add('		FContext.ErrorCode:= E.FDCode;                                                                               '    );
    PasObject.Add('		if not WasTransactionActive and FThreadStorage.Transaction.Active then                                       '    );
    PasObject.Add('		  FThreadStorage.Transaction.Rollback;                                                                       '    );
    PasObject.Add('                                                                                                                 '  );
    PasObject.Add('      // Log using your EurekaLog/CodeSite wrapper                                                               '  );
    PasObject.Add('		FLog.LogException(E, ''NextID Error: '' + E.FDObjName + '' : '', FContext);                                  '    );
    PasObject.Add('		raise;                                                                                                       '    );
    PasObject.Add('	 end;                                                                                                          '   );
    PasObject.Add('	 on E: Exception do                                                                                            '   );
    PasObject.Add('	 begin                                                                                                         '   );
    PasObject.Add('		if not WasTransactionActive and FThreadStorage.Transaction.Active then                                       '    );
    PasObject.Add('		  FThreadStorage.Transaction.Rollback;                                                                       '    );
    PasObject.Add('                                                                                                                 '  );
    PasObject.Add('      // Log using your EurekaLog/CodeSite wrapper                                                               '  );
    PasObject.Add('		FLog.LogException(E, ''NextID Error:'', FContext);                                                             '  );
    PasObject.Add('		raise;                                                                                                       '    );
    PasObject.Add('	 end;                                                                                                          '   );
    PasObject.Add('  end;                                                                                                           '  );
    PasObject.Add('end;                                                                                                             '  );
    PasObject.Add('                                                                                                                 '  );
    PasObject.Add(Format('procedure TDataService_%s_SERVER.SetThreadStorage(const Value: IThreadStorage); // 1', [TableId]));
    PasObject.Add('begin                                                                                                            ');
    PasObject.Add('  FThreadStorage:= Value;                                                                                        ');
    PasObject.Add('end;                                                                                                             ');
    PasObject.Add('                                                                                                                 ');
    PasObject.Add('end.                                                                                                             ');
  finally
    SectionCode.Free;
  end; // try
end; // procedure

procedure TOrmGenerator.GenerateNewTableObject(const TableName0: string; InterfaceObject, PasObject: TStringList);  // dl:ok method-too-long@4e9f -- REVIEWED 2026-11-17 v152 TTGEN: verbatim TableTools generator (one Add per emitted line); splitting it risks the byte-identical output
var
  IntfGUID    : TGUID;
  TableId   : string;
  SectionCode : TStringList;
begin
  TableId:= TableName0.Replace('$', '_');
  LoadTable(TableName0);

  SectionCode:= TStringList.Create;
  try
    InterfaceObject.Add(Format('unit %s%s;', [ORM_INTF_PREFIX, TableId]));
    InterfaceObject.Add('                     '    );
    InterfaceObject.Add('interface            '    );
    InterfaceObject.Add('                     '    );
    InterfaceObject.Add('uses                 '    );
    InterfaceObject.Add('  System.Classes,     '   );
    InterfaceObject.Add('  System.SysUtils, '      );
    InterfaceObject.Add('  VCL.Graphics,       '   );
    InterfaceObject.Add('  Data.SqlTimSt,   '      );
    InterfaceObject.Add('  Data.FmtBcd,     '      );
    InterfaceObject.Add('  //MSCTYPES,            ');
    InterfaceObject.Add('  IUMicObject'            );
    InterfaceObject.Add('                     '    );
    InterfaceObject.Add('		;                 '     );
    InterfaceObject.Add('                     '    );
    InterfaceObject.Add('                     '    );
    InterfaceObject.Add('type                 '    );
    InterfaceObject.Add('                     '    );

    InterfaceObject.Add(Format('  Imc%s = interface(IMicObject)', [TableId]));
    IntfGUID:= NewGuid;
    InterfaceObject.Add(Format('    [''%s'']', [GUIDToString(IntfGUID)]));
    if TableId = 'FIB_FIELDS_INFO' then
    begin
      InterfaceObject.Add('    function GetCurrentFieldName: string;');
      InterfaceObject.Add(Format('    function Setup(const ATable, AField: string): Imc%s;', [TableId]));
    end;
    InterfaceObject.Add(Format('    procedure AssignI(const IValue: Imc%s);', [TableId]));

    PasObject.Add(Format('unit %s%s;', [ORM_PAS_PREFIX, TableId]));
    PasObject.Add('                     	'    );
    PasObject.Add('interface            	'    );
    PasObject.Add('                     	'    );
    PasObject.Add('uses                 	'    );
    PasObject.Add('  System.Classes,     '    );
    PasObject.Add('  System.SysUtils,    '    );
    PasObject.Add('  VCL.Graphics,       '    );
    PasObject.Add('  Data.DB,            '    );
    PasObject.Add('  Data.SqlTimSt,      '    );
    PasObject.Add('  Data.FmtBcd,        '    );
    PasObject.Add('  Spring,             '    );
    PasObject.Add('  Spring.Collections, '    );
    PasObject.Add('  Spring.Container.Common,');
    PasObject.Add('  Spring.Services,        ');
    PasObject.Add('  Spring.Container,       ');
    PasObject.Add('  FireDAC.Comp.DataSet,   ');
    PasObject.Add('  FireDAC.Comp.Client,    ');
    PasObject.Add('  FireDAC.Stan.Param,     ');
    PasObject.Add('  IUMicObject,            ');
    PasObject.Add('  MStreams,               ');
    PasObject.Add('  //MscTypes,             ');
    PasObject.Add(Format('  %s%s,', [ORM_INTF_PREFIX, TableId]));
    PasObject.Add('  uMicObjectBase'                                     );
    PasObject.Add('               	'                                     );
    PasObject.Add('	 ; '                                                 );
    PasObject.Add('{$M+}'                                                );
    PasObject.Add('                     	'                               );
    PasObject.Add('type                  '                               );
    PasObject.Add('	[ComponentPlatformsAttribute(pidWin32 or pidWin64)] ');
    PasObject.Add(Format('  Tmc%s = class(TMicObjectBase<Imc%s>, Imc%s) ', [TableId, TableId, TableId]));
    PasObject.Add('  private                     	');
    PasObject.Add('{$REGION ''DB-RAD 1''}');
    SectionCode.Clear;
    GenerateSection1(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 1''}');

    PasObject.Add('{$REGION ''DB-RAD 1A''}');
    SectionCode.Clear;
    GenerateSection1A(SectionCode);
    PasObject.AddStrings(SectionCode                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 1A''}');

    PasObject.Add('  protected                    	');
    PasObject.Add('    '                                                 );
    PasObject.Add('     procedure AssignTo(Dest: TPersistent); override;');
    PasObject.Add('  public                    	');
    PasObject.Add('     constructor Create(Owner: TComponent); override;');
    PasObject.Add('  published'                                          );
    PasObject.Add('{$REGION ''DB-RAD 12''}'                              );
    { region 12 is empty (see GenerateRegion) }
    PasObject.Add       ('{$ENDREGION ''DB-RAD 12''}');

    PasObject.Add('     destructor Destroy; override;'                   );
    PasObject.Add('     procedure Assign(Source: TPersistent); override;');
    PasObject.Add('     procedure Initialize; override;'                                        );
    PasObject.Add('     function __GetClassName:string;                                        ');
    PasObject.Add('     function Writer(AStream: TABZMemoryStream): boolean; override;');
    PasObject.Add('     function Reader(AStream: TABZMemoryStream): boolean; override;');
    PasObject.Add(Format('     procedure AssignI(const Value: Imc%s);', [TableId]));
    if TableId = 'FIB_FIELDS_INFO' then
    begin
      PasObject.Add('   function GetCurrentFieldName: string;'                            );
      PasObject.Add('   function Setup(const ATable, AField: string): ImcFIB_FIELDS_INFO;');
    end;
    PasObject.Add('    ');
    PasObject.Add('{$REGION ''DB-RAD 2''}');
    SectionCode.Clear;
    GenerateSection2P(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 2''}');

    InterfaceObject.Add('{$REGION ''DB-RAD 2''}');
    SectionCode.Clear;
    GenerateSection2I(SectionCode);
    InterfaceObject.AddStrings(SectionCode                );
    InterfaceObject.Add       ('{$ENDREGION ''DB-RAD 2''}');

    GenerateInterfaceFooter(InterfaceObject);
    PasObject.Add('  end;		               ');
    PasObject.Add('									       '       );
    PasObject.Add('procedure Register;     ');
    PasObject.Add('									       '        );
    PasObject.Add('implementation		       ' );
    PasObject.Add('									       '        );
    PasObject.Add('uses							       '      );
    PasObject.Add('									       '        );
    PasObject.Add('  System.IOutils,        ');
    PasObject.Add('  System.Strutils,       ');
    PasObject.Add('  Winapi.Messages,       ');
    PasObject.Add('  Winapi.Windows         ');
    PasObject.Add('                         ');
    PasObject.Add('    ;                    ');
    PasObject.Add('                         ');
    PasObject.Add('procedure Register;     ' );
    PasObject.Add('begin						       '       );
    PasObject.Add(Format('		RegisterComponents(''Micronite'', [Tmc%s]);', [TableId]));
    PasObject.Add('end;							       ');
    PasObject.Add('									       '  );

    if TableId = 'FIB_FIELDS_INFO' then
    begin
      PasObject.Add(Format('function Tmc%s.GetCurrentFieldName: string;', [TableId]));
      PasObject.Add('begin                                                                                                             ');
      PasObject.Add('  Result:= fFIELD_NAME.Replace(''$'', ''_'');                                                                     ');
      PasObject.Add('end;                                                                                                              ');
    end;
    PasObject.Add('                                                                                                                  ');
    PasObject.Add('                                                                                                                  ');
    PasObject.Add(Format('constructor Tmc%s.Create(Owner: TComponent);', [TableId]));
    PasObject.Add('begin'                     );
    PasObject.Add('  inherited Create(Owner);');
    PasObject.Add('{$REGION ''DB-RAD 14''}');
    SectionCode.Clear;
    GenerateSection14(SectionCode);
    PasObject.AddStrings(SectionCode                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 14''}');
    PasObject.Add       ('end;'                      );
    PasObject.Add       (' '                         );
    PasObject.Add(Format('destructor Tmc%s.Destroy;', [TableId]));
    PasObject.Add('begin'                  );
    PasObject.Add('{$REGION ''DB-RAD 15''}');
    SectionCode.Clear;
    GenerateSection15(SectionCode);
    PasObject.AddStrings(SectionCode                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 15''}');
    PasObject.Add       ('  inherited Destroy;'      );

    PasObject.Add('end;');
    PasObject.Add(' '   );
    PasObject.Add(Format('function Tmc%s.__GetClassName: string;', [TableId]));
    PasObject.Add('begin');
    PasObject.Add(Format('  result:= ''Tmc%s'';', [TableId]));
    PasObject.Add('end;');
    PasObject.Add(' '   );

    PasObject.Add(' ');
    PasObject.Add(' ');

    PasObject.Add(' ');

    PasObject.Add(Format('function Tmc%s.Writer(AStream:TABZMemoryStream): boolean;', [TableId]));
    PasObject.Add('begin'                  );
    PasObject.Add('  Result:= True;'       );
    PasObject.Add('{$REGION ''DB-RAD 10''}');
    SectionCode.Clear;
    GenerateSection10(SectionCode);
    PasObject.AddStrings(SectionCode                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 10''}');
    PasObject.Add       (' '                         );
    PasObject.Add       ('end;'                      );
    PasObject.Add       (' '                         );

    PasObject.Add(Format('function Tmc%s.Reader(AStream:TABZMemoryStream): boolean;', [TableId]));
    PasObject.Add('var'                    );
    PasObject.Add('  StreamSize: integer;' );
    PasObject.Add('  ByteTemp: Byte;'      );
    PasObject.Add('begin'                  );
    PasObject.Add('  Result:= True;'       );
    PasObject.Add('{$REGION ''DB-RAD 11''}');
    SectionCode.Clear;
    GenerateSection11(SectionCode);
    PasObject.AddStrings(SectionCode                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 11''}');
    PasObject.Add       (' '                         );
    PasObject.Add       ('end;'                      );
    PasObject.Add       (' '                         );
    PasObject.Add(Format('procedure Tmc%s.Initialize;', [TableId]));
    PasObject.Add('begin');

    PasObject.Add('{$REGION ''DB-RAD 3''}');
    SectionCode.Clear;
    GenerateSection3(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 3''}');

    PasObject.Add(' '   );
    PasObject.Add('end;');
    PasObject.Add(' '   );

    PasObject.Add(Format('procedure Tmc%s.Assign(Source: TPersistent);', [TableId]));
    PasObject.Add('begin');
    PasObject.Add(Format('  if not (Source is Tmc%s) then', [TableId]));
    PasObject.Add('    inherited');
    PasObject.Add('  else'       );
    PasObject.Add(Format('    with Source as Tmc%s do', [TableId]));
    PasObject.Add('    begin');

    PasObject.Add('{$REGION ''DB-RAD 4''}');
    SectionCode.Clear;
    GenerateSection4(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 4''}');

    PasObject.Add('    end;');

    PasObject.Add(' '   );
    PasObject.Add('end;');
    PasObject.Add(' '   );

    PasObject.Add(Format('procedure Tmc%s.AssignI(const Value: Imc%s);', [TableId, TableId]));
    PasObject.Add('begin');

    PasObject.Add('{$REGION ''DB-RAD 5''}');
    SectionCode.Clear;
    GenerateSection5(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 5''}');

    PasObject.Add(' '   );
    PasObject.Add('end;');
    PasObject.Add(' '   );

    PasObject.Add(Format('procedure Tmc%s.AssignTo(Dest: TPersistent);', [TableId]));
    PasObject.Add('begin');
    PasObject.Add(Format('  if not (Dest is Tmc%s) then', [TableId]));
    PasObject.Add('    inherited');
    PasObject.Add('  else'       );
    PasObject.Add(Format('    with Dest as Tmc%s do', [TableId]));
    PasObject.Add('    begin');

    PasObject.Add('{$REGION ''DB-RAD 6''}');
    SectionCode.Clear;
    GenerateSection6(SectionCode);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 6''}');
    PasObject.Add       ('    end;'                 );

    PasObject.Add(' '   );
    PasObject.Add('end;');
    PasObject.Add(' '   );


    PasObject.Add('{$REGION ''DB-RAD 7''}');
    SectionCode.Clear;
    GenerateSection7(SectionCode, TableId);
    PasObject.AddStrings(SectionCode                );
    PasObject.Add       ('{$ENDREGION ''DB-RAD 7''}');

    PasObject.Add(' ');

    if TableId = 'FIB_FIELDS_INFO' then
    begin
      PasObject.Add(Format('function Tmc%s.Setup(const ATable, AField: string): Imc%s;            ', [TableId, TableId]));
      PasObject.Add('begin                                                                                           ');
      PasObject.Add('  Self.TABLE_NAME:= ATable;                                                                     ');
      PasObject.Add('  Self.FIELD_NAME:= AField;                                                                     ');
      PasObject.Add('  Result         := Self;                                                                       ');
      PasObject.Add('end;                                                                                            ');
      PasObject.Add('                                                                                                ');
    end;
    PasObject.Add('end.                     ');
  finally
    SectionCode.Free;
  end; // try
end; // procedure

procedure TOrmGenerator.GenerateSection1(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do
  begin
    if CurField.ISENUM then
      SectionCode.Add(Format('    f%s: %s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.ENUMTYPE.PadRight(PAD_TYPE)]))
    else
      SectionCode.Add(Format('    f%s: %s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.VAR_TYPE.PadRight(PAD_TYPE)]));
  end;
end;

procedure TOrmGenerator.GenerateSection10(SectionCode: TStringList);
var
  CurField: TOrmField;
  S       : string;
begin
  for CurField in FFieldList do
  begin
    S:= CurField.VAR_TYPE.ToLower;
    if CurField.VAR_TYPE = STPicture then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteStream(''%s'', f%s, f%s.Size);',
          [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName, CurField.GetCurrentFieldName]));
    end
    else if CurField.ISENUM then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s.ToByte);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'boolean' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'int64' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'integer' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'smallint' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'string' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tdate' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tdatetime' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tpicture' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'ttime' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tsqltimestampoffset' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tsqltimestamp' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'double' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tstringlist' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'byte' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tbytes' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tbcd' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.WriteB(f%s);', [CurField.GetCurrentFieldName]));
    end
    else
    begin
      SectionCode.Add(Format('  UNKNOWN TYPE ''%s'', f%s : TYPE:<%s>);', [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName, S]));
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection11(SectionCode: TStringList);
var
  CurField: TOrmField;
  S       : string;
begin
  for CurField in FFieldList do
  begin
    S:= CurField.VAR_TYPE.ToLower;
    if CurField.VAR_TYPE = STPicture then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.ReadStream(''%s'', f%s, StreamSize);', [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName]));
    end
    else if CurField.ISENUM then
    begin
      SectionCode.Add('  Result:= Result and AStream.Read(ByteTemp);');
      SectionCode.Add(Format('  %s:= %s.FromByte(ByteTemp);', [CurField.GetCurrentFieldName, CurField.ENUMTYPE]));
    end
    else if S = 'boolean' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'int64' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'integer' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'smallint' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'string' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tdate' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tdatetime' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tpicture' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'ttime' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tsqltimestampoffset' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tsqltimestamp' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'double' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tstringlist' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'byte' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else if S = 'tbytes' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s, %d);', [CurField.GetCurrentFieldName, CurField.FIELD_SIZE]));
    end
    else if S = 'tbcd' then
    begin
      SectionCode.Add(Format('  Result:= Result and AStream.Read(f%s);', [CurField.GetCurrentFieldName]));
    end
    else
    begin
      SectionCode.Add(Format('  UNKNOWN TYPE ''%s'', f%s : TYPE:<%s>);', [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName, S]));
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection14(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do
  begin
    if IsVarTypeCreatable(CurField.VAR_TYPE) then
      SectionCode.Add(Format('  f%s:= %s.Create;', [CurField.GetCurrentFieldName, CurField.VAR_TYPE]));
  end;
end;

procedure TOrmGenerator.GenerateSection15(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do
  begin
    if IsVarTypeCreatable(CurField.VAR_TYPE) then
      SectionCode.Add(Format('  f%s.Free;', [CurField.GetCurrentFieldName]));
  end;
end;


procedure TOrmGenerator.GenerateCLSectionKEY(SectionCode: TStringList; const TableName0: string);
var
  I         : Integer;
  CurField  : TOrmField;
  TableId : string;
  FmtParts  : string;
  ArgParts  : string;
  FmtSpec   : string;
  ArgExpr   : string;
  FieldN    : string;
begin
  TableId:= TableName0.Replace('$', '_');
  FmtParts:= '';
  ArgParts:= '';
  for I:= 0 to FKeyFields.Count - 1 do
  begin
    CurField:= LocateField (FKeyFields[I]);
    FieldN  := GetFieldName(FKeyFields[I]);
    if I > 0 then
    begin
      FmtParts:= FmtParts + '|';  // dl:ok concat-in-loop@15c6 -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      ArgParts:= ArgParts + ', ';  // dl:ok concat-in-loop@78b6 -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
    end;
    if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') then
    begin
      FmtSpec:= '%d';
      ArgExpr:= 'A' + FieldN;
    end
    else if CurField.FIELD_AS_TYPE.ToLower = 'aslargeint' then
    begin
      FmtSpec:= '%d';
      ArgExpr:= 'A' + FieldN;
    end
    else
    begin
      FmtSpec:= '%s';
      ArgExpr:= 'A' + FieldN;
    end;
    FmtParts:= FmtParts + FieldN + '=' + FmtSpec;
    ArgParts:= ArgParts + ArgExpr;  // dl:ok concat-in-loop@9a23 -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
  end; // for
  SectionCode.Add('  Result := TEncoding.UTF8.GetBytes(');
  SectionCode.Add(Format('    Format(''TABLE=%s|%s'', [%s]));', [TableId, FmtParts, ArgParts]));
end; // procedure

procedure TOrmGenerator.GenerateCLSectionLOAD(SectionCode: TStringList; const TableName0: string);
var
  I        : Integer;
  CurField : TOrmField;
  TableId: string;
  FieldN   : string;
begin
  TableId:= TableName0.Replace('$', '_');
  for I:= 0 to FKeyFields.Count - 1 do
  begin
    CurField:= LocateField (FKeyFields[I]);
    FieldN  := GetFieldName(FKeyFields[I]);
    if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') or (CurField.FIELD_AS_TYPE.ToLower = 'aslargeint') then
    begin
      SectionCode.Add(Format('  if Obj.%s <= 0 then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Load: %s must be > 0'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end
    else if (CurField.FIELD_AS_TYPE.ToLower = 'asstring') or (CurField.FIELD_AS_TYPE.ToLower = 'aswidestring') then
    begin
      SectionCode.Add(Format('  if Trim(Obj.%s) = '''' then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Load: %s must not be empty'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateCLSectionSAVE(SectionCode: TStringList; const TableName0: string);  // dl:ok duplicate-code@c2b0 -- REVIEWED 2026-11-17 v152 TTGEN: TableTools section generators differ only in emitted text; kept 1:1 with the ported source
var
  I        : Integer;
  CurField : TOrmField;
  TableId: string;
  FieldN   : string;
begin
  TableId:= TableName0.Replace('$', '_');
  for I:= 0 to FKeyFields.Count - 1 do
  begin
    CurField:= LocateField (FKeyFields[I]);
    FieldN  := GetFieldName(FKeyFields[I]);
    if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') or (CurField.FIELD_AS_TYPE.ToLower = 'aslargeint') then
    begin
      SectionCode.Add(Format('  if Obj.%s <= 0 then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Save: %s must be > 0'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end
    else if (CurField.FIELD_AS_TYPE.ToLower = 'asstring') or (CurField.FIELD_AS_TYPE.ToLower = 'aswidestring') then
    begin
      SectionCode.Add(Format('  if Trim(Obj.%s) = '''' then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Save: %s must not be empty'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateCLSectionDEL(SectionCode: TStringList; const TableName0: string);  // dl:ok duplicate-code@7072 -- REVIEWED 2026-11-17 v152 TTGEN: TableTools section generators differ only in emitted text; kept 1:1 with the ported source
var
  I        : Integer;
  CurField : TOrmField;
  TableId: string;
  FieldN   : string;
begin
  TableId:= TableName0.Replace('$', '_');
  for I:= 0 to FKeyFields.Count - 1 do
  begin
    CurField:= LocateField (FKeyFields[I]);
    FieldN  := GetFieldName(FKeyFields[I]);
    if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') or (CurField.FIELD_AS_TYPE.ToLower = 'aslargeint') then
    begin
      SectionCode.Add(Format('  if A%s <= 0 then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Delete: %s must be > 0'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end
    else if (CurField.FIELD_AS_TYPE.ToLower = 'asstring') or (CurField.FIELD_AS_TYPE.ToLower = 'aswidestring') then
    begin
      SectionCode.Add(Format('  if Trim(A%s) = '''' then', [FieldN]));
      SectionCode.Add('  begin');
      SectionCode.Add(Format('    Log(mtError, ''%s.Delete: %s must not be empty'');', [TableId, FieldN]));
      SectionCode.Add('    Exit;');
      SectionCode.Add('  end;'   );
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateCLSectionNEXTID(SectionCode: TStringList; const TableName0: string; HasGenerator: Boolean; const GenName: string);
var
  TableId: string;
begin
  TableId:= TableName0.Replace('$', '_');
  if HasGenerator then
  begin
    SectionCode.Add('  var Payload, RspPayload: TBytes;' );
    SectionCode.Add('  var RspHdr: TPipeMessageHeader;'  );
    SectionCode.Add('  var GLE: DWORD;'                  );
    SectionCode.Add('  Result := 0;'                     );
    SectionCode.Add('  if not FConnection.Connected then');
    SectionCode.Add('  begin'                            );
    SectionCode.Add(Format('    Log(mtError, ''%s.NextID: pipe not connected'');', [TableId]));
    SectionCode.Add('    Exit;');
    SectionCode.Add('  end;'   );
    SectionCode.Add(Format('  Payload := TEncoding.UTF8.GetBytes(''GEN=%s'');', [GenName]));
    SectionCode.Add('  GLE     := FConnection.ExecuteCommand(cmdNextID, Payload, RspHdr, RspPayload);');
    SectionCode.Add('  if GLE <> ERROR_SUCCESS then'                                                  );
    SectionCode.Add('  begin'                                                                         );
    SectionCode.Add(Format('    Log(mtError, Format(''%s.NextID: pipe error %%d - %%s'', [GLE, SysErrorMessage(GLE)]));', [TableId]));
    SectionCode.Add('    Exit;'                                                                      );
    SectionCode.Add('  end;'                                                                         );
    SectionCode.Add('  if (TCommandID(RspHdr.CommandID) = rspData) and (Length(RspPayload) = 8) then');
    SectionCode.Add('    Move(RspPayload[0], Result, SizeOf(Result))'                                );
    SectionCode.Add('  else'                                                                         );
    SectionCode.Add(Format('    Log(mtError, ''%s.NextID: unexpected server response'');', [TableId]));
  end // if
  else
  begin
    SectionCode.Add(Format('  // %s uses a composite key without a Firebird generator.', [TableId]));
    SectionCode.Add('  // Assign key fields manually before calling Save.');
    SectionCode.Add('  Result := 0;'                                      );
    SectionCode.Add(Format('  Log(mtWarning, ''%s.NextID: no generator - returning 0. Assign key fields manually.'');', [TableId]));
  end;
end; // procedure

procedure TOrmGenerator.GenerateNewClientObject(const TableName0: string; PasObject: TStringList);  // dl:ok method-too-long@a378 -- REVIEWED 2026-11-17 v152 TTGEN: verbatim TableTools generator (one Add per emitted line); splitting it risks the byte-identical output
var
  SectionCode  : TStringList;
  TableId    : string;
  HasGenerator : Boolean;
  GenName      : string;
  I            : Integer;
  CurField     : TOrmField;
  KeyParamSig  : string; // 'const AChannel: Integer; const AComputer: string'
  KeyArgFromObj: string; // 'Obj.CHANNEL, Obj.COMPUTER'
  KeyArgDirect : string; // 'AChannel, AComputer'
  KeyLogFmt    : string; // 'CHANNEL=%d COMPUTER=%s'
  KeyLogArgObj : string; // 'Obj.CHANNEL, Obj.COMPUTER' (log Format args in Load/Save)
  KeyLogArgDir : string; // 'AChannel, AComputer'       (log Format args in Delete)
  ParamType    : string;
  FmtSpec      : string;
  FieldN       : string;
  HasTimestamp : Boolean;
  TSField      : TOrmField;
begin
  TableId:= TableName0.Replace('$', '_');
  LoadTable(TableName0);
  HasGenerator:= FHasGenerator;
  GenName:= FGenName;

  HasTimestamp:= False;
  for TSField in FFieldList do if SameText(TSField.VAR_TYPE, 'TSQLTimeStamp') then
  begin
    HasTimestamp:= True;
    Break;
  end;

  KeyParamSig  := '';
  KeyArgFromObj:= '';
  KeyArgDirect := '';
  KeyLogFmt    := '';
  KeyLogArgObj := '';
  KeyLogArgDir := '';
  for I:= 0 to FKeyFields.Count - 1 do
  begin
    CurField:= LocateField (FKeyFields[I]);
    FieldN  := GetFieldName(FKeyFields[I]);
    if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') then
    begin
      ParamType:= 'Integer';
      FmtSpec  := '%d';
    end
    else if CurField.FIELD_AS_TYPE.ToLower = 'aslargeint' then
    begin
      ParamType:= 'Int64';
      FmtSpec  := '%d';
    end
    else if CurField.ISENUM or (CurField.FIELD_AS_TYPE.ToLower = 'asbyte') then
    begin
      ParamType:= 'Byte';
      FmtSpec  := '%d';
    end
    else
    begin
      ParamType:= 'string';
      FmtSpec  := '%s';
    end;
    if I > 0 then
    begin
      KeyParamSig  := KeyParamSig   + '; ';  // dl:ok concat-in-loop@ca22 -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      KeyArgFromObj:= KeyArgFromObj + ', ';  // dl:ok concat-in-loop@5d8c -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      KeyArgDirect := KeyArgDirect  + ', ';  // dl:ok concat-in-loop@628a -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      KeyLogFmt    := KeyLogFmt     + ' ';  // dl:ok concat-in-loop@36f0 -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      KeyLogArgObj := KeyLogArgObj  + ', ';  // dl:ok concat-in-loop@485e -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
      KeyLogArgDir := KeyLogArgDir  + ', ';  // dl:ok concat-in-loop@aeca -- REVIEWED 2026-11-17 v152 TTGEN: ported TableTools string building over a handful of key fields; kept 1:1
    end;
    KeyParamSig:= KeyParamSig + 'const A' + FieldN + ': ' + ParamType;
    if SameText(CurField.VAR_TYPE, 'TSQLTimeStamp') then
    begin
      KeyArgFromObj:= KeyArgFromObj + 'SQLTimeStampToStr(''YYYY-MM-DD HH:NN:SS'', Obj.' + FieldN + ')';
      KeyLogArgObj := KeyLogArgObj  + 'SQLTimeStampToStr(''YYYY-MM-DD HH:NN:SS'', Obj.' + FieldN + ')';
    end
    else if CurField.ISENUM then
    begin
      KeyArgFromObj:= KeyArgFromObj + 'Byte(Obj.' + FieldN + ')';
      KeyLogArgObj := KeyLogArgObj  + 'Byte(Obj.' + FieldN + ')';
    end
    else
    begin
      KeyArgFromObj:= KeyArgFromObj + 'Obj.' + FieldN;
      KeyLogArgObj := KeyLogArgObj  + 'Obj.' + FieldN;
    end;
    KeyArgDirect:= KeyArgDirect + 'A' + FieldN;
    KeyLogFmt:= KeyLogFmt + FieldN + '=' + FmtSpec;
    KeyLogArgDir:= KeyLogArgDir + 'A' + FieldN;
  end; // for

  SectionCode:= TStringList.Create;
  try
    PasObject.Add(Format('unit u%s_CLIENT;', [TableId]));
    PasObject.Add('');
    PasObject.Add(Format('// %s CLIENT-side data service.', [TableId]));
    PasObject.Add('//');
    PasObject.Add(Format('// Implements IDataService<Imc%s> using the Micronite named pipe.', [TableId]));
    PasObject.Add('// Replaces FireDAC with pipe transport + TABZMemoryStream serialization.');
    PasObject.Add('//'                                                                       );
    PasObject.Add('// Pipe payload format:'                                                  );
    PasObject.Add(Format('//   Load   cmdLoad  (100): TABLE=%s|KEY1=v|...'                , [TableId]));
    PasObject.Add(Format('//   Save   cmdSave  (101): TABLE=%s| + serialized object bytes', [TableId]));
    PasObject.Add(Format('//   Delete cmdDelete(102): TABLE=%s|KEY1=v|...'                , [TableId]));
    if HasGenerator then
      PasObject.Add(Format('//   NextID cmdNextID: GEN=%s - server returns 8-byte Int64', [GenName]))
    else
      PasObject.Add(Format('//   NextID: %s uses composite key i?? no generator, always returns 0', [TableId]));
    PasObject.Add('//'                                                                  );
    PasObject.Add('// TPipeClientConnection is SHARED i?? this service does not own it.');
    PasObject.Add(''                                                                    );
    PasObject.Add('interface'                                                           );
    PasObject.Add(''                                                                    );
    PasObject.Add('uses'                                                                );
    PasObject.Add('  System.SysUtils,'                                                  );
    PasObject.Add('  System.Classes,'                                                   );
    PasObject.Add('  Winapi.Windows,'                                                   );
    PasObject.Add(Format('  i%s,', [TableId]));
    PasObject.Add('  IuMicObject,'          );
    PasObject.Add('  uPipeClientConnection,');
    PasObject.Add('  iLoggingServiceP,'     );
    PasObject.Add('  MStreams,'             );
    if HasTimestamp then
      PasObject.Add('  Data.SqlTimSt,' );
    PasObject  .Add('  Pipes.Protocol;');
    PasObject  .Add(''                 );
    PasObject  .Add('type'             );
    PasObject.Add(Format('  TDataService_%s_CLIENT = class(TInterfacedObject,', [TableId]));
    PasObject.Add('    IDataService,');
    PasObject.Add(Format('    IDataService<Imc%s>)', [TableId]));
    PasObject.Add('  private'                                                                    );
    PasObject.Add('    FConnection   : TPipeClientConnection;  // shared reference i?? not owned');
    PasObject.Add('    FLogger       : IABZLoggingSys;'                                          );
    PasObject.Add('    FThreadStorage: IThreadStorage;'                                          );
    PasObject.Add(''                                                                             );
    PasObject.Add('    procedure Log(AType: TMessageType; const AMsg: string);'                  );
    PasObject.Add('    procedure HandleErrorResponse(const ARspHdr    : TPipeMessageHeader;'     );
    PasObject.Add('                                  const ARspPayload: TBytes;'                 );
    PasObject.Add('                                  const AContext   : string);'                );
    PasObject.Add(Format('    function  BuildKeyPayload(%s): TBytes;', [KeyParamSig]));
    PasObject.Add('  public'                                                  );
    PasObject.Add('    constructor Create(AConnection: TPipeClientConnection;');
    PasObject.Add('                       ALogger    : IABZLoggingSys = nil);');
    PasObject.Add('    destructor Destroy; override;'                         );
    PasObject.Add(''                                                          );
    PasObject.Add(Format('    // ---- IDataService<Imc%s> ----', [TableId]));
    PasObject.Add('    function  GetThreadStorage: IThreadStorage;'             );
    PasObject.Add('    procedure SetThreadStorage(const Value: IThreadStorage);');
    PasObject.Add('    property  ThreadStorage: IThreadStorage'                 );
    PasObject.Add('                read  GetThreadStorage'                      );
    PasObject.Add('                write SetThreadStorage;'                     );
    PasObject.Add(''                                                            );
    PasObject.Add(Format('    function Load(const Obj: Imc%s): Boolean; overload;', [TableId]));
    PasObject.Add(Format('    function Save(const Obj: Imc%s): Boolean; overload;', [TableId]));
    PasObject.Add('    function NextID: Int64;');
    PasObject.Add(Format('    function Delete(%s): Boolean;', [KeyParamSig]));
    PasObject.Add('  end;'        );
    PasObject.Add(''              );
    PasObject.Add('implementation');
    PasObject.Add(''              );
    PasObject.Add('const'         );
    PasObject.Add(Format('  TABLE_PREFIX = ''TABLE=%s'';', [TableId]));
    PasObject.Add('');
    PasObject.Add(Format('{ TDataService_%s_CLIENT }', [TableId]));
    PasObject.Add('');
    PasObject.Add(Format('constructor TDataService_%s_CLIENT.Create(AConnection: TPipeClientConnection;', [TableId]));
    PasObject.Add('  ALogger: IABZLoggingSys);'     );
    PasObject.Add('begin'                           );
    PasObject.Add('  inherited Create;'             );
    PasObject.Add('  FConnection    := AConnection;');
    PasObject.Add('  FLogger        := ALogger;'    );
    PasObject.Add('  FThreadStorage := nil;'        );
    PasObject.Add('end;'                            );
    PasObject.Add(''                                );
    PasObject.Add(Format('destructor TDataService_%s_CLIENT.Destroy;', [TableId]));
    PasObject.Add('begin'                                                                     );
    PasObject.Add('  // FConnection is NOT freed here i?? it is owned by the caller'          );
    PasObject.Add('  inherited;'                                                              );
    PasObject.Add('end;'                                                                      );
    PasObject.Add(''                                                                          );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add('// Helpers'                                                                );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add(''                                                                          );
    PasObject.Add(Format('procedure TDataService_%s_CLIENT.Log(AType: TMessageType; const AMsg: string);', [TableId]));
    PasObject.Add('begin'                                  );
    PasObject.Add('  if Assigned(FLogger) then'            );
    PasObject.Add('    FLogger.LogMessage(AType, AMsg, 1);');
    PasObject.Add('end;'                                   );
    PasObject.Add(''                                       );
    PasObject.Add(Format('procedure TDataService_%s_CLIENT.HandleErrorResponse(', [TableId]));
    PasObject.Add('  const ARspHdr    : TPipeMessageHeader;'                                       );
    PasObject.Add('  const ARspPayload: TBytes;'                                                   );
    PasObject.Add('  const AContext   : string);'                                                  );
    PasObject.Add('var'                                                                            );
    PasObject.Add('  ErrMsg: string;'                                                              );
    PasObject.Add('begin'                                                                          );
    PasObject.Add('  ErrMsg := '''';'                                                              );
    PasObject.Add('  if Length(ARspPayload) > 0 then'                                              );
    PasObject.Add('    ErrMsg := TEncoding.UTF8.GetString(ARspPayload);'                           );
    PasObject.Add('  Log(mtError,'                                                                 );
    PasObject.Add('    Format(''%s: server returned %s i?? %s'','                                  );
    PasObject.Add('           [AContext, CommandIDToStr(TCommandID(ARspHdr.CommandID)), ErrMsg]));');
    PasObject.Add('end;'                                                                           );
    PasObject.Add(''                                                                               );
    PasObject.Add(Format('function TDataService_%s_CLIENT.BuildKeyPayload(%s): TBytes;', [TableId, KeyParamSig]));
    PasObject.Add('begin'                      );
    PasObject.Add('{$REGION ''DB-RAD CL-KEY''}');
    SectionCode.Clear;
    GenerateCLSectionKEY(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                                                                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD CL-KEY''}'                                            );
    PasObject.Add       ('end;'                                                                      );
    PasObject.Add       (''                                                                          );
    PasObject.Add       ('// -----------------------------------------------------------------------');
    PasObject.Add       ('// IDataService<...> i?? ThreadStorage (satisfies interface; unused here)' );
    PasObject.Add       ('// -----------------------------------------------------------------------');
    PasObject.Add       (''                                                                          );
    PasObject.Add(Format('function TDataService_%s_CLIENT.GetThreadStorage: IThreadStorage;', [TableId]));
    PasObject.Add('begin'                      );
    PasObject.Add('  Result := FThreadStorage;');
    PasObject.Add('end;'                       );
    PasObject.Add(''                           );
    PasObject.Add(Format('procedure TDataService_%s_CLIENT.SetThreadStorage(const Value: IThreadStorage);', [TableId]));
    PasObject.Add('begin'                                                                     );
    PasObject.Add('  FThreadStorage := Value;'                                                );
    PasObject.Add('end;'                                                                      );
    PasObject.Add(''                                                                          );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add('// Load'                                                                   );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add(''                                                                          );
    PasObject.Add(Format('function TDataService_%s_CLIENT.Load(const Obj: Imc%s): Boolean;', [TableId, TableId]));
    PasObject.Add('var'                              );
    PasObject.Add('  Payload   : TBytes;'            );
    PasObject.Add('  RspHdr    : TPipeMessageHeader;');
    PasObject.Add('  RspPayload: TBytes;'            );
    PasObject.Add('  GLE       : DWORD;'             );
    PasObject.Add('  MS        : TABZMemoryStream;'  );
    PasObject.Add('begin'                            );
    PasObject.Add('  Result := False;'               );
    PasObject.Add(''                                 );
    PasObject.Add('{$REGION ''DB-RAD CL-LOAD''}'     );
    SectionCode.Clear;
    GenerateCLSectionLOAD(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                          );
    PasObject.Add       ('{$ENDREGION ''DB-RAD CL-LOAD''}'    );
    PasObject.Add       (''                                   );
    PasObject.Add       ('  if not FConnection.Connected then');
    PasObject.Add       ('  begin'                            );
    PasObject.Add(Format('    Log(mtError, ''%s.Load: pipe not connected'');', [TableId]));
    PasObject.Add('    Exit;');
    PasObject.Add('  end;'   );
    PasObject.Add(''         );
    PasObject.Add(Format('  Payload := BuildKeyPayload(%s);', [KeyArgFromObj]));
    PasObject.Add('  GLE     := FConnection.ExecuteCommand(cmdLoad, Payload, RspHdr, RspPayload);');
    PasObject.Add('  if GLE <> ERROR_SUCCESS then'                                                );
    PasObject.Add('  begin'                                                                       );
    PasObject.Add(Format('    Log(mtError, Format(''%s.Load: pipe error %%d - %%s'', [GLE, SysErrorMessage(GLE)]));', [TableId]));
    PasObject.Add('    Exit;'                                           );
    PasObject.Add('  end;'                                              );
    PasObject.Add(''                                                    );
    PasObject.Add('  if TCommandID(RspHdr.CommandID) = rspNotFound then');
    PasObject.Add('  begin'                                             );
    PasObject.Add(Format('    Log(mtInfo, Format(''%s.Load: not found - %s'', [%s]));', [TableId, KeyLogFmt, KeyLogArgObj]));
    PasObject.Add('    Exit;'                                        );
    PasObject.Add('  end;'                                           );
    PasObject.Add(''                                                 );
    PasObject.Add('  if TCommandID(RspHdr.CommandID) <> rspData then');
    PasObject.Add('  begin'                                          );
    PasObject.Add(Format('    HandleErrorResponse(RspHdr, RspPayload, ''%s.Load'');', [TableId]));
    PasObject.Add('    Exit;'                                               );
    PasObject.Add('  end;'                                                  );
    PasObject.Add(''                                                        );
    PasObject.Add('  MS := TABZMemoryStream.Create;'                        );
    PasObject.Add('  try'                                                   );
    PasObject.Add('    if Length(RspPayload) > 0 then'                      );
    PasObject.Add('      MS.WriteBuffer(RspPayload[0], Length(RspPayload));');
    PasObject.Add('    MS.Position := 0;'                                   );
    PasObject.Add('    Result      := Obj.Reader(MS);'                      );
    PasObject.Add('  finally'                                               );
    PasObject.Add('    MS.Free;'                                            );
    PasObject.Add('  end;'                                                  );
    PasObject.Add(''                                                        );
    PasObject.Add('  if Result then'                                        );
    PasObject.Add('  begin'                                                 );
    PasObject.Add('    Obj.Modified := False;'                              );
    PasObject.Add(Format('    Log(mtInfo, Format(''%s.Load OK - %s'', [%s]));', [TableId, KeyLogFmt, KeyLogArgObj]));
    PasObject.Add('  end' );
    PasObject.Add('  else');
    PasObject.Add(Format('    Log(mtError, ''%s.Load: Reader returned False'');', [TableId]));
    PasObject.Add('end;'                                                                      );
    PasObject.Add(''                                                                          );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add('// Save'                                                                   );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add(''                                                                          );
    PasObject.Add(Format('function TDataService_%s_CLIENT.Save(const Obj: Imc%s): Boolean;', [TableId, TableId]));
    PasObject.Add('var'                              );
    PasObject.Add('  MS        : TABZMemoryStream;'  );
    PasObject.Add('  Prefix    : TBytes;'            );
    PasObject.Add('  Payload   : TBytes;'            );
    PasObject.Add('  RspHdr    : TPipeMessageHeader;');
    PasObject.Add('  RspPayload: TBytes;'            );
    PasObject.Add('  GLE       : DWORD;'             );
    PasObject.Add('  ObjSize   : Integer;'           );
    PasObject.Add('begin'                            );
    PasObject.Add('  Result := False;'               );
    PasObject.Add(''                                 );
    PasObject.Add('{$REGION ''DB-RAD CL-SAVE''}'     );
    SectionCode.Clear;
    GenerateCLSectionSAVE(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                          );
    PasObject.Add       ('{$ENDREGION ''DB-RAD CL-SAVE''}'    );
    PasObject.Add       (''                                   );
    PasObject.Add       ('  if not FConnection.Connected then');
    PasObject.Add       ('  begin'                            );
    PasObject.Add(Format('    Log(mtError, ''%s.Save: pipe not connected'');', [TableId]));
    PasObject.Add('    Exit;'                       );
    PasObject.Add('  end;'                          );
    PasObject.Add(''                                );
    PasObject.Add('  MS := TABZMemoryStream.Create;');
    PasObject.Add('  try'                           );
    PasObject.Add('    if not Obj.Writer(MS) then'  );
    PasObject.Add('    begin'                       );
    PasObject.Add(Format('      Log(mtError, ''%s.Save: Writer returned False'');', [TableId]));
    PasObject.Add('      Exit;'                                                               );
    PasObject.Add('    end;'                                                                  );
    PasObject.Add('    ObjSize := Integer(MS.Size);'                                          );
    PasObject.Add('    Prefix  := TEncoding.UTF8.GetBytes(TABLE_PREFIX + ''|'');'             );
    PasObject.Add('    SetLength(Payload, Length(Prefix) + ObjSize);'                         );
    PasObject.Add('    Move(Prefix[0], Payload[0], Length(Prefix));'                          );
    PasObject.Add('    MS.Position := 0;'                                                     );
    PasObject.Add('    MS.ReadBuffer(Payload[Length(Prefix)], ObjSize);'                      );
    PasObject.Add('  finally'                                                                 );
    PasObject.Add('    MS.Free;'                                                              );
    PasObject.Add('  end;'                                                                    );
    PasObject.Add(''                                                                          );
    PasObject.Add('  GLE := FConnection.ExecuteCommand(cmdSave, Payload, RspHdr, RspPayload);');
    PasObject.Add('  if GLE <> ERROR_SUCCESS then'                                            );
    PasObject.Add('  begin'                                                                   );
    PasObject.Add(Format('    Log(mtError, Format(''%s.Save: pipe error %%d - %%s'', [GLE, SysErrorMessage(GLE)]));', [TableId]));
    PasObject.Add('    Exit;'                                      );
    PasObject.Add('  end;'                                         );
    PasObject.Add(''                                               );
    PasObject.Add('  if TCommandID(RspHdr.CommandID) <> rspOK then');
    PasObject.Add('  begin'                                        );
    PasObject.Add(Format('    HandleErrorResponse(RspHdr, RspPayload, ''%s.Save'');', [TableId]));
    PasObject.Add('    Exit;'               );
    PasObject.Add('  end;'                  );
    PasObject.Add(''                        );
    PasObject.Add('  Obj.Modified := False;');
    PasObject.Add('  Result       := True;' );
    PasObject.Add(Format('  Log(mtInfo, Format(''%s.Save OK - %s'', [%s]));', [TableId, KeyLogFmt, KeyLogArgObj]));
    PasObject.Add('end;'                                                                      );
    PasObject.Add(''                                                                          );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add('// NextID'                                                                 );
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add(''                                                                          );
    PasObject.Add(Format('function TDataService_%s_CLIENT.NextID: Int64;', [TableId]));
    PasObject.Add('begin'                         );
    PasObject.Add('{$REGION ''DB-RAD CL-NEXTID''}');
    SectionCode.Clear;
    GenerateCLSectionNEXTID(SectionCode, TableName0, HasGenerator, GenName);
    PasObject.AddStrings(SectionCode                                                                 );
    PasObject.Add       ('{$ENDREGION ''DB-RAD CL-NEXTID''}'                                         );
    PasObject.Add       ('end;'                                                                      );
    PasObject.Add       (''                                                                          );
    PasObject.Add       ('// -----------------------------------------------------------------------');
    PasObject.Add(Format('// Delete  (convenience i?? not part of IDataService<Imc%s> interface)', [TableId]));
    PasObject.Add('// -----------------------------------------------------------------------');
    PasObject.Add(''                                                                          );
    PasObject.Add(Format('function TDataService_%s_CLIENT.Delete(%s): Boolean;', [TableId, KeyParamSig]));
    PasObject.Add('var'                              );
    PasObject.Add('  Payload   : TBytes;'            );
    PasObject.Add('  RspHdr    : TPipeMessageHeader;');
    PasObject.Add('  RspPayload: TBytes;'            );
    PasObject.Add('  GLE       : DWORD;'             );
    PasObject.Add('begin'                            );
    PasObject.Add('  Result := False;'               );
    PasObject.Add(''                                 );
    PasObject.Add('{$REGION ''DB-RAD CL-DEL''}'      );
    SectionCode.Clear;
    GenerateCLSectionDEL(SectionCode, TableName0);
    PasObject.AddStrings(SectionCode                          );
    PasObject.Add       ('{$ENDREGION ''DB-RAD CL-DEL''}'     );
    PasObject.Add       (''                                   );
    PasObject.Add       ('  if not FConnection.Connected then');
    PasObject.Add       ('  begin'                            );
    PasObject.Add(Format('    Log(mtError, ''%s.Delete: pipe not connected'');', [TableId]));
    PasObject.Add('    Exit;');
    PasObject.Add('  end;'   );
    PasObject.Add(''         );
    PasObject.Add(Format('  Payload := BuildKeyPayload(%s);', [KeyArgDirect]));
    PasObject.Add('  GLE     := FConnection.ExecuteCommand(cmdDelete, Payload, RspHdr, RspPayload);');
    PasObject.Add('  if GLE <> ERROR_SUCCESS then'                                                  );
    PasObject.Add('  begin'                                                                         );
    PasObject.Add(Format('    Log(mtError, Format(''%s.Delete: pipe error %%d - %%s'', [GLE, SysErrorMessage(GLE)]));', [TableId]));
    PasObject.Add('    Exit;'                                           );
    PasObject.Add('  end;'                                              );
    PasObject.Add(''                                                    );
    PasObject.Add('  if TCommandID(RspHdr.CommandID) = rspNotFound then');
    PasObject.Add('  begin'                                             );
    PasObject.Add(Format('    Log(mtInfo, Format(''%s.Delete: not found - %s'', [%s]));', [TableId, KeyLogFmt, KeyLogArgDir]));
    PasObject.Add('    Exit;'                                      );
    PasObject.Add('  end;'                                         );
    PasObject.Add(''                                               );
    PasObject.Add('  if TCommandID(RspHdr.CommandID) <> rspOK then');
    PasObject.Add('  begin'                                        );
    PasObject.Add(Format('    HandleErrorResponse(RspHdr, RspPayload, ''%s.Delete'');', [TableId]));
    PasObject.Add('    Exit;'        );
    PasObject.Add('  end;'           );
    PasObject.Add(''                 );
    PasObject.Add('  Result := True;');
    PasObject.Add(Format('  Log(mtInfo, Format(''%s.Delete OK - %s'', [%s]));', [TableId, KeyLogFmt, KeyLogArgDir]));
    PasObject.Add('end;');
    PasObject.Add(''    );
    PasObject.Add('end.');
  finally
    SectionCode.Free;
  end; // try
end; // procedure

procedure TOrmGenerator.GenerateSection2I(SectionCode: TStringList);
var
  CurField: TOrmField;
  RealType: string;
  SS      : string;
begin
  for CurField in FFieldList do
  begin
    RealType:= if CurField.ISENUM then CurField.ENUMTYPE else CurField.VAR_TYPE;
    SectionCode.Add(Format('    function Get%s: %s;', [AccessorName(CurField.GetCurrentFieldName).PadRight(PAD_NAME), RealType]));
    SectionCode.Add(Format('    procedure Set%s(const Value: %s);', [AccessorName(CurField.GetCurrentFieldName), RealType]));
    SectionCode.Add('{$REGION ''Documentation''}');

    if CurField.DOC_SUMMARY.Count > 0 then
    begin
      SectionCode.Add('/// <summary>              ');
      for SS in CurField.DOC_SUMMARY do SectionCode.Add(Format('/// %s', [SS]));
      SectionCode.Add('/// </summary>             ');
    end;
    if CurField.DOC_REMARKS.Count > 0 then
    begin
      SectionCode.Add('/// <remarks>              ');
      for SS in CurField.DOC_REMARKS do SectionCode.Add(Format('    /// %s', [SS]));
      SectionCode.Add('/// </remarks>             ');
    end;
    SectionCode.Add('{$ENDREGION}               ');
    SectionCode.Add(Format('    property %s: %s read Get%s write Set%s; ', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), RealType.PadRight(PAD_NAME),
          AccessorName(CurField.GetCurrentFieldName).PadRight(PAD_NAME), AccessorName(CurField.GetCurrentFieldName).PadRight(PAD_NAME)]));
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection2P(SectionCode: TStringList);
var
  CurField: TOrmField;
  RealType: string;
  SS      : string;
begin
  for CurField in FFieldList do
  begin

    RealType:= if CurField.ISENUM then CurField.ENUMTYPE else CurField.VAR_TYPE;  // dl:ok duplicate-code@2407 -- REVIEWED 2026-11-17 v152 TTGEN: TableTools section generators differ only in emitted text; kept 1:1 with the ported source
    SectionCode.Add('{$REGION ''Documentation''}		');
    if CurField.DOC_SUMMARY.Count > 0 then
    begin
      SectionCode.Add('/// <summary>                ');
      for SS in CurField.DOC_SUMMARY do SectionCode.Add(Format('/// %s', [SS]));
      SectionCode.Add('/// </summary>               ');
    end;
    if CurField.DOC_REMARKS.Count > 0 then
    begin
      SectionCode.Add('/// <remarks>                ');
      for SS in CurField.DOC_REMARKS do SectionCode.Add(Format('/// %s', [SS]));
      SectionCode.Add('/// </remarks>               ');
    end;
    SectionCode.Add('{$ENDREGION}                 ');
    SectionCode.Add(Format('    property %s: %s read Get%s write Set%s; ',
        [CurField.GetCurrentFieldName.PadRight(PAD_NAME), RealType, AccessorName(CurField.GetCurrentFieldName), AccessorName(CurField.GetCurrentFieldName)]));
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection1A(SectionCode: TStringList);
var
  CurField: TOrmField;
  RealType: string;
begin
  for CurField in FFieldList do
  begin
    RealType:= if CurField.ISENUM then CurField.ENUMTYPE else CurField.VAR_TYPE;
    SectionCode.Add(Format('    function Get%s: %s;', [AccessorName(CurField.GetCurrentFieldName).PadRight(PAD_NAME), RealType]));
    SectionCode.Add(Format('    procedure Set%s(const Value: %s);', [AccessorName(CurField.GetCurrentFieldName), RealType]));
  end;
end;

procedure TOrmGenerator.GenerateSection3(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do
  begin
    if Length(Trim(CurField.DEFAULTVAL)) > 0 then
    begin
      if CurField.VAR_TYPE.ToUpper = 'TTIME' then
        SectionCode.Add(Format('    f%s:= StrToTime(%s);', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]))
      else if CurField.VAR_TYPE.ToUpper = 'TDATE' then
        SectionCode.Add(Format('    f%s:= StrToDate(%s);', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]))
      else if CurField.VAR_TYPE.ToUpper = 'TDATETIME' then
        SectionCode.Add(Format('    f%s:= StrToDateTime(%s);', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]))
      else if CurField.VAR_TYPE.ToUpper = 'TSQLTIMESTAMP' then
      if ZeroTime(CurField.DEFAULTVAL) then
        SectionCode.Add(Format('    f%s:= NullSQLTimeStamp;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME)]))
      else
        SectionCode.Add(Format('    f%s:= StrToSQLTimeStamp(''%s'');', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]))
      else if CurField.VAR_TYPE.ToUpper = 'DOUBLE' then
      if ZeroTime(CurField.DEFAULTVAL) then
        SectionCode.Add(Format('    f%s:= 0;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME)]))
      else
        SectionCode.Add(Format('    f%s:= %s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]))
      else
        SectionCode.Add(Format('    f%s:= %s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.DEFAULTVAL]));
    end // if
    else
    begin
      if CurField.VAR_TYPE.ToUpper = 'TSQLTIMESTAMP' then
        SectionCode.Add(Format('    f%s:= NullSQLTimeStamp;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME)]))
      else if CurField.VAR_TYPE.ToUpper = 'DOUBLE' then
        SectionCode.Add(Format('    f%s:= 0;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME)]))
    end;
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection4(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do SectionCode.Add(Format('      f%s:= %s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.GetCurrentFieldName.PadRight(PAD_NAME)]));
end;

procedure TOrmGenerator.GenerateSection5(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do SectionCode.Add(Format('    f%s:= Value.%s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.GetCurrentFieldName.PadRight(PAD_NAME)]));
end;

procedure TOrmGenerator.GenerateSection6(SectionCode: TStringList);
var
  CurField: TOrmField;
begin
  for CurField in FFieldList do SectionCode.Add(Format('      %s:= f%s;', [CurField.GetCurrentFieldName.PadRight(PAD_NAME), CurField.GetCurrentFieldName.PadRight(PAD_NAME)]));
end;

procedure TOrmGenerator.GenerateSection7(SectionCode: TStringList; const TableId: string);
var
  CurField: TOrmField;
  RealType: string;
begin
  for CurField in FFieldList do
  begin
    RealType:= if CurField.ISENUM then CurField.ENUMTYPE else CurField.VAR_TYPE;
    SectionCode.Add(Format('function Tmc%s.Get%s: %s;', [TableId, AccessorName(CurField.GetCurrentFieldName), RealType]));
    SectionCode.Add('begin');
    SectionCode.Add(Format('  result:= f%s;', [CurField.GetCurrentFieldName]));
    SectionCode.Add('end;');
    SectionCode.Add(' '   );
    SectionCode.Add(Format('procedure Tmc%s.Set%s(const Value: %s);', [TableId, AccessorName(CurField.GetCurrentFieldName), RealType]));
    SectionCode.Add('begin');
    SectionCode.Add(Format('  f%s:= Value;', [CurField.GetCurrentFieldName]));
    SectionCode.Add('  fModified:= True;');
    SectionCode.Add('end;'               );
    SectionCode.Add(' '                  );
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection8A(SectionCode: TStringList; TableName0: string);
var
  CurField: TOrmField;
  I       : Integer;
  S       : string;
  SBFields: TStringBuilder;
  SBKeys  : TStringBuilder;
begin
  SBFields:= TStringBuilder.Create(' ');
  SBKeys  := TStringBuilder.Create(' ');
  try
    if FKeyFields.Count > 0 then
    begin
      SBKeys.Append(' WHERE (');
      for I:= 0 to FKeyFields.Count - 1 do
      begin
        if I > 0 then
          SBKeys.Append(' AND ');
        SBKeys.Append(Format(' (%s = :%s) ', [FKeyFields[I], GetFieldName(FKeyFields[I])]));
      end;
      SBKeys.Append(' )');
    end;
    SectionCode.Add('     QRYLoad.SQL.Add(''SELECT '');');

    for CurField in FFieldList do
    begin
      if SBFields.Length > 1 then
        SBFields.Append(', ');
      SBFields.Append(Format(' %s AS %s', [CurField.FIELD_NAME, CurField.GetCurrentFieldName]));
    end;
    if SBFields.Length <= MAX_LITERAL_CHUNK then
      SectionCode.Add(Format('     QRYLoad.SQL.Add(''%s'');', [SBFields.ToString]))
    else
    begin
      S:= ToLiteral(SBFields);
      SectionCode.Add(Format('     var sTmp: string := %s;', [S]));
      SectionCode.Add('     QRYLoad.SQL.Add(sTmp);')
    end;
    SectionCode.Add(Format('     QRYLoad.SQL.Add(''FROM %s'');', [TableName0]));
    SectionCode.Add(Format('     QRYLoad.SQL.Add(''%s'');', [SBKeys.ToString]));
    SectionCode.Add('      QRYLoad.Prepare;');
  finally
    SBKeys.Free;
    SBFields.Free;
  end; // try
end; // procedure

procedure TOrmGenerator.GenerateSection8(SectionCode: TStringList; TableName0: string);
var
  CurField: TOrmField;
  I       : Integer;
begin
  if FKeyFields.Count > 0 then
  begin
    SectionCode.Add('      var STmp: string := '''';');
    for I:= 0 to FKeyFields.Count - 1 do
    begin
      CurField:= LocateField(FKeyFields[I]);
      if CurField.ISENUM then
      begin
        SectionCode.Add(Format('      if Ord(Obj.%s) <= 0 then', [GetFieldName(FKeyFields[I])]));
        SectionCode.Add(Format('        if STmp <> '''' then STmp := STmp + '', %s'' else STmp := ''%s'';', [GetFieldName(FKeyFields[I]), GetFieldName(FKeyFields[I])]));
      end
      else if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'aslargeint') or
      (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') or (CurField.FIELD_AS_TYPE.ToLower = 'asbyte') then
      begin
        SectionCode.Add(Format('      if Obj.%s <= 0 then', [GetFieldName(FKeyFields[I])]));
        SectionCode.Add(Format('        if STmp <> '''' then STmp := STmp + '', %s'' else STmp := ''%s'';', [GetFieldName(FKeyFields[I]), GetFieldName(FKeyFields[I])]));
      end
      else if (CurField.FIELD_AS_TYPE.ToLower = 'asstring') or (CurField.FIELD_AS_TYPE.ToLower = 'aswidestring') then
      begin
        SectionCode.Add(Format('      if Length(Trim(Obj.%s)) = 0 then', [GetFieldName(FKeyFields[I])]));
        SectionCode.Add(Format('        if STmp <> '''' then STmp := STmp + '', %s'' else STmp := ''%s'';', [GetFieldName(FKeyFields[I]), GetFieldName(FKeyFields[I])]));
      end;
    end; // for
    SectionCode.Add('      if STmp <> '''' then');
    SectionCode.Add(Format('        raise EUndefinedKeyValue.CreateFmt(''Key field(s) <%%s> are not set. Cannot Load from %s'', [STmp]);', [TableName0]));
    for I:= 0 to FKeyFields.Count - 1 do
    begin
      CurField:= LocateField(FKeyFields[I]);
      if CurField.ISENUM then
        SectionCode.Add(Format('      QRYLoad.ParamByName(''%s'').%s:= Obj.%s.ToByte ;', [GetFieldName(FKeyFields[I]), CurField.FIELD_AS_TYPE, GetFieldName(FKeyFields[I])]))
      else
        SectionCode.Add(Format('      QRYLoad.ParamByName(''%s'').%s:= Obj.%s ;', [GetFieldName(FKeyFields[I]), CurField.FIELD_AS_TYPE, GetFieldName(FKeyFields[I])]))
    end;
  end; // if
  SectionCode.Add('      QRYLoad.Open;'                    );
  SectionCode.Add('      result:= qryLoad.RecordCount > 0;');

  I:= 0;
  for CurField in FFieldList do
  begin
    if CurField.VAR_TYPE = STPicture then
      SectionCode.Add(Format('      TBlobField(QRYLoad.Fields[%d]).SaveToStream(Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else if CurField.ISENUM then
    begin
      if CurField.FIELD_AS_TYPE.ToLower = 'asbyte' then
        SectionCode.Add(Format('     Obj.%s:= %s.FromByte(Get1Byte(QRYLoad.Fields[%d]));', [CurField.GetCurrentFieldName, CurField.ENUMTYPE, I]))
      else
        SectionCode.Add(Format('     Obj.%s:= %s.FromInteger(QRYLoad.Fields[%d].AsInteger);', [CurField.GetCurrentFieldName, CurField.ENUMTYPE, I]))
    end
    else if CurField.VAR_TYPE.ToUpper = 'BYTE' then
      SectionCode.Add(Format('      Obj.%s:= Get1Byte(QRYLoad.Fields[%d]);', [CurField.GetCurrentFieldName, I]))
    else if CurField.VAR_TYPE.ToUpper = 'TBYTES' then
      SectionCode.Add(Format('      Obj.%s:= GetBytes(QRYLoad.Fields[%d]);', [CurField.GetCurrentFieldName, I]))
    else if CurField.VAR_TYPE.ToUpper = 'TSTRINGLIST' then
      SectionCode.Add(Format('      Obj.%s.Text:= QRYLoad.Fields[%d].AsString;', [CurField.GetCurrentFieldName, I]))
    else if CurField.VAR_TYPE.ToUpper = 'TPICTURE' then
      SectionCode.Add(Format('     LoadImageField(QRYLoad, QRYLoad.Fields[%d], Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else
      SectionCode.Add(Format('      Obj.%s:= QRYLoad.Fields[%d].%s ;', [CurField.GetCurrentFieldName, I, CurField.FIELD_AS_TYPE]));
    Inc(I);
  end; // for
end; // procedure

procedure TOrmGenerator.GenerateSection9A(SectionCode: TStringList; const TableName0: string);
var
  CurField: TOrmField;
  I       : Integer;
  S       : string;
  SBFields: TStringBuilder;
  SBKeys  : TStringBuilder;
  SBValues: TStringBuilder;
begin

  SBKeys  := TStringBuilder.Create('MATCHING (');
  SBFields:= TStringBuilder.Create('('         );
  SBValues:= TStringBuilder.Create(VALUES_OPEN);
  try
    if FKeyFields.Count > 0 then
    begin
      for I:= 0 to FKeyFields.Count - 1 do
      begin
        if I > 0 then
          SBKeys.Append(', ');
        SBKeys.Append(FKeyFields[I]);
      end;
      SBKeys.Append(' )');
    end;

    for CurField in FFieldList do
    begin
      if SBFields.Length > 1 then
        SBFields.Append(', ');
      if SBValues.Length > Length(VALUES_OPEN) then
        SBValues.Append(', ');
      SBFields.Append(CurField.FIELD_NAME);
      SBValues.Append(':' + CurField.GetCurrentFieldName);
    end;
    SBFields.Append(')');
    SBValues.Append(')');

    SectionCode.Add(Format('    QRYSave.CommandText.Add(''UPDATE OR INSERT INTO %s'');', [TableName0]));
    if SBFields.Length < MAX_LITERAL_CHUNK then
      SectionCode.Add(Format('    QRYSave.CommandText.Add(''  %s'');', [SBFields.ToString]))
    else
    begin
      S:= ToLiteral(SBFields);
      SectionCode.Add(Format('     var sTmp: string := %s;', [S]));
      SectionCode.Add('     QRYSave.CommandText.Add(sTmp);')
    end;
    if SBValues.Length < MAX_LITERAL_CHUNK then
      SectionCode.Add(Format('    QRYSave.CommandText.Add(''  %s'');', [SBValues.ToString]))
    else
    begin
      S:= ToLiteral(SBValues);
      SectionCode.Add(Format('     var sTmp2: string := %s;', [S]));
      SectionCode.Add('     QRYSave.CommandText.Add(sTmp2);')
    end;
    SectionCode.Add('      QRYSave.Prepare;');
  finally
    SBKeys.Free;
    SBFields.Free;
    SBValues.Free;
  end; // try
end; // procedure

procedure TOrmGenerator.GenerateSection9(SectionCode: TStringList; const TableName0: string);
var
  CurField    : TOrmField;
  I           : Integer;
  HasNonGenKey: Boolean;
begin
  if FKeyFields.Count > 0 then
  begin
    HasNonGenKey:= False;
    for I:= 0 to FKeyFields.Count - 1 do
    begin
      CurField:= LocateField(FKeyFields[I]);
      if FKeyGens[I] <> '' then
      begin
        SectionCode.Add(Format('      if Obj.%s <= 0 then', [CurField.GetCurrentFieldName]));
        SectionCode.Add(Format('        Obj.%s:= NextID;' , [CurField.GetCurrentFieldName]));
      end
      else
        HasNonGenKey:= True;
    end;
    if HasNonGenKey then
    begin
      SectionCode.Add('      var STmp: string := '''';');
      for I:= 0 to FKeyFields.Count - 1 do
      begin
        if FKeyGens[I] = '' then
        begin
          CurField:= LocateField(FKeyFields[I]);
          if (CurField.FIELD_AS_TYPE.ToLower = 'asinteger') or (CurField.FIELD_AS_TYPE.ToLower = 'aslargeint') or (CurField.FIELD_AS_TYPE.ToLower = 'assmallint') then
          begin
            SectionCode.Add(Format('      if Obj.%s <= 0 then', [CurField.GetCurrentFieldName]));
            SectionCode.Add(Format('        if STmp <> '''' then STmp := STmp + '', %s'' else STmp := ''%s'';', [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName]));
          end
          else if (CurField.FIELD_AS_TYPE.ToLower = 'asstring') or (CurField.FIELD_AS_TYPE.ToLower = 'aswidestring') then
          begin
            SectionCode.Add(Format('      if Length(Trim(Obj.%s)) = 0 then', [CurField.GetCurrentFieldName]));
            SectionCode.Add(Format('        if STmp <> '''' then STmp := STmp + '', %s'' else STmp := ''%s'';', [CurField.GetCurrentFieldName, CurField.GetCurrentFieldName]));
          end;
        end;
      end; // for
      SectionCode.Add('      if STmp <> '''' then');
      SectionCode.Add(Format('        raise EUndefinedKeyValue.CreateFmt(''Key field(s) <%%s> are not set. Cannot Save to %s'', [STmp]);', [TableName0]));
    end; // if
  end; // if
  I:= 0;
  for CurField in FFieldList do
  begin
    if CurField.VAR_TYPE = STPicture then
      SectionCode.Add(Format('      TBlobField(QRYSave.Params[%d]).LoadFromStream(Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else if CurField.ISENUM and (FSaveForm = osfLegacy) then
      SectionCode.Add(Format('      QRYSave.Params[%d].AsByte:= Obj.%s.ToByte ;', [I, CurField.GetCurrentFieldName]))
    else if CurField.ISENUM then
      SectionCode.Add(Format('      Set1Byte(QRYSave.Params[%d], Obj.%s.ToByte);', [I, CurField.GetCurrentFieldName]))
    else if (CurField.VAR_TYPE.ToUpper = 'TSQLTIMESTAMP') and (FSaveForm = osfLegacy) then
      SectionCode.Add(Format('      QRYSave.Params[%d].AsSQLTimeStamp:= Obj.%s;', [I, CurField.GetCurrentFieldName]))
    else if CurField.VAR_TYPE.ToUpper = 'TSQLTIMESTAMP' then
    begin
      SectionCode.Add(Format('      if Obj.%s.Year = 0 then QRYSave.Params[%d].Clear', [CurField.GetCurrentFieldName, I]));
      SectionCode.Add(Format('      else QRYSave.Params[%d].AsSQLTimeStamp:= Obj.%s;', [I, CurField.GetCurrentFieldName]));
    end
    else if CurField.VAR_TYPE.ToUpper = 'BYTE' then
      SectionCode.Add(Format('      Set1Byte(QRYSave.Params[%d], Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else if CurField.VAR_TYPE.ToUpper = 'TBYTES' then
      SectionCode.Add(Format('      SetBytes(QRYSave.Params[%d], Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else if CurField.VAR_TYPE.ToUpper = 'TSTRINGLIST' then
      SectionCode.Add(Format('      QRYSave.Params[%d].%s:= Obj.%s.Text;',
        [I, if FSaveForm = osfLegacy then 'AsString' else 'AsWideMemo', CurField.GetCurrentFieldName]))
    else if CurField.VAR_TYPE.ToUpper = 'TPICTURE' then
      SectionCode.Add(Format('     SaveImageField(qrySave, QRYSave.Params[%d], Obj.%s);', [I, CurField.GetCurrentFieldName]))
    else if CurField.VAR_TYPE.ToUpper = 'TBCD' then
      SectionCode.Add(Format('      QRYSave.Params[%d].AsFMTBCD:= Obj.%s ;', [I, CurField.GetCurrentFieldName]))
    else if FSaveForm = osfLegacy then
      { B33 (1.52): the FIELD_AS_TYPE accessor (TableTools before 2026-05-19), the form every
        ORM3 _SERVER unit carries, so update-orm leaves them unchanged }
      SectionCode.Add(Format('      QRYSave.Params[%d].%s:= Obj.%s ;', [I, CurField.FIELD_AS_TYPE, CurField.GetCurrentFieldName]))
    else
      SectionCode.Add(Format('      QRYSave.Params[%d].Value:= Obj.%s ;', [I, CurField.GetCurrentFieldName]));
    Inc(I);
  end; // for
end; // procedure

{ TableTools UpdateFileRegions: the per-id dispatch. Ids 12 and 13 fall through to "nothing"
  on purpose: TableTools' GenerateSection12 / 13 only build a string they never add (the lines
  that used it are commented out there), so both regions come out empty. }
procedure TOrmGenerator.GenerateRegion(const pRegionId: string; pIsInterface: Boolean; pCode: TStringList);
var
  TableId: string;
begin
  TableId:= FLoadedTable.Replace('$', '_');
  if pRegionId = '2' then
  begin
    if pIsInterface then
      GenerateSection2I(pCode)
    else
      GenerateSection2P(pCode);
  end
  else if pRegionId = '1' then
    GenerateSection1(pCode)
  else if pRegionId = '1A' then
    GenerateSection1A(pCode)
  else if pRegionId = '3' then
    GenerateSection3(pCode)
  else if pRegionId = '4' then
    GenerateSection4(pCode)
  else if pRegionId = '5' then
    GenerateSection5(pCode)
  else if pRegionId = '6' then
    GenerateSection6(pCode)
  else if pRegionId = '7' then
    GenerateSection7(pCode, TableId)
  else if pRegionId = '8' then
    GenerateSection8(pCode, FLoadedTable)
  else if pRegionId = '9' then
    GenerateSection9(pCode, FLoadedTable)
  else if pRegionId = '8A' then
    GenerateSection8A(pCode, FLoadedTable)
  else if pRegionId = '9A' then
    GenerateSection9A(pCode, FLoadedTable)
  else if pRegionId = '10' then
    GenerateSection10(pCode)
  else if pRegionId = '11' then
    GenerateSection11(pCode)
  else if pRegionId = '14' then
    GenerateSection14(pCode)
  else if pRegionId = '15' then
    GenerateSection15(pCode)
  else if pRegionId = 'CL-KEY' then
    GenerateCLSectionKEY(pCode, FLoadedTable)
  else if pRegionId = 'CL-LOAD' then
    GenerateCLSectionLOAD(pCode, FLoadedTable)
  else if pRegionId = 'CL-SAVE' then
    GenerateCLSectionSAVE(pCode, FLoadedTable)
  else if pRegionId = 'CL-DEL' then
    GenerateCLSectionDEL(pCode, FLoadedTable)
  else if pRegionId = 'CL-NEXTID' then
    GenerateCLSectionNEXTID(pCode, FLoadedTable, FHasGenerator, FGenName);
end;

type
  { One physical line of a file: its text and its own line end ('' on a last line without one). }
  TRawLine = record
    Text: string;
    Eol: string;
  end;

function SplitRawLines(const pText: string): TArray<TRawLine>;
var
  L: TList<TRawLine>;
  I, Start: Integer;
  R: TRawLine;
begin
  L:= TList<TRawLine>.Create;
  try
    I:= 1;
    Start:= 1;
    while I <= Length(pText) do
    begin
      if CharInSet(pText[I], [#10, #13]) then
      begin
        R.Text:= Copy(pText, Start, I - Start);
        if (pText[I] = #13) and (I < Length(pText)) and (pText[I + 1] = #10) then
        begin
          R.Eol:= #13#10;
          Inc(I);
        end
        else
          R.Eol:= pText[I];
        L.Add(R);
        Start:= I + 1;
      end;
      Inc(I);
    end;
    if Start <= Length(pText) then
    begin
      R.Text:= Copy(pText, Start, MaxInt);
      R.Eol:= '';
      L.Add(R);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function TOrmGenerator.UpdateRegions(const pText, pTableName: string; pIsInterface: Boolean;
  out pRegionCount: Integer): string;
var
  Lines: TArray<TRawLine>;
  SB: TStringBuilder;
  Code: TStringList;
  I, J: Integer;
  RegionId: string;
begin
  if FLoadedTable <> pTableName then
    LoadTable(pTableName);
  pRegionCount:= 0;
  Lines:= SplitRawLines(pText);
  SB:= TStringBuilder.Create;
  Code:= TStringList.Create;
  try
    I:= 0;
    while I < Length(Lines) do
    begin
      SB.Append(Lines[I].Text).Append(Lines[I].Eol);
      if IsOrmRegionStart(Lines[I].Text, RegionId) then
      begin
        Inc(pRegionCount);
        { a start line on the last line without a line end: TableTools would add one }
        if Lines[I].Eol = '' then
          SB.Append(#13#10);
        Code.Clear;
        GenerateRegion(RegionId, pIsInterface, Code);
        SB.Append(OrmJoinLines(Code));
        J:= I + 1;
        while (J < Length(Lines)) and not IsOrmRegionEnd(Lines[J].Text) do
          Inc(J);
        if J < Length(Lines) then
        begin
          SB.Append(Lines[J].Text).Append(Lines[J].Eol);
          I:= J;
        end;
      end;
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    Code.Free;
    SB.Free;
  end;
end;

{ plan / apply }

function ChangeOf(const pFileName, pOldText, pNewText: string; pExists: Boolean): TOrmFileChange;
begin
  Result.FileName:= pFileName;
  Result.OldText:= pOldText;
  Result.NewText:= pNewText;
  if not pExists then
    Result.Kind:= ockNew
  else if pOldText = pNewText then  // dl:ok ifthen-to-if-expression@1943 -- REVIEWED 2026-11-17 v152 TTGEN: three-way result, an if-expression is not clearer here
    Result.Kind:= ockUnchanged
  else
    Result.Kind:= ockChanged;
end;

function ReadUnitText(const pFileName: string): string;
begin
  { TableTools TStringList.LoadFromFile: no BOM = the ANSI code page }
  Result:= TFile.ReadAllText(pFileName, TEncoding.ANSI);
end;

function CheckedTables(pGen: TOrmGenerator; const pTables: TArray<string>): TArray<string>;
var
  All: TArray<string>;
  T, A: string;
  Found: Boolean;
begin
  All:= pGen.TableNames;
  if Length(pTables) = 0 then
    Exit(All);
  for T in pTables do
  begin
    Found:= False;
    for A in All do
      if SameText(A, T) then
        Found:= True;
    if not Found then
      raise EOrmGenError.CreateFmt('Table <%s> is not in the repository', [T]);
  end;
  Result:= pTables;
end;

function PlanUpdateOrm(pRepo: TFDConnection; const pCodeDir, pServerDir, pClientDir: string;
  const pTables: TArray<string>; pSkipped: TStrings; pSaveForm: TOrmSaveForm): TArray<TOrmFileChange>;
var
  Gen: TOrmGenerator;
  L: TList<TOrmFileChange>;
  T, Ident: string;

  procedure One(const pFile: string; pIsInterface: Boolean);
  var
    OldL: string;
    N: Integer;
  begin
    if not TFile.Exists(pFile) then
    begin
      pSkipped.Add(pFile + ': file does not exist');
      Exit;
    end;
    OldL:= ReadUnitText(pFile);
    L.Add(ChangeOf(pFile, OldL, Gen.UpdateRegions(OldL, T, pIsInterface, N), True));
  end;

begin
  L:= TList<TOrmFileChange>.Create;
  Gen:= TOrmGenerator.Create(pRepo);
  Gen.SaveForm:= pSaveForm;
  try
    for T in CheckedTables(Gen, pTables) do
    begin
      Gen.LoadTable(T);
      Ident:= T.Replace('$', '_');
      { TableTools would empty every region of such a table; update-orm leaves it alone }
      if Gen.FieldCount = 0 then
      begin
        pSkipped.Add(T + ': no field row with FIELD_KIND = 1; regions left unchanged');
        Continue;
      end;
      One(TPath.Combine(pCodeDir, ORM_INTF_PREFIX + Ident + ORM_FILE_EXT), True);
      One(TPath.Combine(pCodeDir, ORM_PAS_PREFIX + Ident + ORM_FILE_EXT), False);
      if pServerDir <> '' then
        One(TPath.Combine(pServerDir, ORM_PAS_PREFIX + Ident + '_SERVER' + ORM_FILE_EXT), False);
      if pClientDir <> '' then
        One(TPath.Combine(pClientDir, ORM_PAS_PREFIX + Ident + '_CLIENT' + ORM_FILE_EXT), False);
    end;
    Result:= L.ToArray;
  finally
    Gen.Free;
    L.Free;
  end;
end;

function OrmPlanFile(const pFileName: string; pLines: TStrings): TOrmFileChange;
var
  Exists: Boolean;
  OldL: string;
begin
  Exists:= TFile.Exists(pFileName);
  OldL:= if Exists then ReadUnitText(pFileName) else '';
  Result:= ChangeOf(pFileName, OldL, OrmJoinLines(pLines), Exists);
end;

function PlanGenOrm(pRepo: TFDConnection; const pCodeDir: string; const pTables: TArray<string>;
  const pGuidProvider: TFunc<TGUID>): TArray<TOrmFileChange>;
var
  Gen: TOrmGenerator;
  L: TList<TOrmFileChange>;
  Intf, Pas: TStringList;
  T, Ident: string;
begin
  L:= TList<TOrmFileChange>.Create;
  Gen:= TOrmGenerator.Create(pRepo);
  Intf:= TStringList.Create;
  Pas:= TStringList.Create;
  try
    Gen.GuidProvider:= pGuidProvider;
    for T in CheckedTables(Gen, pTables) do
    begin
      Intf.Clear;
      Pas.Clear;
      Gen.GenerateNewTableObject(T, Intf, Pas);
      Ident:= T.Replace('$', '_');
      L.Add(OrmPlanFile(TPath.Combine(pCodeDir, ORM_INTF_PREFIX + Ident + ORM_FILE_EXT), Intf));
      L.Add(OrmPlanFile(TPath.Combine(pCodeDir, ORM_PAS_PREFIX + Ident + ORM_FILE_EXT), Pas));
    end;
    Result:= L.ToArray;
  finally
    Pas.Free;
    Intf.Free;
    Gen.Free;
    L.Free;
  end;
end;

procedure BackupFile(const pFileName: string);
var
  N: Integer;
begin
  N:= 1;
  while TFile.Exists(pFileName + Format('.BCK%d', [N])) do
    Inc(N);
  TFile.Copy(pFileName, pFileName + Format('.BCK%d', [N]));
end;

function ApplyOrmChanges(const pChanges: TArray<TOrmFileChange>; pBackup: Boolean): Integer;
var
  C: TOrmFileChange;
begin
  Result:= 0;
  for C in pChanges do
  begin
    if C.Kind = ockUnchanged then
      Continue;
    if pBackup and TFile.Exists(C.FileName) then
      BackupFile(C.FileName);
    TDirectory.CreateDirectory(ExtractFilePath(C.FileName));
    TFile.WriteAllBytes(C.FileName, TEncoding.ASCII.GetBytes(C.NewText));
    Inc(Result);
  end;
end;

function OrmChangeDiff(const pChange: TOrmFileChange): string;
var
  OldL, NewL: TArray<string>;
  SB: TStringBuilder;
  I, J, OS, NS: Integer;
  Hunks: Integer;

  procedure EmitHunk(pOS, pOE, pNS, pNE: Integer);
  begin
    { trim the lines both sides share at the end of the hunk }
    while (pOE > pOS) and (pNE > pNS) and (OldL[pOE - 1] = NewL[pNE - 1]) do
    begin
      Dec(pOE);
      Dec(pNE);
    end;
    if (pOE = pOS) and (pNE = pNS) then
      Exit;
    Inc(Hunks);
    SB.Append(Format('@@ line %d @@', [pOS + 1])).Append(#13#10);
    while pOS < pOE do
    begin
      SB.Append('-').Append(OldL[pOS]).Append(#13#10);
      Inc(pOS);
    end;
    while pNS < pNE do
    begin
      SB.Append('+').Append(NewL[pNS]).Append(#13#10);
      Inc(pNS);
    end;
  end;

begin
  if pChange.Kind = ockUnchanged then
    Exit('');
  OldL:= OrmSplitLines(pChange.OldText);
  NewL:= OrmSplitLines(pChange.NewText);
  Hunks:= 0;
  SB:= TStringBuilder.Create;
  try
    SB.Append('--- ').Append(pChange.FileName).Append(#13#10);
    SB.Append('+++ ').Append(pChange.FileName).Append(#13#10);
    if pChange.Kind = ockNew then
    begin
      SB.Append(Format('@@ new file, %d lines @@', [Length(NewL)])).Append(#13#10);
      for J:= 0 to High(NewL) do
        SB.Append('+').Append(NewL[J]).Append(#13#10);
      Exit(SB.ToString);
    end;
    { walk both texts; a hunk runs from the first differing line to the next region end
      on each side (update-orm changes only region bodies) }
    I:= 0;
    J:= 0;
    while (I < Length(OldL)) and (J < Length(NewL)) do
    begin
      if OldL[I] = NewL[J] then
      begin
        Inc(I);
        Inc(J);
        Continue;
      end;
      OS:= I;
      NS:= J;
      while (I < Length(OldL)) and not IsOrmRegionEnd(OldL[I]) do
        Inc(I);
      while (J < Length(NewL)) and not IsOrmRegionEnd(NewL[J]) do
        Inc(J);
      { two different lines that are both region ends: take them, so the walk always moves }
      if (I = OS) and (J = NS) then
      begin
        Inc(I);
        Inc(J);
      end;
      EmitHunk(OS, I, NS, J);
    end;
    EmitHunk(I, Length(OldL), J, Length(NewL));
    if Hunks = 0 then
      SB.Append('@@ line ends only @@').Append(#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;
end.
