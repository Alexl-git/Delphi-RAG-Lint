unit Blueprint4.ViewModel;

{ ==================================================================
  NEW ViewModel for Blueprint4 ? rewritten 2026-05-13 (Phase 1C).
  Replaces the BDE-bound Blueprint4.Model.pas (now .OLD).

  Architecture (see memory reference_micronite_data_architecture.md):
    - Client owns TFDMemTables only. NO FireDAC connection on client.
    - Loads via cmdTableLoad over per-thread pipe (AppConnection).
    - Saves via cmdDelta on AfterPost/AfterDelete.
    - Schema built via TFieldsInfoFactory from FIB$FIELDS_INFO.
    - Folder scoping: WHERE=FLDRID=N (direct) or via subquery for
      child tables that lack a direct FLDRID column.

  Templates this is modeled on:
    - uJobList.ViewModel.pas (pipe-load + async + special commands)
    - uOperName.ViewModel.pas (cmdDelta save pattern)

  Phase 1 scope:
    - Skeleton : 13 folder-scoped MemTables + schema-building
    - 113 named field accessors for Blueprint4.Imports.pas compat
    - ALL business-logic methods are STUBS (TODO Phase 2+)
    - Lookup VMs (Customers/Machines/OperName/AttrNames/VarNames)
      not yet composed ? pdsr* getters return nil for those
  ================================================================== }

interface

uses
  System.SysUtils
  , System.Classes
  , System.UITypes
  , System.Variants
  , System.Generics.Collections
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Stan.Intf
  , FireDAC.Stan.StorageBin
  , Vcl.Forms
  , Winapi.Windows
  , spring
  , uPipeClientConnection
  , uAppGlobals
  , Pipes.Protocol
  , uFieldsInfoFactory
  , Blueprint4.Interfaces
  , BASICS
  , BASICSF
  , MSCTYPES
  , iSetupDefaults // SetupDefaultsRec / IGlobalSetupDefaults (ImportOGP)
  , FlexDateTime // ReadDate/ReadTime -- OGP Date/Time column validation
  , iMSCLIST
  , uMSCLIST // TmcMSCLIST concrete class for FFTR working buffer
  ;

type
  TBlueprint_ViewModel = class(TInterfacedObject, IBlueprint_ViewModel)
    strict private
      FConn           : TPipeClientConnection;
      FFldrID         : Integer              ;
      FSchemaBuilt    : Boolean              ;
      FSuppressEvents : Boolean              ;
      // CMM-import headless seam: when FImportHeadless is set (by --autotest)
      // ImportMsg routes every importer dialog to FImportReport and returns
      // IDYES for the dry-run gate, so OGP/ZEISS/LK/Nikon/Sheffield/JenVICI
      // run without blocking on Application.MessageBox. UI mode unchanged.
      FImportHeadless : Boolean    ;
      FImportReport   : TStringList;
      // 2026-05-26 -- last cmdDelta FOLDERS rejection (FK_FOLDERS14 etc.).
      // Cleared at SendDeltaFolder enter; set when the server returns
      // anything other than rspOK. The form polls it after Post.
      FLastPersistError: string;
      // 2026-05-14 Phase 2 -- FTR working buffer (form binds 84 UI controls to FFTR.X)
      FFTR : ImcMSCLIST;

      // Folder-scoped MemTables (owned)
      FMTFtrs      : TFDMemTable; // MSCLIST
      FMTOperation : TFDMemTable; // OPERAT
      FMTOSublot   : TFDMemTable; // OSUBLOT  (child of OPERAT)
      FMTGInsp     : TFDMemTable; // GINSP    (child of OPERAT)
      FMTIInsp     : TFDMemTable; // IINSP    (child of GINSP)
      FMTInspRslt  : TFDMemTable; // INSPRSLT
      FMTIPChart   : TFDMemTable; // IPCHART  (child of INSPRSLT)
      FMTCPSet     : TFDMemTable; // CPSET    (child of MSCLIST)
      FMTMUSet     : TFDMemTable; // MUSET    (child of MSCLIST)
      FMTPPSet     : TFDMemTable; // PPSET    (child of MSCLIST)
      FMTGonOff    : TFDMemTable; // GONOFF
      FMTPlanList  : TFDMemTable; // PLANLIST
      FMTReadings  : TFDMemTable; // READINGS (child of INSPRSLT)
      FMTFolder    : TFDMemTable; // FOLDERS  (1-row: this folder's Job Header)
      FMTMachines  : TFDMemTable; // MACHINES (full plant, UNFILTERED -- BP4 is
      // an admin form; the station-filtered
      // LookupCache 'MACHINES' entry is for
      // operator-side pickers, not job setup)

      // DataSources for grid binding (owned for MTFtrs & MTOperation; rest
      // come from composed lookup VMs in Phase 2+)
      FDsrFtrs      : TDataSource;
      FDsrOperation : TDataSource;
      FDsrFolder    : TDataSource; // Job Header binding (Blueprint4 edtF*/edt_*)
      FDsrMachines  : TDataSource; // viewMachines (edtMachine lookup combo)
      FDsrFtrNames  : TDataSource; // viewFTRName lookup (VARNAMES via LookupCache)
      FDsrOperNames : TDataSource; // viewOperationName lookup (OPERNAME via LookupCache)

      // State (mostly set/get via interface)
      FLoadEnabled        : Boolean           ;
      FSaveEnabled        : Boolean           ;
      FRequireRefresh     : Boolean           ;
      FSkipOperationScroll: Boolean           ;
      FFTRCreated         : Boolean           ;
      FLotSize            : Integer           ;
      FEditField          : REditField        ;
      FActiveField        : REditField        ;
      FCNotation          : TSpecNotation     ;
      FCSpec              : TSpecType         ;
      FieldOrder          : Vector<string>    ;
      EditFields          : Vector<REditField>;

      // Cached MSCLIST field refs ? 109 used by Blueprint4.Imports.pas.
      // All typed as TField in Phase 1; upgrade to specific subclasses
      // (TFloatField/TIntegerField/etc.) via TFieldsInfoFactory.BindAs<T>
      // in a later phase. See feedback_no_fieldbyname.md.
      FfFtrs_AbsoluteValue   : TField;
      FfFtrs_Addto           : TField;
      FfFtrs_AttrCode        : TField;
      FfFtrs_AttrName        : TField;
      FfFtrs_AttrType        : TField;
      FfFtrs_CbxFinalI       : TField;
      FfFtrs_CbxPCAP         : TField;
      FfFtrs_CbxPCAPPROP     : TField;
      FfFtrs_CbxRunSQC       : TField;
      FfFtrs_CbxSetR         : TField;
      FfFtrs_CbxStab         : TField;
      FfFtrs_CbxTFirstA      : TField;
      FfFtrs_Convert         : TField;
      FfFtrs_DataChannel     : TField;
      FfFtrs_Decimals        : TField;
      FfFtrs_DimAbbr         : TField;
      FfFtrs_DimName         : TField;
      FfFtrs_DimUnits        : TField;
      FfFtrs_DoIPCF          : TField;
      FfFtrs_DoRSCF          : TField;
      FfFtrs_DoSbCF          : TField;
      FfFtrs_EdtByPpk        : TField;
      FfFtrs_EdtByZdi        : TField;
      FfFtrs_EdtIPCPRd2      : TField;
      FfFtrs_EdtIPCPSampRd2  : TField;
      FfFtrs_EdtIPCPSamps    : TField;
      FfFtrs_EdtIPCPkSamprd2 : TField;
      FfFtrs_EdtIPCPkSamps   : TField;
      FfFtrs_EdtIPCPkrd2     : TField;
      FfFtrs_EdtIPCPks       : TField;
      FfFtrs_EdtIPCPs        : TField;
      FfFtrs_EdtRSQCLCL      : TField;
      FfFtrs_EdtRSQCUCL      : TField;
      FfFtrs_EdtSRNom        : TField;
      FfFtrs_FinalPlanID     : TField;
      FfFtrs_FinalPlanType   : TField;
      FfFtrs_FldrID          : TField;
      FfFtrs_FtrMClass       : TField;
      FfFtrs_FtrQClass       : TField;
      FfFtrs_FtrSuffix       : TField;
      FfFtrs_FtrType         : TField;
      FfFtrs_GagePortNmbr    : TField;
      FfFtrs_ID              : TField;
      FfFtrs_IPFinalPlanID   : TField;
      FfFtrs_IPFinalPlanType : TField;
      FfFtrs_IPSet           : TField;
      FfFtrs_Indicator       : TField;
      FfFtrs_InspAsVar       : TField;
      FfFtrs_LSL             : TField;
      FfFtrs_LastOnOff       : TField;
      FfFtrs_LowerTol        : TField;
      FfFtrs_MainInsp        : TField;
      FfFtrs_MasterID        : TField;
      FfFtrs_MathA           : TField;
      FfFtrs_MathB           : TField;
      FfFtrs_MathC           : TField;
      FfFtrs_MathD           : TField;
      FfFtrs_MathLine        : TField;
      FfFtrs_MultBy          : TField;
      FfFtrs_NextEvent       : TField;
      FfFtrs_Nominal         : TField;
      FfFtrs_Notation        : TField;
      FfFtrs_Notes           : TField;
      FfFtrs_Num             : TField;
      FfFtrs_OperID          : TField;
      FfFtrs_OperOrd         : TField;
      FfFtrs_OriginalLSL     : TField;
      FfFtrs_OriginalUSL     : TField;
      FfFtrs_ProcON          : TField;
      FfFtrs_RSQCPrectrlOnly : TField;
      FfFtrs_RbtIPFreq       : TField;
      FfFtrs_RbtIPMode       : TField;
      FfFtrs_RbtIPSPCPriority: TField;
      FfFtrs_RbtRSQCCLType   : TField;
      FfFtrs_RbtRSQCPpk      : TField;
      FfFtrs_RbtRSQCZdi      : TField;
      FfFtrs_RbtSRSTMode     : TField;
      FfFtrs_RecFinalPlanID  : TField;
      FfFtrs_RecFinalPlanType: TField;
      FfFtrs_RedFlag         : TField;
      FfFtrs_SSortIP         : TField;
      FfFtrs_SSortME         : TField;
      FfFtrs_SpecType        : TField;
      FfFtrs_StatusOFF       : TField;
      FfFtrs_StatusON        : TField;
      FfFtrs_SubFinalPlanID  : TField;
      FfFtrs_SubFinalPlanType: TField;
      FfFtrs_TabIMode        : TField;
      FfFtrs_TimerON         : TField;
      FfFtrs_USL             : TField;
      FfFtrs_UpperTol        : TField;
      FfFtrs_UseMathLine     : TField;
      FfFtrs_YellowFlag      : TField;
      FfFtrs_ZeroAt          : TField;
      FfFtrs_ZeroMode        : TField;
      // Lowercase-starting Imports.pas refs (CamelCase in Delphi; uppercased in SQL):
      FfFtrs_cbxSIP          : TField;
      FfFtrs_edtFirstPUpper  : TField;
      FfFtrs_edtFirstPlower  : TField;
      FfFtrs_edtIPFPcs       : TField;
      FfFtrs_edtIPFreq       : TField;
      FfFtrs_edtIPRLLim      : TField;
      FfFtrs_edtIPRULim      : TField;
      FfFtrs_edtIPSS         : TField;
      FfFtrs_edtIPYLLim      : TField;
      FfFtrs_edtIPYULim      : TField;
      FfFtrs_edtLCL          : TField;
      FfFtrs_edtMEPrecision  : TField;
      FfFtrs_edtMESSize      : TField;
      FfFtrs_edtUCL          : TField;
      FfFtrs_lsbFinalII      : TField;
      FfFtrs_lsbIPFinalII    : TField;
      FfFtrs_lsbRecFinalII   : TField;
      FfFtrs_lsbSubFinalII   : TField;
      FfFtrs_rbtIPAccLim     : TField;
      FfFtrs_rbtMError       : TField;
      FfFtrs_rbtPrecontrType : TField;
      FfFtrs_rbtUnregul      : TField;

      // Calculated fields (virtual, not in DB schema) - populated by OnCalcFields
      FfFtrs_FtrName      : TField;
      FfFtrs_ClassName    : TField;
      FfFtrs_USLLSLName   : TField;
      FfFtrs_DimAbbrSmall : TField;
      FfFtrs_Tolerance    : TField;
      FfFtrs_ToolName     : TField;
      FfFtrs_InspIsSet    : TField;
      FfFtrs_Duein        : TField;
      FfFtrs_StatusONStr  : TField;
      FfFtrs_StatusOFFstr : TField;
      FfFtrs_InspAsVarStr : TField;
      FfFtrs_Attribute    : TField;

      // Cached OPERAT field refs --- 4 used by Blueprint4.Imports.pas
      FfOperation_CMMMultiplier: TField;
      FfOperation_CMMType      : TField;
      FfOperation_FileName     : TField;
      FfOperation_ID           : TField;

      procedure BuildSchema;
      procedure CacheFieldRefs;
      procedure FtrsOnCalcFields(DataSet: TDataSet); // 2026-05-20 -- populates 12 calc fields
      procedure FtrsOnFilterRecord(DataSet: TDataSet; var Accept: Boolean);
      function LoadOneTable(AMT: TFDMemTable; const ATableName, AWhere: string): Boolean;
      // 2026-05-14 Phase 2 -- MSCLIST persistence + GNG helpers
      procedure DoAfterPostFtrs  (DataSet: TDataSet);
      procedure DoAfterDeleteFtrs(DataSet: TDataSet);
      function SendDeltaFtrs(const AContext: string): Boolean;
      // 2026-05-19 -- FOLDERS (Job Header) write-back, same cmdDelta path.
      procedure DoAfterPostFolder(DataSet: TDataSet);
      function SendDeltaFolder(const AContext: string): Boolean;
      procedure ToGNG1Char;
      procedure FromGNG1Char;
      // 2026-05-14 Phase 2 -- OPERAT persistence + Operation CRUD
      procedure DoAfterPostOperation  (DataSet: TDataSet);
      procedure DoAfterDeleteOperation(DataSet: TDataSet);
      function SendDeltaOperation(const AContext: string): Boolean                ;
      function ReserveNextID(const AGenName: string; out ANewID: Integer): Boolean;
      // Shared by the CMM importers (ImportOGP/ImportZEISS/...): sniff a
      // file's text encoding -- UTF-8 BOM, else valid (BOM-less) UTF-8,
      // else ANSI (ASuspect=True when 8-bit non-UTF-8 -> verify glyphs).
      function DetectFileEncoding(const AFile: string; out ASuspect: Boolean): TEncoding;
      // CMM-import message router = the headless seam (see FImportHeadless).
      // Used by every Import* in place of Application.MessageBox.
      function ImportMsg(const AText, ACaption: string; AFlags: UINT): Integer;
      // 2026-05-17 -- field jump-order subsystem (ported from
      // Blueprint4.Model.pas.OLD). FieldByName resolves an EditFields entry
      // by control name; FieldOrderdByName finds its index in the dynamic
      // FieldOrder list (rebuilt by RefreshFieldOrder from CNotation/CSpec).
      function FieldByName      (const AName: string): REditField;
      function FieldOrderdByName(const AName: string): Integer;
      // 2026-05-17 -- D_BYTETAG columns (FTRTYPE/SPECTYPE/NOTATION/FTRCLASS/
      // CBX*/RBT* ...) are CHAR(1) OCTETS = a single ordinal byte, but
      // TableTools emits FIELD_AS_TYPE='AsWideString' so the MemTable field is
      // WideString(1). The byte value is the WideChar code. Reading/writing
      // them as .AsInteger raised "Invalid variant type or size". These wrap
      // the encode/decode (and tolerate a TBytesField if the octets override
      // is ever applied) so call sites stay readable.
      function TagOf(F: TField): Integer;
      procedure SetTag(F: TField; AOrd: Integer);
      // 2026-05-17 -- shared engine for SmartClassifyInches/MM (ported from
      // Blueprint4.Model.pas.OLD; the two differ only in the tolerance bands).
      // D_BYTETAG-correct: SpecType/FtrMClass via TagOf/SetTag (TBytesField).
      procedure DoSmartClassify(const ATolGramLim, AGramLim1, AGramLim2, AGramLim3: array of double);
      procedure AssignActiveFieldValue(const AStr: string; const AINT: Integer; const AFloat: double; const ABool: Boolean);
      procedure ExtractActiveFieldValue(out AStr: string; out AINT: Integer; out AFloat: double; out ABool: Boolean);
      // Send cmdDeleteCharacteristic to the server and return True on rspOK.
      // On failure sets FLastPersistError and returns False.
      function ServerDeleteCharacteristic(AID: Integer): Boolean;
      // Send cmdDeleteOperation to the server and return True on rspOK (the
      // server guards on has-data + cascades the OPERAT delete + plan cleanup).
      function ServerDeleteOperation(AID: Integer): Boolean;
    public
      constructor Create(AConn: TPipeClientConnection; AFldrID: Integer); reintroduce;
      destructor Destroy; override;

      // Bulk load ? call from form's FormShow after construction.
      // Loads all 13 folder-scoped MemTables for FFldrID via cmdTableLoad.
      procedure LoadAllForFolder;
      function DiagByteTagFields: string;

      {$REGION 'IBlueprint_ViewModel ? read'}
      function CharacteristicHasData(const ID     : Integer): Boolean;
      function InspectionHasData    (const IInspID: Integer): TInspHasDataInfo;
      function FTR                   : ImcMSCLIST;
      function GetCNotation          : TSpecNotation;
      function GetCSpec              : TSpecType;
      function GetEditField          : REditField;
      function GetFLDRID             : Integer;
      function GetFTRCreated         : Boolean;
      function GetFtrsRecordCount    : Integer;
      function GetLotSize            : Integer;
      function GetOperationNames     : TOperationNameRec;
      function GetpdsrAttrNames      : TDataSource;
      function GetpdsrCustomers      : TDataSource;
      function GetpdsrFolder         : TDataSource;
      function GetpdsrFtrNames       : TDataSource;
      function GetpdsrFtrs           : TDataSource;
      function GetpdsrMachines       : TDataSource;
      function GetpdsrOperation      : TDataSource;
      function GetpdsrOperNames      : TDataSource;
      function GetRequireRefresh     : Boolean;
      function GetSkipOperationScroll: Boolean;
      function GetImportHeadless     : Boolean;
      function GetLastImportReport : string;
      function GetLastPersistError : string;
      procedure ClearLastPersistError;
      procedure SetImportHeadless(const V: Boolean);
      function LoadEnabled : Boolean                       ;
      function NextField: string                           ;
      function OperationHasData(const ID: Integer): Boolean;
      function PriorField: string                          ;
      function SaveEnabled: Boolean                        ;
      function FlushFolder: Boolean                        ;
      {$ENDREGION}

      {$REGION 'IBlueprint_ViewModel ? write/mutate (STUBBED in Phase 1)'}
      procedure AddCharacteristic; overload;
      procedure AddCharacteristic(const AFtrType: Integer); overload;
      procedure AddOperation;
      procedure AppendCharGroups(const FldrID: TSystID; const pID: TSystID);
      procedure ApplyActiveField(AID: TArray<Integer>);
      procedure ConnectDsrFtrs;
      procedure DeleteCharacteristic(AID: TArray<Integer>);
      procedure DeleteOperation(const AID: Integer);
      procedure DisconnectDsrFtrs;
      procedure EnableLoad;
      procedure EnableSave;
      procedure EnterField(const AFieldName: string);
      procedure FromGNGSelected(AID: TArray<Integer>);
      procedure FromGNGSuffix;
      procedure ImportCAD;
      procedure ImportCopyOperation(const pID: Integer; const pClass: TCharMClass);
      procedure ImportJenVICI(const ADevType: Integer; const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure ImportLK   (const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure ImportNikon(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure ImportOGP  (const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure ImportPDF;
      procedure OpenControlPlan2;
      procedure ImportSheffield(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure ImportZEISS    (const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
      procedure LoadFtrRecord(const ID: Integer);
      procedure RefreshFieldOrder;
      procedure SaveFtrRecord         (const ID        : Integer      );
      procedure SetCNotation          (const Value     : TSpecNotation);
      procedure SetCSpec              (const Value     : TSpecType    );
      procedure SetEditField          (const AEditField: REditField   );
      procedure SetFLDRID             (const Value     : Integer      );
      procedure SetFTRCreated         (const Value     : Boolean      );
      procedure SetLotSize            (const Value     : Integer      );
      procedure SetRequireRefresh     (const Value     : Boolean      );
      procedure SetSkipOperationScroll(const Value     : Boolean      );
      procedure SmartClassifyInches;
      procedure SmartClassifyMM;
      procedure ToGNGSelected(AID: TArray<Integer>);
      procedure ToGNGSuffix;
      procedure VerifyAll(const APP: TPrePlan);
      {$ENDREGION}

      // Direct MemTable access for unit-internal code (NOT for forms).
      // Blueprint4.Imports.pas uses these via AMODEL.tblFtrs / .tblOperation.
      property tblFtrs     : TFDMemTable read FMTFtrs;
      property tblOperation: TFDMemTable read FMTOperation;

      {$REGION 'Named field accessors for Blueprint4.Imports.pas backwards compat'}
      // MSCLIST (87 PascalCase + 22 lowercase = 109)
      property tblFtrsAbsoluteValue    : TField read FfFtrs_AbsoluteValue;
      property tblFtrsAddto            : TField read FfFtrs_Addto;
      property tblFtrsCbxFinalI        : TField read FfFtrs_CbxFinalI;
      property tblFtrsCbxPCAP          : TField read FfFtrs_CbxPCAP;
      property tblFtrsCbxPCAPPROP      : TField read FfFtrs_CbxPCAPPROP;
      property tblFtrsCbxRunSQC        : TField read FfFtrs_CbxRunSQC;
      property tblFtrsCbxSetR          : TField read FfFtrs_CbxSetR;
      property tblFtrsCbxStab          : TField read FfFtrs_CbxStab;
      property tblFtrsCbxTFirstA       : TField read FfFtrs_CbxTFirstA;
      property tblFtrsConvert          : TField read FfFtrs_Convert;
      property tblFtrsDataChannel      : TField read FfFtrs_DataChannel;
      property tblFtrsDecimals         : TField read FfFtrs_Decimals;
      property tblFtrsDimAbbr          : TField read FfFtrs_DimAbbr;
      property tblFtrsDimName          : TField read FfFtrs_DimName;
      property tblFtrsDimUnits         : TField read FfFtrs_DimUnits;
      property tblFtrsEdtByPpk         : TField read FfFtrs_EdtByPpk;
      property tblFtrsEdtByZdi         : TField read FfFtrs_EdtByZdi;
      property tblFtrsEdtIPCPRd2       : TField read FfFtrs_EdtIPCPRd2;
      property tblFtrsEdtIPCPSampRd2   : TField read FfFtrs_EdtIPCPSampRd2;
      property tblFtrsEdtIPCPSamps     : TField read FfFtrs_EdtIPCPSamps;
      property tblFtrsEdtIPCPkSamprd2  : TField read FfFtrs_EdtIPCPkSamprd2;
      property tblFtrsEdtIPCPkSamps    : TField read FfFtrs_EdtIPCPkSamps;
      property tblFtrsEdtIPCPkrd2      : TField read FfFtrs_EdtIPCPkrd2;
      property tblFtrsEdtIPCPks        : TField read FfFtrs_EdtIPCPks;
      property tblFtrsEdtIPCPs         : TField read FfFtrs_EdtIPCPs;
      property tblFtrsEdtRSQCLCL       : TField read FfFtrs_EdtRSQCLCL;
      property tblFtrsEdtRSQCUCL       : TField read FfFtrs_EdtRSQCUCL;
      property tblFtrsEdtSRNom         : TField read FfFtrs_EdtSRNom;
      property tblFtrsFinalPlanID      : TField read FfFtrs_FinalPlanID;
      property tblFtrsFinalPlanType    : TField read FfFtrs_FinalPlanType;
      property tblFtrsFldrID           : TField read FfFtrs_FldrID;
      property tblFtrsFtrMClass        : TField read FfFtrs_FtrMClass;
      property tblFtrsFtrQClass        : TField read FfFtrs_FtrQClass;
      property tblFtrsFtrSuffix        : TField read FfFtrs_FtrSuffix;
      property tblFtrsFtrType          : TField read FfFtrs_FtrType;
      property tblFtrsGagePortNmbr     : TField read FfFtrs_GagePortNmbr;
      property tblFtrsID               : TField read FfFtrs_ID;
      property tblFtrsIPFinalPlanID    : TField read FfFtrs_IPFinalPlanID;
      property tblFtrsIPFinalPlanType  : TField read FfFtrs_IPFinalPlanType;
      property tblFtrsIPSet            : TField read FfFtrs_IPSet;
      property tblFtrsIndicator        : TField read FfFtrs_Indicator;
      property tblFtrsInspAsVar        : TField read FfFtrs_InspAsVar;
      property tblFtrsLSL              : TField read FfFtrs_LSL;
      property tblFtrsLastOnOff        : TField read FfFtrs_LastOnOff;
      property tblFtrsLowerTol         : TField read FfFtrs_LowerTol;
      property tblFtrsMainInsp         : TField read FfFtrs_MainInsp;
      property tblFtrsMasterID         : TField read FfFtrs_MasterID;
      property tblFtrsMathA            : TField read FfFtrs_MathA;
      property tblFtrsMathB            : TField read FfFtrs_MathB;
      property tblFtrsMathC            : TField read FfFtrs_MathC;
      property tblFtrsMathD            : TField read FfFtrs_MathD;
      property tblFtrsMathLine         : TField read FfFtrs_MathLine;
      property tblFtrsMultBy           : TField read FfFtrs_MultBy;
      property tblFtrsNextEvent        : TField read FfFtrs_NextEvent;
      property tblFtrsNominal          : TField read FfFtrs_Nominal;
      property tblFtrsNotation         : TField read FfFtrs_Notation;
      property tblFtrsNotes            : TField read FfFtrs_Notes;
      property tblFtrsNum              : TField read FfFtrs_Num;
      property tblFtrsOperID           : TField read FfFtrs_OperID;
      property tblFtrsOperOrd          : TField read FfFtrs_OperOrd;
      property tblFtrsOriginalLSL      : TField read FfFtrs_OriginalLSL;
      property tblFtrsOriginalUSL      : TField read FfFtrs_OriginalUSL;
      property tblFtrsProcON           : TField read FfFtrs_ProcON;
      property tblFtrsRSQCPrectrlOnly  : TField read FfFtrs_RSQCPrectrlOnly;
      property tblFtrsRbtIPFreq        : TField read FfFtrs_RbtIPFreq;
      property tblFtrsRbtIPMode        : TField read FfFtrs_RbtIPMode;
      property tblFtrsRbtIPSPCPriority : TField read FfFtrs_RbtIPSPCPriority;
      property tblFtrsRbtRSQCCLType    : TField read FfFtrs_RbtRSQCCLType;
      property tblFtrsRbtRSQCPpk       : TField read FfFtrs_RbtRSQCPpk;
      property tblFtrsRbtRSQCZdi       : TField read FfFtrs_RbtRSQCZdi;
      property tblFtrsRbtSRSTMode      : TField read FfFtrs_RbtSRSTMode;
      property tblFtrsRecFinalPlanID   : TField read FfFtrs_RecFinalPlanID;
      property tblFtrsRecFinalPlanType : TField read FfFtrs_RecFinalPlanType;
      property tblFtrsRedFlag          : TField read FfFtrs_RedFlag;
      property tblFtrsSpecType         : TField read FfFtrs_SpecType;
      property tblFtrsStatusOFF        : TField read FfFtrs_StatusOFF;
      property tblFtrsStatusON         : TField read FfFtrs_StatusON;
      property tblFtrsSubFinalPlanID   : TField read FfFtrs_SubFinalPlanID;
      property tblFtrsSubFinalPlanType : TField read FfFtrs_SubFinalPlanType;
      property tblFtrsTabIMode         : TField read FfFtrs_TabIMode;
      property tblFtrsTimerON          : TField read FfFtrs_TimerON;
      property tblFtrsUSL              : TField read FfFtrs_USL;
      property tblFtrsUpperTol         : TField read FfFtrs_UpperTol;
      property tblFtrsUseMathLine      : TField read FfFtrs_UseMathLine;
      property tblFtrsYellowFlag       : TField read FfFtrs_YellowFlag;
      property tblFtrsZeroAt           : TField read FfFtrs_ZeroAt;
      property tblFtrsZeroMode         : TField read FfFtrs_ZeroMode;
      property tblFtrscbxSIP           : TField read FfFtrs_cbxSIP;
      property tblFtrsedtFirstPUpper   : TField read FfFtrs_edtFirstPUpper;
      property tblFtrsedtFirstPlower   : TField read FfFtrs_edtFirstPlower;
      property tblFtrsedtIPFPcs        : TField read FfFtrs_edtIPFPcs;
      property tblFtrsedtIPFreq        : TField read FfFtrs_edtIPFreq;
      property tblFtrsedtIPRLLim       : TField read FfFtrs_edtIPRLLim;
      property tblFtrsedtIPRULim       : TField read FfFtrs_edtIPRULim;
      property tblFtrsedtIPSS          : TField read FfFtrs_edtIPSS;
      property tblFtrsedtIPYLLim       : TField read FfFtrs_edtIPYLLim;
      property tblFtrsedtIPYULim       : TField read FfFtrs_edtIPYULim;
      property tblFtrsedtLCL           : TField read FfFtrs_edtLCL;
      property tblFtrsedtMEPrecision   : TField read FfFtrs_edtMEPrecision;
      property tblFtrsedtMESSize       : TField read FfFtrs_edtMESSize;
      property tblFtrsedtUCL           : TField read FfFtrs_edtUCL;
      property tblFtrslsbFinalII       : TField read FfFtrs_lsbFinalII;
      property tblFtrslsbIPFinalII     : TField read FfFtrs_lsbIPFinalII;
      property tblFtrslsbRecFinalII    : TField read FfFtrs_lsbRecFinalII;
      property tblFtrslsbSubFinalII    : TField read FfFtrs_lsbSubFinalII;
      property tblFtrsrbtIPAccLim      : TField read FfFtrs_rbtIPAccLim;
      property tblFtrsrbtMError        : TField read FfFtrs_rbtMError;
      property tblFtrsrbtPrecontrType  : TField read FfFtrs_rbtPrecontrType;
      property tblFtrsrbtUnregul       : TField read FfFtrs_rbtUnregul;

      // OPERAT (4)
      property tblOperationCMMMultiplier: TField read FfOperation_CMMMultiplier;
      property tblOperationCMMType      : TField read FfOperation_CMMType;
      property tblOperationFileName     : TField read FfOperation_FileName;
      property tblOperationID           : TField read FfOperation_ID;
      {$ENDREGION}
  end;

  // Factory used by Blueprint4.pas:
  //   FBlueprint_ViewModel := Blueprint_ViewModelCreateClass(MyFolder.ID);
function Blueprint_ViewModelCreateClass(const pFLDRID: Integer): IBlueprint_ViewModel;

implementation

uses
  System.TypInfo
  , System.IOUtils // TFile.AppendAllText for persistence-debug log file
  , CodeSiteLogging
  , Blueprint4.CADImport
  , Blueprint4.PDFImport
  // ControlPlan2 = real Process Control Planning editor (replaces the Phase-0 Blueprint4.ControlPlan2 stub)
  , ControlPlan2
  , uLookupCache
  , uMDIChildManager // 2026-07-02 per-folder singleton reuse (activate-or-create)
  , uLogPaths // 2026-07-02 host-aware log dir (BP4 diagnostic logs -> ATEST\LOG on HTRTEST)
  ;

procedure PersistLog(const AMsg: string);
// File-based log of the Job Header persistence path. Appends to
// BP4_PERSIST.log so the user can paste content without CodeSite.
// Mirrors the CodeSite traces in DoAfterPostFolder + SendDeltaFolder.
// 2026-07-02 host-aware path (HTRTEST -> D:\MICDATA_D\ATEST\LOG, else C:\TEMP1).
begin
  try
    TFile.AppendAllText(LogFilePath('BP4_PERSIST.log'), FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' | ' + AMsg + sLineBreak, TEncoding.UTF8);
  except
    // Swallow file errors; do not crash if the log dir is missing.
  end;
end;

const
  C_PHASE2_TODO = 'TODO Phase 2 ? method not yet migrated from BDE Blueprint4.Model.OLD';

const
  RestOfThem: TArray<string> = [
    'edtNotes', 'edtGagePort', 'edtSuffix', 'edtClass', 'edtOperOrder', 'edtDecimals', 'edtunits', 'edtIndicator', 'edtZeroAt', 'edtConvertReading', 'edtMultBy', 'edtAdd',
    'edtUseAbsValue', 'edtUseMathLine', 'edtMathLine', 'edtA', 'edtB', 'edtC', 'edtD', 'edtAbbr', 'edtDataChannel', 'edtNum'];

  FieldOrder0: TArray<string>{ array [0 .. 36] of string } = [
    'edtName', 'edtUSL', 'edtLSL', 'edtNominal', 'edtUpper', 'edtLower', 'edtNotes', 'edtGagePort', 'edtSuffix', 'edtClass', 'edtOperOrder', 'edtDecimals', 'edtunits',
    'edtIndicator', 'edtZeroAt', 'edtConvertReading', 'edtMultBy', 'edtAdd', 'edtUseAbsValue', 'edtUseMathLine', 'edtMathLine', 'edtA', 'edtB', 'edtC', 'edtD', 'edtAbbr',
    'edtDataChannel', 'btnSpecDouble', 'btnSpecSingle', 'btnNotationSpec', 'btnNotationTolerance', 'edtNum'];

  EditFields0: array [1 .. 32] of REditField = (//
    (idx: 1 ; Field: 'edtNum'              ; Description: '#'                              ; DBField: 'Num'          ), // 1	edtNum
    (idx: 2 ; Field: 'edtName'             ; Description: 'Name'                           ; DBField: 'DimName'      ), // 2	edtName
    (idx: 3 ; Field: 'btnSpecDouble'       ; Description: 'Spec Limits Double'             ; DBField: 'SpecType'     ), // 3	btnSpecDouble
    (idx: 4 ; Field: 'btnSpecSingle'       ; Description: 'Spec Limits Single (Upper only)'; DBField: 'SpecType'     ), // 4	btnSpecSingle
    (idx: 5 ; Field: 'btnNotationSpec'     ; Description: 'Notatiuon Spec'                 ; DBField: 'Notation'     ), // 5	btnNotationSpec
    (idx: 6 ; Field: 'btnNotationTolerance'; Description: 'Notation Tolerance'             ; DBField: 'Notation'     ), // 6	tnNotationTolerance
    (idx: 7 ; Field: 'edtUSL'              ; Description: 'USL'                            ; DBField: 'USL'          ), // 7	edtUSL
    (idx: 8 ; Field: 'edtLSL'              ; Description: 'LSL'                            ; DBField: 'LSL'          ), // 8	edtLSL
    (idx: 9 ; Field: 'edtNominal'          ; Description: 'Nominal'                        ; DBField: 'Nominal'      ), // 9	edtNominal
    (idx: 10; Field: 'edtUpper'            ; Description: 'Upper Tolerance'                ; DBField: 'UpperTol'     ), // 10	edtUpper
    (idx: 11; Field: 'edtLower'            ; Description: 'Lower Tolerance '               ; DBField: 'LowerTol'     ), // 11	edtLower
    (idx: 12; Field: 'edtSuffix'           ; Description: 'Suffix'                         ; DBField: 'FtrSuffix'    ), // 12	edtSuffix
    (idx: 13; Field: 'edtClass'            ; Description: 'Class'                          ; DBField: 'FtrMClass'    ), // 13	edtClass
    (idx: 14; Field: 'edtOperOrder'        ; Description: 'Custom Order'                   ; DBField: 'OperOrd'      ), // 14	edtOperOrder
    (idx: 15; Field: 'edtDecimals'         ; Description: 'Decimals'                       ; DBField: 'Decimals'     ), // 15	edtDecimals
    (idx: 16; Field: 'edtUnits'            ; Description: 'Units '                         ; DBField: 'DimUnits'     ), // 16	edtUnits
    (idx: 17; Field: 'edtAbbr'             ; Description: 'Abbreviation'                   ; DBField: 'DimAbbr'      ), // 17	edtAbbr
    (idx: 18; Field: 'edtIndicator'        ; Description: 'Indicator'                      ; DBField: 'FINDICATOR'   ), // 18	edtIndicator (MSCLIST col is FINDICATOR)
    (idx: 19; Field: 'edtZeroAt'           ; Description: 'Set zero at'                    ; DBField: 'ZeroAt'       ), // 19	edtZeroAt
    (idx: 20; Field: 'edtConvertReading'   ; Description: 'Convert Readings'               ; DBField: 'FCONVERT'     ), // 20	edtConvertReading (MSCLIST col is FCONVERT)
    (idx: 21; Field: 'edtMultBy'           ; Description: 'Multiply by'                    ; DBField: 'MultBy'       ), // 21	edtMultBy
    (idx: 22; Field: 'edtAdd'              ; Description: 'Add'                            ; DBField: 'Addto'        ), // 22	edtAdd
    (idx: 23; Field: 'edtUseAbsValue'      ; Description: 'Use absolute value'             ; DBField: 'AbsoluteValue'), // 23	edtUseAbsValue
    (idx: 24; Field: 'edtUseMathLine'      ; Description: 'Use MathLine'                   ; DBField: 'UseMathLine'  ), // 24	edtUseMathLine
    (idx: 25; Field: 'edtMathLine'         ; Description: 'MathLine'                       ; DBField: 'MathLine'     ), // 25	edtMathLine
    (idx: 26; Field: 'edtA'                ; Description: 'A'                              ; DBField: 'MathA'        ), // 26	edtA
    (idx: 27; Field: 'edtB'                ; Description: 'B'                              ; DBField: 'MathB'        ), // 27	edtB
    (idx: 28; Field: 'edtC'                ; Description: 'C'                              ; DBField: 'MathC'        ), // 28	edtC
    (idx: 29; Field: 'edtD'                ; Description: 'D'                              ; DBField: 'MathD'        ), // 29	edtD
    (idx: 30; Field: 'edtGagePort'         ; Description: 'Gage port'                      ; DBField: 'GagePortNmbr' ), // 30	edtGagePort
    (idx: 31; Field: 'edtDataChannel'      ; Description: 'Data channel'                   ; DBField: 'DataChannel'  ), // 31	edtDataChannel
    (idx: 32; Field: 'edtNotes'; Description: 'Instructions'; DBField: 'Notes')// 32	edtNotes
  ); //

  { ----- factory ----- }
function Blueprint_ViewModelCreateClass(const pFLDRID: Integer): IBlueprint_ViewModel;
begin
  Result:= TBlueprint_ViewModel.Create(AppConnection, pFLDRID);
end;

{ ----- TBlueprint_ViewModel ----- }

constructor TBlueprint_ViewModel.Create(AConn: TPipeClientConnection; AFldrID: Integer);
var
  I : Integer;
  XF: TField ;
begin
  inherited Create;
  FConn          := AConn;
  FFldrID        := AFldrID;
  FSchemaBuilt   := False;
  FSuppressEvents:= False;
  FImportHeadless:= False;
  FImportReport:= TStringList.Create;
  FLoadEnabled:= True;
  FSaveEnabled:= True;
  FLotSize    := 0;
  FEditField  := EmptyEditField;

  // 2026-05-14 -- FTR working buffer. Reference-counted; releases automatically.
  FFTR:= TmcMSCLIST.Create(nil) as ImcMSCLIST;

  FMTFtrs:= TFDMemTable.Create(nil);
  FMTFtrs.AfterPost  := DoAfterPostFtrs;
  FMTFtrs.AfterDelete:= DoAfterDeleteFtrs;
  FMTOperation:= TFDMemTable.Create(nil);
  FMTOperation.AfterPost  := DoAfterPostOperation;
  FMTOperation.AfterDelete:= DoAfterDeleteOperation;
  FMTOSublot := TFDMemTable.Create(nil);
  FMTGInsp   := TFDMemTable.Create(nil);
  FMTIInsp   := TFDMemTable.Create(nil);
  FMTInspRslt:= TFDMemTable.Create(nil);
  FMTIPChart := TFDMemTable.Create(nil);
  FMTCPSet   := TFDMemTable.Create(nil);
  FMTMUSet   := TFDMemTable.Create(nil);
  FMTPPSet   := TFDMemTable.Create(nil);
  FMTGonOff  := TFDMemTable.Create(nil);
  FMTPlanList:= TFDMemTable.Create(nil);
  FMTReadings:= TFDMemTable.Create(nil);
  FMTFolder  := TFDMemTable.Create(nil);
  FMTFolder.AfterPost:= DoAfterPostFolder; // Job Header write-back (cmdDelta)
  FMTMachines:= TFDMemTable.Create(nil); // unfiltered plant-wide MACHINES

  FDsrFtrs     := TDataSource.Create(nil); FDsrFtrs     .DataSet:= FMTFtrs;
  FDsrOperation:= TDataSource.Create(nil); FDsrOperation.DataSet:= FMTOperation;
  FDsrFolder   := TDataSource.Create(nil); FDsrFolder   .DataSet:= FMTFolder;
  FDsrMachines  := TDataSource.Create(nil); FDsrMachines.DataSet:= FMTMachines;
  // FtrNames / OperNames: DataSet is wired lazily in the getter so the constructor
  // does NOT call LookupCache.Table() while the global VCL application is still
  // initialising (avoids a TFDMemTable notification-loop hang in headless / autotest paths).
  FDsrFtrNames  := TDataSource.Create(nil);
  FDsrOperNames := TDataSource.Create(nil);

  // 2026-05-17 -- Schema must exist before we resolve EditFields' DB fields.
  // FMTFtrs is an empty TFDMemTable until BuildSchema runs CreateDataSet;
  // calling FieldByName before that raised EDatabaseError 'Field "Num"
  // not found' on the first EditFields0 entry (DBField='Num').
  BuildSchema;

  EditFields.Assign(EditFields0);
  for I:= low(EditFields.Data) to high(EditFields.Data) do // Iterate
  begin
    EditFields.Data[I].XControl:= nil;
    EditFields.Data[I].XField  := nil;
    EditFields.Data[I].Field:= EditFields[I].Field.ToUpper;
    XF:= tblFtrs.FindField(EditFields[I].DBField);
    if not Assigned(XF) then raise Exception.CreateFmt('Unable to find DB Field %d. "%s" in TBlueprint4_Model.Initialize', [I, EditFields[I].DBField]);
    EditFields.Data[I].XField:= XF;
  end; // for

  FFTRCreated:= False;
  FieldOrder := FieldOrder0;
  for I:= low(FieldOrder.Data) to high(FieldOrder.Data) do FieldOrder.Data[I]:= FieldOrder.Data[I].ToUpper;

  FActiveField:= EmptyEditField;
end; // constructor

destructor TBlueprint_ViewModel.Destroy;
begin
  FImportReport.Free;
  FDsrFtrs.Free;
  FDsrOperation.Free;
  FDsrFolder.Free;
  FDsrMachines.Free;
  FDsrFtrNames.Free;
  FDsrOperNames.Free;
  FMTMachines.Free;
  FMTFolder.Free;
  FMTFtrs.Free;
  FMTOperation.Free;
  FMTOSublot.Free;
  FMTGInsp.Free;
  FMTIInsp.Free;
  FMTInspRslt.Free;
  FMTIPChart.Free;
  FMTCPSet.Free;
  FMTMUSet.Free;
  FMTPPSet.Free;
  FMTGonOff.Free;
  FMTPlanList.Free;
  FMTReadings.Free;
  inherited;
end; // destructor

{ ----- schema ----- }

procedure TBlueprint_ViewModel.BuildSchema;
// Create one TCalculatedField on AMT. Must run BEFORE AMT.CreateDataSet so
// FireDAC includes the field in the in-memory record layout.
  procedure C(AMT: TFDMemTable; const AName: string; AType: TFieldType; ASize: Integer = 0);
  var
    F: TField;
  begin
    case AType of
      ftWideString: F:= TWideStringField.Create(AMT);
      ftString    : F:= TStringField    .Create(AMT);
      ftFloat     : F:= TFloatField     .Create(AMT);
      ftBoolean   : F:= TBooleanField   .Create(AMT);
      ftInteger   : F:= TIntegerField   .Create(AMT);
      else F:= TWideStringField.Create(AMT);
    end;
    F.FieldName:= AName;
    F.FieldKind:= fkCalculated;
    if (ASize > 0) and (F is TWideStringField) then TWideStringField(F).Size:= ASize;
    if (ASize > 0) and (F is TStringField    ) then TStringField    (F).Size:= ASize;
    F.DataSet:= AMT;
  end;
  procedure B(AMT: TFDMemTable; const ATableName: string);
  begin
    if not TFieldsInfoFactory.BuildMemTable(AMT, ATableName, False, []) then
      raise EDatabaseError.CreateFmt( '%s: %s metadata not in FieldsInfoCache. Session bootstrap may have failed.', [ClassName, ATableName]);
    AMT.CreateDataSet;
  end;
begin
  if FSchemaBuilt then Exit;
  // 2026-05-20 -- MSCLIST: build persistent fields, add 12 calculated fields,
  // THEN CreateDataSet. The 12 calc fields are populated by FtrsOnCalcFields
  // (ported from legacy tblFtrsCalcFields). DFM grid columns bound to them
  // (FtrName/ClassName/USLLSLName/DimAbbrSmall/Tolerance/ToolName/InspIsSet/
  // Duein/StatusONStr/StatusOFFstr/InspAsVarStr/Attribute) render once these
  // exist on the memtable.
  if not TFieldsInfoFactory.BuildMemTable(FMTFtrs, 'MSCLIST', False, []) then
    raise EDatabaseError.CreateFmt( '%s: MSCLIST metadata not in FieldsInfoCache. Session bootstrap may have failed.', [ClassName]);
  C(FMTFtrs, 'FtrName'     , ftWideString, 200);
  C(FMTFtrs, 'ClassName'   , ftWideString, 30 );
  C(FMTFtrs, 'USLLSLName'  , ftWideString, 200);
  C(FMTFtrs, 'DimAbbrSmall', ftWideString, 40 );
  C(FMTFtrs, 'Tolerance' , ftFloat );
  C(FMTFtrs, 'ToolName' , ftWideString, 80);
  C(FMTFtrs, 'InspIsSet' , ftBoolean );
  C(FMTFtrs, 'Duein'       , ftWideString, 20);
  C(FMTFtrs, 'StatusONStr' , ftWideString, 40);
  C(FMTFtrs, 'StatusOFFstr', ftWideString, 40);
  C(FMTFtrs, 'InspAsVarStr', ftWideString, 20);
  C(FMTFtrs, 'Attribute' , ftBoolean );
  FMTFtrs.CreateDataSet;
  B(FMTOperation, 'OPERAT' );
  // 2026-05-17 -- This Setup/Router screen uses ONLY MSCLIST + OPERAT. The
  // 11 inspection/results schemas below belong to a later screen; building
  // them here just wastes startup time. Their TFDMemTables still exist (the
  // ctor created them empty) so any reference stays valid -- they are simply
  // not CreateDataSet'd until that screen lazy-builds them. CacheFieldRefs
  // and the master-detail wiring below only touch FMTFtrs/FMTOperation, so
  // skipping these is safe. Re-enable per-table when the next screen needs it.
  // B(FMTOSublot  , 'OSUBLOT'  );
  // B(FMTGInsp    , 'GINSP'    );
  // B(FMTIInsp    , 'IINSP'    );
  // B(FMTInspRslt , 'INSPRSLT' );
  // B(FMTIPChart  , 'IPCHART'  );
  // B(FMTCPSet    , 'CPSET'    );
  // B(FMTMUSet    , 'MUSET'    );
  // B(FMTPPSet    , 'PPSET'    );
  // B(FMTGonOff   , 'GONOFF'   );
  // B(FMTPlanList , 'PLANLIST' );
  // B(FMTReadings , 'READINGS' );
  CacheFieldRefs;
  // 2026-05-20 -- Wire OnCalcFields to populate 12 virtual fields
  FMTFtrs.OnCalcFields:= FtrsOnCalcFields;
  // 2026-05-14 -- Master-detail: FMTFtrs auto-filters by current OPERAT row.
  // Empty operation -> empty chars grid. Scrolling OPERAT retops MSCLIST.
  FMTFtrs.IndexFieldNames:= 'OPERID';
  FMTFtrs.MasterSource   := FDsrOperation;
  FMTFtrs.MasterFields   := 'ID'; // OPERAT.ID
  FMTFtrs.DetailFields   := 'OPERID'; // MSCLIST.OPERID
  FSchemaBuilt:= True;
end; // begin

procedure TBlueprint_ViewModel.CacheFieldRefs;
var
  Missing: string;
  // 2026-05-17 hardening: FindField returns nil silently on a name mismatch,
  // which left ~110 cached TField refs nil and turned a typo into a delayed
  // AV far from the cause (the FINDICATOR/FCONVERT/INDICATOR class of bugs).
  // FF now accumulates every unresolved name; we raise ONCE at the end with
  // the full list, so a bad column name fails loudly at schema-build time.
  function FF(AMT: TFDMemTable; const AName: string): TField;
  begin
    Result:= AMT.FindField(AName);
    if Result = nil then Missing:= Missing + AName + ' ';
  end;
begin
  Missing:= '';
  // MSCLIST ? names match the lowercase-aware Imports.pas usage but resolve
  // to uppercase SQL column names (Firebird is case-insensitive for unquoted
  // identifiers).
  FfFtrs_AbsoluteValue   := FF(FMTFtrs, 'ABSOLUTEVALUE'   );
  FfFtrs_Addto           := FF(FMTFtrs, 'ADDTO'           );
  FfFtrs_AttrCode        := FF(FMTFtrs, 'ATTRCODE'        );
  FfFtrs_AttrName        := FF(FMTFtrs, 'ATTRNAME'        );
  FfFtrs_AttrType        := FF(FMTFtrs, 'ATTRTYPE'        );
  FfFtrs_CbxFinalI       := FF(FMTFtrs, 'CBXFINALI'       );
  FfFtrs_CbxPCAP         := FF(FMTFtrs, 'CBXPCAP'         );
  FfFtrs_CbxPCAPPROP     := FF(FMTFtrs, 'CBXPCAPPROP'     );
  FfFtrs_CbxRunSQC       := FF(FMTFtrs, 'CBXRUNSQC'       );
  FfFtrs_CbxSetR         := FF(FMTFtrs, 'CBXSETR'         );
  FfFtrs_CbxStab         := FF(FMTFtrs, 'CBXSTAB'         );
  FfFtrs_CbxTFirstA      := FF(FMTFtrs, 'CBXTFIRSTA'      );
  FfFtrs_Convert         := FF(FMTFtrs, 'FCONVERT'        );
  FfFtrs_DataChannel     := FF(FMTFtrs, 'DATACHANNEL'     );
  FfFtrs_Decimals        := FF(FMTFtrs, 'DECIMALS'        );
  FfFtrs_DimAbbr         := FF(FMTFtrs, 'DIMABBR'         );
  FfFtrs_DimName         := FF(FMTFtrs, 'DIMNAME'         );
  FfFtrs_DimUnits        := FF(FMTFtrs, 'DIMUNITS'        );
  FfFtrs_DoIPCF          := FF(FMTFtrs, 'DOIPCF'          );
  FfFtrs_DoRSCF          := FF(FMTFtrs, 'DORSCF'          );
  FfFtrs_DoSbCF          := FF(FMTFtrs, 'DOSBCF'          );
  FfFtrs_EdtByPpk        := FF(FMTFtrs, 'EDTBYPPK'        );
  FfFtrs_EdtByZdi        := FF(FMTFtrs, 'EDTBYZDI'        );
  FfFtrs_EdtIPCPRd2      := FF(FMTFtrs, 'EDTIPCPRD2'      );
  FfFtrs_EdtIPCPSampRd2  := FF(FMTFtrs, 'EDTIPCPSAMPRD2'  );
  FfFtrs_EdtIPCPSamps    := FF(FMTFtrs, 'EDTIPCPSAMPS'    );
  FfFtrs_EdtIPCPkSamprd2 := FF(FMTFtrs, 'EDTIPCPKSAMPRD2' );
  FfFtrs_EdtIPCPkSamps   := FF(FMTFtrs, 'EDTIPCPKSAMPS'   );
  FfFtrs_EdtIPCPkrd2     := FF(FMTFtrs, 'EDTIPCPKRD2'     );
  FfFtrs_EdtIPCPks       := FF(FMTFtrs, 'EDTIPCPKS'       );
  FfFtrs_EdtIPCPs        := FF(FMTFtrs, 'EDTIPCPS'        );
  FfFtrs_EdtRSQCLCL      := FF(FMTFtrs, 'EDTRSQCLCL'      );
  FfFtrs_EdtRSQCUCL      := FF(FMTFtrs, 'EDTRSQCUCL'      );
  FfFtrs_EdtSRNom        := FF(FMTFtrs, 'EDTSRNOM'        );
  FfFtrs_FinalPlanID     := FF(FMTFtrs, 'FINALPLANID'     );
  FfFtrs_FinalPlanType   := FF(FMTFtrs, 'FINALPLANTYPE'   );
  FfFtrs_FldrID          := FF(FMTFtrs, 'FLDRID'          );
  FfFtrs_FtrMClass       := FF(FMTFtrs, 'FTRMCLASS'       );
  FfFtrs_FtrQClass       := FF(FMTFtrs, 'FTRQCLASS'       );
  FfFtrs_FtrSuffix       := FF(FMTFtrs, 'FTRSUFFIX'       );
  FfFtrs_FtrType         := FF(FMTFtrs, 'FTRTYPE'         );
  FfFtrs_GagePortNmbr    := FF(FMTFtrs, 'GAGEPORTNMBR'    );
  FfFtrs_ID              := FF(FMTFtrs, 'ID'              );
  FfFtrs_IPFinalPlanID   := FF(FMTFtrs, 'IPFINALPLANID'   );
  FfFtrs_IPFinalPlanType := FF(FMTFtrs, 'IPFINALPLANTYPE' );
  FfFtrs_IPSet           := FF(FMTFtrs, 'IPSET'           );
  FfFtrs_Indicator       := FF(FMTFtrs, 'FINDICATOR'      );
  FfFtrs_InspAsVar       := FF(FMTFtrs, 'INSPASVAR'       );
  FfFtrs_LSL             := FF(FMTFtrs, 'LSL'             );
  FfFtrs_LastOnOff       := FF(FMTFtrs, 'LASTONOFF'       );
  FfFtrs_LowerTol        := FF(FMTFtrs, 'LOWERTOL'        );
  FfFtrs_MainInsp        := FF(FMTFtrs, 'MAININSP'        );
  FfFtrs_MasterID        := FF(FMTFtrs, 'MASTERID'        );
  FfFtrs_MathA           := FF(FMTFtrs, 'MATHA'           );
  FfFtrs_MathB           := FF(FMTFtrs, 'MATHB'           );
  FfFtrs_MathC           := FF(FMTFtrs, 'MATHC'           );
  FfFtrs_MathD           := FF(FMTFtrs, 'MATHD'           );
  FfFtrs_MathLine        := FF(FMTFtrs, 'MATHLINE'        );
  FfFtrs_MultBy          := FF(FMTFtrs, 'MULTBY'          );
  FfFtrs_NextEvent       := FF(FMTFtrs, 'NEXTEVENT'       );
  FfFtrs_Nominal         := FF(FMTFtrs, 'NOMINAL'         );
  FfFtrs_Notation        := FF(FMTFtrs, 'NOTATION'        );
  FfFtrs_Notes           := FF(FMTFtrs, 'NOTES'           );
  FfFtrs_Num             := FF(FMTFtrs, 'NUM'             );
  FfFtrs_OperID          := FF(FMTFtrs, 'OPERID'          );
  FfFtrs_OperOrd         := FF(FMTFtrs, 'OPEROrd'         );
  FfFtrs_OriginalLSL     := FF(FMTFtrs, 'ORIGINALLSL'     );
  FfFtrs_OriginalUSL     := FF(FMTFtrs, 'ORIGINALUSL'     );
  FfFtrs_ProcON          := FF(FMTFtrs, 'PROCON'          );
  FfFtrs_RSQCPrectrlOnly := FF(FMTFtrs, 'RSQCPRECTRLONLY' );
  FfFtrs_RbtIPFreq       := FF(FMTFtrs, 'RBTIPFREQ'       );
  FfFtrs_RbtIPMode       := FF(FMTFtrs, 'RBTIPMODE'       );
  FfFtrs_RbtIPSPCPriority:= FF(FMTFtrs, 'RBTIPSPCPRIORITY');
  FfFtrs_RbtRSQCCLType   := FF(FMTFtrs, 'RBTRSQCCLTYPE'   );
  FfFtrs_RbtRSQCPpk      := FF(FMTFtrs, 'RBTRSQCPPK'      );
  FfFtrs_RbtRSQCZdi      := FF(FMTFtrs, 'RBTRSQCZDI'      );
  FfFtrs_RbtSRSTMode     := FF(FMTFtrs, 'RBTSRSTMODE'     );
  FfFtrs_RecFinalPlanID  := FF(FMTFtrs, 'RECFINALPLANID'  );
  FfFtrs_RecFinalPlanType:= FF(FMTFtrs, 'RECFINALPLANTYPE');
  FfFtrs_RedFlag         := FF(FMTFtrs, 'REDFLAG'         );
  FfFtrs_SSortIP         := FF(FMTFtrs, 'SSORTIP'         );
  FfFtrs_SSortME         := FF(FMTFtrs, 'SSORTME'         );
  FfFtrs_SpecType        := FF(FMTFtrs, 'SPECTYPE'        );
  FfFtrs_StatusOFF       := FF(FMTFtrs, 'STATUSOFF'       );
  FfFtrs_StatusON        := FF(FMTFtrs, 'STATUSON'        );
  FfFtrs_SubFinalPlanID  := FF(FMTFtrs, 'SUBFINALPLANID'  );
  FfFtrs_SubFinalPlanType:= FF(FMTFtrs, 'SUBFINALPLANTYPE');
  FfFtrs_TabIMode        := FF(FMTFtrs, 'TABIMODE'        );
  FfFtrs_TimerON         := FF(FMTFtrs, 'TIMERON'         );
  FfFtrs_USL             := FF(FMTFtrs, 'USL'             );
  FfFtrs_UpperTol        := FF(FMTFtrs, 'UPPERTOL'        );
  FfFtrs_UseMathLine     := FF(FMTFtrs, 'USEMATHLINE'     );
  FfFtrs_YellowFlag      := FF(FMTFtrs, 'YELLOWFLAG'      );
  FfFtrs_ZeroAt          := FF(FMTFtrs, 'ZEROAT'          );
  FfFtrs_ZeroMode        := FF(FMTFtrs, 'ZEROMODE'        );
  FfFtrs_cbxSIP          := FF(FMTFtrs, 'CBXSIP'          );
  FfFtrs_edtFirstPUpper  := FF(FMTFtrs, 'EDTFIRSTPUPPER'  );
  FfFtrs_edtFirstPlower  := FF(FMTFtrs, 'EDTFIRSTPLOWER'  );
  FfFtrs_edtIPFPcs       := FF(FMTFtrs, 'EDTIPFPCS'       );
  FfFtrs_edtIPFreq       := FF(FMTFtrs, 'EDTIPFREQ'       );
  FfFtrs_edtIPRLLim      := FF(FMTFtrs, 'EDTIPRLLIM'      );
  FfFtrs_edtIPRULim      := FF(FMTFtrs, 'EDTIPRULIM'      );
  FfFtrs_edtIPSS         := FF(FMTFtrs, 'EDTIPSS'         );
  FfFtrs_edtIPYLLim      := FF(FMTFtrs, 'EDTIPYLLIM'      );
  FfFtrs_edtIPYULim      := FF(FMTFtrs, 'EDTIPYULIM'      );
  FfFtrs_edtLCL          := FF(FMTFtrs, 'EDTLCL'          );
  FfFtrs_edtMEPrecision  := FF(FMTFtrs, 'EDTMEPRECISION'  );
  FfFtrs_edtMESSize      := FF(FMTFtrs, 'EDTMESSIZE'      );
  FfFtrs_edtUCL          := FF(FMTFtrs, 'EDTUCL'          );
  FfFtrs_lsbFinalII      := FF(FMTFtrs, 'LSBFINALII'      );
  FfFtrs_lsbIPFinalII    := FF(FMTFtrs, 'LSBIPFINALII'    );
  FfFtrs_lsbRecFinalII   := FF(FMTFtrs, 'LSBRECFINALII'   );
  FfFtrs_lsbSubFinalII   := FF(FMTFtrs, 'LSBSUBFINALII'   );
  FfFtrs_rbtIPAccLim     := FF(FMTFtrs, 'RBTIPACCLIM'     );
  FfFtrs_rbtMError       := FF(FMTFtrs, 'RBTMERROR'       );
  FfFtrs_rbtPrecontrType := FF(FMTFtrs, 'RBTPRECONTRTYPE' );
  FfFtrs_rbtUnregul      := FF(FMTFtrs, 'RBTUNREGUL'      );

  // OPERAT
  FfOperation_CMMMultiplier:= FF(FMTOperation, 'CMMMULTIPLIER');
  FfOperation_CMMType      := FF(FMTOperation, 'CMMTYPE'      );
  FfOperation_FileName     := FF(FMTOperation, 'FILENAME'     );
  FfOperation_ID           := FF(FMTOperation, 'ID'           );

  // 2026-05-20 -- Calculated MSCLIST fields (created in BuildSchema via C()).
  FfFtrs_FtrName     := FF(FMTFtrs, 'FtrName'      );
  FfFtrs_ClassName   := FF(FMTFtrs, 'ClassName'    );
  FfFtrs_USLLSLName  := FF(FMTFtrs, 'USLLSLName'   );
  FfFtrs_DimAbbrSmall:= FF(FMTFtrs, 'DimAbbrSmall' );
  FfFtrs_Tolerance   := FF(FMTFtrs, 'Tolerance'    );
  FfFtrs_ToolName    := FF(FMTFtrs, 'ToolName'     );
  FfFtrs_InspIsSet   := FF(FMTFtrs, 'InspIsSet'    );
  FfFtrs_Duein       := FF(FMTFtrs, 'Duein'        );
  FfFtrs_StatusONStr := FF(FMTFtrs, 'StatusONStr'  );
  FfFtrs_StatusOFFstr:= FF(FMTFtrs, 'StatusOFFstr' );
  FfFtrs_InspAsVarStr:= FF(FMTFtrs, 'InspAsVarStr' );
  FfFtrs_Attribute   := FF(FMTFtrs, 'Attribute'    );

  if Missing <> '' then raise EDatabaseError.CreateFmt(
    'CacheFieldRefs: unresolved column(s) in MSCLIST/OPERAT memtable ' + 'schema -> [%s]. The FF() name does not match a live DB column / '
      + 'FIB$FIELDS_INFO (the FINDICATOR/FCONVERT class of bug).', [Trim(Missing)]);
end; // begin

procedure TBlueprint_ViewModel.FtrsOnCalcFields(DataSet: TDataSet);
// 2026-05-20 -- Populate 12 virtual/calculated fields from dependent columns.
// These fields are bound in Blueprint4.dfm grid columns but not stored in database.
// 2026-06-23: USLLSLName/ToolName/InspIsSet/DueIn/StatusOFFstr ported from the
// legacy tblFtrsCalcFields (Blueprint4.Model.pas.OLD); ToolName needs an FTRTOOL
// lookup not yet loaded in ORM3, so it stays blank (documented below).
var
  FtrType: Integer  ;
  Dec    : Integer  ;
  Spec   : string   ;
  Mins   : Integer  ;
begin
  if DataSet.State = dsInsert then Exit;

  // FTRTYPE / FTRMCLASS / SPECTYPE / NOTATION are D_BYTETAG (BINARY(1))
  // -> TBytesField at runtime. .AsInteger raises TField.AccessError.
  // Use TagOf() which decodes the single OCTETS byte to an Integer.
  FtrType:= TagOf(FfFtrs_FtrType);

  // FTRNAME - primary characteristic name for grid display.
  // 2026-06-23: full legacy notation/spec-aware name (MSCTYPES.FtrNameString port,
  // ex FtrDefs.getFtrName) replacing the simplified "DimName (DimAbbr)".
  // Byte-tag FTRTYPE/SPECTYPE/NOTATION decoded via TagOf(); master rows (ID=MasterID)
  // upper-cased, subordinate rows lower-cased; abbreviation-based (pUseAbbr=True).
  if Assigned(FfFtrs_FtrName) then
    FfFtrs_FtrName.AsString:= FtrNameString(
      TagOf(FfFtrs_Notation), TagOf(FfFtrs_SpecType),
      FfFtrs_USL.AsFloat, FfFtrs_LSL.AsFloat, FfFtrs_Decimals.AsInteger,
      FfFtrs_Nominal.AsFloat, FfFtrs_UpperTol.AsFloat, FfFtrs_LowerTol.AsFloat,
      FtrType, FfFtrs_MathLine.AsString, FfFtrs_DimAbbr.AsString, FfFtrs_DimName.AsString,
      FfFtrs_FtrSuffix.AsString, FfFtrs_AttrName.AsString, FfFtrs_AttrType.AsString,
      FfFtrs_AttrCode.AsString,
      FfFtrs_ID.AsLargeInt = FfFtrs_MasterID.AsLargeInt, True);

  // CLASSNAME - TCharMClass as string
  if Assigned(FfFtrs_ClassName) then FfFtrs_ClassName.AsString:= TCharMClass.FromInteger(TagOf(FfFtrs_FtrMClass)).ToString;

  // USLLSLNAME -- spec representation (ported from legacy DimSpec_StrReprf):
  // Variable -> spec string by SpecType/Notation; Attribute -> AttrName
  // (lower-cased on a subordinate row, ID<>MasterID); Group/other -> DimName.
  if Assigned(FfFtrs_USLLSLName) then
  begin
    if FtrType = Integer(FtrType_Variable) then
    begin
      Dec:= FfFtrs_Decimals.AsInteger;
      case TSpecType.FromInteger(TagOf(FfFtrs_SpecType)) of
        SpecType_Double:
          case TSpecNotation.FromInteger(TagOf(FfFtrs_Notation)) of
            SpecNotation_Tolerance: Spec:= FloatToStrF(FfFtrs_Nominal .AsFloat, ffFixed, 15, Dec)
                + ' +' + FloatToStrF(FfFtrs_UpperTol.AsFloat, ffFixed, 15, Dec)
                + ' / -' + FloatToStrF(FfFtrs_LowerTol.AsFloat, ffFixed, 15, Dec);
            else Spec:= FloatToStrF(FfFtrs_LSL.AsFloat, ffFixed, 15, Dec)
                + ' / ' + FloatToStrF(FfFtrs_USL.AsFloat, ffFixed, 15, Dec);
          end;
        SpecType_SingleUpper: Spec:= FloatToStrF(FfFtrs_USL.AsFloat, ffFixed, 15, Dec) + ' MAX';
        SpecType_SingleLower: Spec:= FloatToStrF(FfFtrs_LSL.AsFloat, ffFixed, 15, Dec) + ' MIN';
        else Spec:= '';
      end;
      FfFtrs_USLLSLName.AsString:= Spec;
    end
    else if FtrType = Integer(FtrType_Attribute) then
    begin
      if FfFtrs_ID.AsLargeInt <> FfFtrs_MasterID.AsLargeInt then
        FfFtrs_USLLSLName.AsString:= LowerCase(FfFtrs_AttrName.AsString)
      else
        FfFtrs_USLLSLName.AsString:= UpperCase(FfFtrs_AttrName.AsString);
    end
    else
      FfFtrs_USLLSLName.AsString:= FfFtrs_DimName.AsString;
  end;

  // DIMABBRSMALL - dimension abbreviation
  if Assigned(FfFtrs_DimAbbrSmall) then FfFtrs_DimAbbrSmall.AsString:= FfFtrs_DimAbbr.AsString;

  // TOLERANCE -- legacy tblFtrsCalcFields logic:
  //   SpecType_Double:
  //     Notation_Spec      -> USL - LSL
  //     Notation_Tolerance -> UpperTol + LowerTol
  //   SpecType_SingleUpper -> USL
  //   else                 -> 0
  if Assigned(FfFtrs_Tolerance) then
  begin
    case TSpecType.FromInteger(TagOf(FfFtrs_SpecType)) of
      SpecType_Double         : case TSpecNotation.FromInteger(TagOf(FfFtrs_Notation)) of
        SpecNotation_Spec     : FfFtrs_Tolerance.AsFloat:= FfFtrs_USL .AsFloat - FfFtrs_LSL .AsFloat        ;
        SpecNotation_Tolerance: FfFtrs_Tolerance.AsFloat:= FfFtrs_UpperTol.AsFloat + FfFtrs_LowerTol.AsFloat;
        else FfFtrs_Tolerance.AsFloat:= 0;
      end;
      SpecType_SingleUpper: FfFtrs_Tolerance.AsFloat:= FfFtrs_USL.AsFloat;
      else FfFtrs_Tolerance.AsFloat:= 0;
    end;
  end;

  // TOOLNAME - legacy looked this up via the memFtrTool (FTRTOOL -> TOOLDEF)
  // lookup memtable (Locate FTRID -> ToolName). ORM3 BP4 does not yet load an
  // FTRTOOL lookup, so there is no tool-name source on the loaded memtables;
  // leave blank until that lookup is wired (a Tier-3 data-flow item).
  if Assigned(FfFtrs_ToolName) then FfFtrs_ToolName.AsString:= '';

  // INSPISSSET - any inspection kind is configured on this characteristic.
  // CHAR(1) octet flags (First-Article/Final/SPC/In-Process/Stability/Receiving)
  // read via TagOf<>0; CBXRUNSQC and RBTMERROR are Firebird BOOLEAN (.AsBoolean);
  // SSORTME is INTEGER (=1 means Process DOE).
  if Assigned(FfFtrs_InspIsSet) then
    FfFtrs_InspIsSet.AsBoolean:=
      (TagOf(FfFtrs_CbxTFirstA) <> 0) or (TagOf(FfFtrs_CbxFinalI) <> 0) or
      (TagOf(FfFtrs_CbxPCAP) <> 0) or (TagOf(FfFtrs_CbxPCAPPROP) <> 0) or
      (TagOf(FfFtrs_CbxStab) <> 0) or (TagOf(FfFtrs_CbxSetR) <> 0) or
      (Assigned(FfFtrs_CbxRunSQC) and FfFtrs_CbxRunSQC.AsBoolean) or
      (Assigned(FfFtrs_RbtMError) and FfFtrs_RbtMError.AsBoolean) or
      (Assigned(FfFtrs_SSortME) and (FfFtrs_SSortME.AsInteger = 1));

  // DUEIN - countdown to the next scheduled In-Process event (ported from the
  // legacy CalcDuein; ORM3 computes H:MM from NEXTEVENT-Now since CalcDuein was
  // never ported). Only meaningful when the process clock is on (PROCON).
  if Assigned(FfFtrs_Duein) then
  begin
    if Assigned(FfFtrs_ProcON) and FfFtrs_ProcON.AsBoolean then
    begin
      if (Assigned(FfFtrs_TimerON) and (not FfFtrs_TimerON.AsBoolean))
         or (Assigned(FfFtrs_TabIMode) and (FfFtrs_TabIMode.AsInteger = Ord(ContrMode_ShortRun)))
         or (FfFtrs_NextEvent = nil) or FfFtrs_NextEvent.IsNull then
        FfFtrs_Duein.AsString:= '  :  '
      else
      begin
        Mins:= Round((FfFtrs_NextEvent.AsDateTime - Now) * 24 * 60);
        if Mins < 0 then FfFtrs_Duein.AsString:= 'OVERDUE'
        else FfFtrs_Duein.AsString:= Format('%d:%2.2d', [Mins div 60, Mins mod 60]);
      end;
    end
    else if TagOf(FfFtrs_CbxPCAPPROP) <> 0 then FfFtrs_Duein.AsString:= 'OFF'
    else FfFtrs_Duein.AsString:= '-';
  end;

  // STATUSONSTR - in-process status as string
  if Assigned(FfFtrs_StatusONStr) then FfFtrs_StatusONStr.AsString:= FtrsStatusOnToString(FfFtrs_StatusON.AsInteger);

  // STATUSOFFSTR - offline (ticket verdict) status mapped to its label via the
  // active TTktVerd helper (the legacy TTktVerd_Converter class is commented out
  // in MSCTYPES; TTktVerd.FromInteger(..).ToString is its live replacement).
  if Assigned(FfFtrs_StatusOFFstr) then FfFtrs_StatusOFFstr.AsString:= TTktVerd.FromInteger(FfFtrs_StatusOFF.AsInteger).ToString;

  // INSPASVARSTR - "Variable" vs "Go/No-Go" vs "Attribute"
  if Assigned(FfFtrs_InspAsVarStr) then
  begin
    if FtrType = Integer(FtrType_Variable) then
    begin
      // INSPASVAR is D_BOOLEAN (native Firebird BOOLEAN) -> TBooleanField;
      // .AsInteger raises TField.AccessError on Delphi 13. Use AsBoolean.
      if not FfFtrs_InspAsVar.AsBoolean then FfFtrs_InspAsVarStr.AsString:= 'Go / No-Go'
      else FfFtrs_InspAsVarStr.AsString:= 'Variable';
    end
    else if FtrType = Integer(FtrType_Attribute) then FfFtrs_InspAsVarStr.AsString:= 'Attribute'
    else FfFtrs_InspAsVarStr.AsString:= '';
  end;

  // ATTRIBUTE - boolean flag
  if Assigned(FfFtrs_Attribute) then FfFtrs_Attribute.AsBoolean:= (FtrType = Integer(FtrType_Attribute)) or (not FfFtrs_InspAsVar.AsBoolean);
end; // begin

{ ----- load ----- }

function TBlueprint_ViewModel.LoadOneTable(AMT: TFDMemTable; const ATableName, AWhere: string): Boolean;
var
  Payload   : TBytes            ;
  RspHdr    : TPipeMessageHeader;
  RspPayload: TBytes            ;
  GLE       : DWORD             ;
  BS        : TBytesStream      ;
  PayloadStr: string            ;
begin
  Result:= False;
  if not (Assigned(FConn) and FConn.Connected) then begin CodeSite.Send('Blueprint4.ViewModel.LoadOneTable %s: pipe not connected', [ATableName]); Exit; end;
  PayloadStr:= 'TABLE=' + ATableName + '|BLOBS=0|WHERE=' + AWhere;
  Payload:= TEncoding.UTF8.GetBytes(PayloadStr);
  GLE:= FConn.ExecuteCommand(cmdTableLoad, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData) then
  begin
    CodeSite.Send('Blueprint4.ViewModel.LoadOneTable %s failed (GLE=%d cmd=%d)', [ATableName, GLE, Ord(TCommandID(RspHdr.CommandID))]);
    Exit;
  end;
  FSuppressEvents:= True;
  AMT.DisableControls;
  // Filtered+OnFilterRecord+MasterSource active during LoadFromStream causes
  // a nil-write AV inside FireDAC internals. Clear both before loading;
  // restore in finally AFTER EnableControls (matching LoadAllForFolder order).
  // LoadFromStream also clears OnFilterRecord, so save and re-assign it.
  var OldFiltered: Boolean:= AMT.Filtered;
  var OldOnFilterRecord: TFilterRecordEvent:= AMT.OnFilterRecord;
  if OldFiltered then
  begin
    AMT.Filtered      := False;
    AMT.OnFilterRecord:= nil;
  end;
  try
    // EmptyDataSet requires an OPEN dataset. FMTOperation/FMTFtrs are
    // schema-built (BuildSchema) so they are active; FMTFolder (and other
    // lookup MemTables loaded directly from the pipe) have no pre-built
    // schema and are still closed on first load -- EmptyDataSet would raise
    // EDatabaseError 'Cannot perform this operation on a closed dataset'.
    // LoadFromStream below defines schema + data and opens it regardless.
    if AMT.Active then AMT.EmptyDataSet;
    if Length(RspPayload) > 0 then
    begin
      BS:= TBytesStream.Create(RspPayload);
      try
        AMT.LoadFromStream(BS, sfBinary);
      finally
        BS.Free;
      end;
    end;
    AMT.CachedUpdates:= True;
  finally
    AMT.EnableControls;
    if OldFiltered then
    begin
      AMT.OnFilterRecord:= OldOnFilterRecord;
      AMT.Filtered      := True;
    end;
    FSuppressEvents:= False;
  end; // try
  Result:= True;
end; // function

procedure TBlueprint_ViewModel.LoadAllForFolder;
var
  SF: string;
begin
  if not FSchemaBuilt then BuildSchema;
  SF:= Format('FLDRID=%d', [FFldrID]);

  // 2026-05-17 -- PERFORMANCE. This is the Setup/Router form: the user adds
  // Operations and Characteristics. It needs ONLY OPERAT + MSCLIST (both
  // FLDRID-scoped, small per folder) plus the single MyFolder record (loaded
  // by the form). The previous 13-table fan-out issued 13 sequential
  // synchronous cmdTableLoad pipe round-trips -- several against
  // multi-million-row tables (READINGS 8.4M, INSPRSLT 2.35M, IPCHART 2.23M)
  // via correlated IN (SELECT ...) -- costing ~60s to open even an EMPTY
  // folder, none of which this form displays. Inspection/results tables
  // (OSUBLOT/GINSP/IINSP/CPSET/MUSET/PPSET/IPCHART/READINGS/INSPRSLT/
  // PLANLIST/GONOFF) belong to the runtime inspection path and must be
  // lazy-loaded by whatever tab/feature actually needs them, not here.
  // The MemTables still exist (BuildSchema created them empty), so any
  // reference stays valid -- they are simply not populated until lazy load.
  // TODO Phase 2.x: lazy LoadOneTable(...) on first activation of the
  // inspection/SPC tabs; lookups load once at app startup + broadcast refresh.
  LoadOneTable(FMTOperation, 'OPERAT' , SF);
  // Clear filter before reload: Filtered+OnFilterRecord+MasterSource during LoadFromStream
  // causes a nil-write AV inside FireDAC. Clear here handles both first and subsequent calls.
  FMTFtrs.Filtered := False;
  LoadOneTable(FMTFtrs     , 'MSCLIST', SF);
  FMTFtrs.OnFilterRecord := FtrsOnFilterRecord;
  FMTFtrs.Filtered       := True;
  // 2026-05-19 -- Job Header: load THIS folder's single FOLDERS row into
  // FMTFolder so the 29 header DB-edits (edtF1..F5 Main Tags + Lot/Ext/MRB)
  // bind to real data. Replaces the removed legacy dmlSystem2.dsrFolder.
  // NOTE: server HandleTableLoad passes WHERE verbatim into SQL (no FLDRID
  // translation). OPERAT/MSCLIST have a real FLDRID column; FOLDERS does
  // NOT -- its PK is FLDR_SYSTID -- so SF ('FLDRID=N') would raise "column
  // unknown FLDRID" and load 0 rows (blank header). Use the real PK here.
  LoadOneTable(FMTFolder , 'FOLDERS', Format('FLDR_SYSTID=%d', [FFldrID]));
  // 2026-05-26 -- UNFILTERED MACHINES for the admin-side machine picker.
  // The station-filtered LookupCache 'MACHINES' entry exists for operator
  // forms; BP4 is a job-setup screen and the user may assign any machine
  // in the plant, not just those bound to the current station. Empty
  // WHERE = all rows.
  LoadOneTable(FMTMachines , 'MACHINES', '');
  PersistLog(Format('LoadAllForFolder FLDRID=%d: OPERAT rows=%d, MSCLIST rows=%d (imported MASTERID=-2 not distinguished here)',
    [FFldrID,
     (if FMTOperation.Active then FMTOperation.RecordCount else -1),
     (if FMTFtrs.Active then FMTFtrs.RecordCount else -1)]));
end; // procedure

function TBlueprint_ViewModel.DiagByteTagFields: string;
  function Desc(const AName: string): string           ;
  var
    F: TField;
  begin
    F:= FMTFtrs.FindField(AName);
    if F = nil then Result:= AName + '=<nil>'
    else Result:= Format('%s=%s/%s/sz%d', [AName, F.ClassName, GetEnumName(TypeInfo(TFieldType), Ord(F.DataType)), F.Size]);
  end;
begin
  if not FMTFtrs.Active then Exit('FMTFtrs not active');
  Result:= Desc('FTRTYPE') + '; ' + Desc('SPECTYPE') + '; ' + Desc('NOTATION') + '; ' + Desc('FTRCLASS') + '; ' + Desc('NUM');
end;

{ ----- IBlueprint_ViewModel ? getters (real implementations) ----- }

function TBlueprint_ViewModel.GetFLDRID    : Integer      ; begin Result:= FFldrID    ; end;
function TBlueprint_ViewModel.GetCNotation : TSpecNotation; begin Result:= FCNotation ; end;
function TBlueprint_ViewModel.GetCSpec     : TSpecType    ; begin Result:= FCSpec     ; end;
function TBlueprint_ViewModel.GetEditField : REditField   ; begin Result:= FEditField ; end;
function TBlueprint_ViewModel.GetFTRCreated: Boolean      ; begin Result:= FFTRCreated; end;
function TBlueprint_ViewModel.GetFtrsRecordCount: Integer; begin Result:= FMTFtrs.RecordCount; end     ;
function TBlueprint_ViewModel.GetLotSize            : Integer; begin Result:= FLotSize            ; end;
function TBlueprint_ViewModel.GetRequireRefresh     : Boolean; begin Result:= FRequireRefresh     ; end;
function TBlueprint_ViewModel.GetSkipOperationScroll: Boolean; begin Result:= FSkipOperationScroll; end;
function TBlueprint_ViewModel.LoadEnabled           : Boolean; begin Result:= FLoadEnabled        ; end;
function TBlueprint_ViewModel.SaveEnabled           : Boolean; begin Result:= FSaveEnabled        ; end;

function TBlueprint_ViewModel.GetpdsrFtrs     : TDataSource; begin Result:= FDsrFtrs     ; end;
function TBlueprint_ViewModel.GetpdsrOperation: TDataSource; begin Result:= FDsrOperation; end;

// Phase 2: these DataSources will come from composed lookup ViewModels
// (uCustomers, uMachineList, uOperName, DFCTLIST). Returning nil for now
// is safe at compile time; runtime grid binding will be broken until then.
function TBlueprint_ViewModel.GetpdsrAttrNames: TDataSource; begin Result:= nil; end;
function TBlueprint_ViewModel.GetpdsrCustomers: TDataSource; begin Result:= nil; end;
function TBlueprint_ViewModel.GetpdsrFolder : TDataSource; begin Result:= FDsrFolder; end    ;
function TBlueprint_ViewModel.GetpdsrFtrNames: TDataSource;
begin
  if FDsrFtrNames.DataSet = nil then FDsrFtrNames.DataSet:= LookupCache.Table('VARNAMES');
  Result:= FDsrFtrNames;
end;

function TBlueprint_ViewModel.GetpdsrMachines: TDataSource; begin Result:= FDsrMachines; end;

function TBlueprint_ViewModel.GetpdsrOperNames: TDataSource;
begin
  if FDsrOperNames.DataSet = nil then FDsrOperNames.DataSet:= LookupCache.Table('OPERNAME');
  Result:= FDsrOperNames;
end;

{ ----- IBlueprint_ViewModel ? setters (real implementations) ----- }

procedure TBlueprint_ViewModel.SetCNotation          (const Value     : TSpecNotation); begin FCNotation          := Value     ; end;
procedure TBlueprint_ViewModel.SetCSpec              (const Value     : TSpecType    ); begin FCSpec              := Value     ; end;
procedure TBlueprint_ViewModel.SetEditField          (const AEditField: REditField   ); begin FEditField          := AEditField; end;
procedure TBlueprint_ViewModel.SetFLDRID             (const Value     : Integer      ); begin FFldrID             := Value     ; end;
procedure TBlueprint_ViewModel.SetFTRCreated         (const Value     : Boolean      ); begin FFTRCreated         := Value     ; end;
procedure TBlueprint_ViewModel.SetLotSize            (const Value     : Integer      ); begin FLotSize            := Value     ; end;
procedure TBlueprint_ViewModel.SetRequireRefresh     (const Value     : Boolean      ); begin FRequireRefresh     := Value     ; end;
procedure TBlueprint_ViewModel.SetSkipOperationScroll(const Value     : Boolean      ); begin FSkipOperationScroll:= Value     ; end;
procedure TBlueprint_ViewModel.EnableLoad; begin FLoadEnabled:= True; end;
procedure TBlueprint_ViewModel.EnableSave; begin FSaveEnabled:= True; end;

{ ----- IBlueprint_ViewModel ? light reads ----- }

function TBlueprint_ViewModel.FTR: ImcMSCLIST;
begin
  // 2026-05-14 -- Always returns the persistent FFTR buffer.
  // Caller must invoke LoadFtrRecord(ID) to populate from FMTFtrs.
  Result:= FFTR;
end;

function TBlueprint_ViewModel.CharacteristicHasData(const ID: Integer): Boolean;
// 2026-05-28: real impl via cmdCharHasData. The server walks
// INSPRSLT.FTRID with ROWS 1 + HASDATA filter (FK auto-index) and
// returns a single byte: 0x00 safe to delete, 0x01 has data.
// On any pipe failure we conservatively return True (treat as has
// data) so accidental clicks don't drop chars with real history.
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
begin
  Result:= True;
  if (ID <= 0) or not (Assigned(FConn) and FConn.Connected) then Exit;
  Payload:= TEncoding.UTF8.GetBytes(Format('FTRID=%d', [ID]));
  GLE:= FConn.ExecuteCommand(cmdCharHasData, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData) then Exit;
  if Length(RspPayload) < 1 then Exit;
  Result:= RspPayload[0] <> 0;
end;

function TBlueprint_ViewModel.InspectionHasData(const IInspID: Integer): TInspHasDataInfo;
// Compound probe via cmdInspHasData. Parses the server's UTF-8
// 'HASDATA=<0|1>|SIBLINGS=<0|1>' body. Conservative on pipe failure:
// HasData:=True so accidental cascades don't drop inspection rows
// with real history.
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
  Body      : string            ;

  function ExtractFlag(const S, AKey: string): Boolean;
  var
    P   : Integer;
    EndP: Integer;
    V   : string ;
  begin
    Result:= False;
    P:= Pos(AKey + '=', S);
    if P <= 0 then Exit;
    Inc(P, Length(AKey) + 1);
    EndP:= P;
    while (EndP <= Length(S)) and (S[EndP] <> '|') do Inc(EndP);
    V:= Copy(S, P, EndP - P).Trim;
    Result:= V = '1';
  end;

begin
  Result.HasData    := True;
  Result.HasSiblings:= True;
  if (IInspID <= 0) or not (Assigned(FConn) and FConn.Connected) then Exit;
  Payload:= TEncoding.UTF8.GetBytes(Format('IINSPID=%d', [IInspID]));
  GLE:= FConn.ExecuteCommand(cmdInspHasData, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData) then Exit;
  if Length(RspPayload) = 0 then Exit;
  Body:= TEncoding.UTF8.GetString(RspPayload);
  Result.HasData    := ExtractFlag(Body, 'HASDATA' );
  Result.HasSiblings:= ExtractFlag(Body, 'SIBLINGS');
end;

function TBlueprint_ViewModel.OperationHasData(const ID: Integer): Boolean;
// Real impl via cmdOperHasData (119). The server joins INSPRSLT to MSCLIST
// on OPERID and checks HASDATA (SELECT FIRST 1, FK auto-index) -- sub-ms
// even on multi-million-row INSPRSLT. Conservative on failure: returns True
// so a pipe error blocks deletion rather than silently dropping history.
// Mirrors CharacteristicHasData exactly: same (ID<=0)/not-connected guard,
// same single-byte reply, same conservative-True fall-through.
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
begin
  Result:= True;
  if (ID <= 0) or not (Assigned(FConn) and FConn.Connected) then Exit;
  Payload:= TEncoding.UTF8.GetBytes(Format('OPERID=%d', [ID]));
  GLE:= FConn.ExecuteCommand(cmdOperHasData, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData) then Exit;
  if Length(RspPayload) < 1 then Exit;
  Result:= RspPayload[0] <> 0;
end;

function TBlueprint_ViewModel.GetOperationNames: TOperationNameRec;
// 2026-06-23 -- build the operation (id/num/name) list from the loaded OPERAT
// memtable so the BP4 Copy-Operation submenu is populated. Scans FMTOperation
// with controls disabled + bookmark restore so the current row/selection is
// preserved.
var
  FNum, FName: TField   ;
  Bm         : TBookmark;
  Idx        : Integer  ;
begin
  SetLength(Result, 0);
  if (FMTOperation = nil) or (not FMTOperation.Active) or FMTOperation.IsEmpty then Exit;
  FNum := FMTOperation.FindField('NUM' );
  FName:= FMTOperation.FindField('NAME');
  FSuppressEvents:= True;
  FMTOperation.DisableControls;
  Bm:= FMTOperation.Bookmark;
  try
    FMTOperation.First;
    while not FMTOperation.Eof do
    begin
      Idx:= Length(Result);
      SetLength(Result, Idx + 1);
      Result[Idx].ID  := FfOperation_ID.AsInteger;
      Result[Idx].Num := (if Assigned(FNum ) then FNum .AsInteger else 0 );
      Result[Idx].Name:= (if Assigned(FName) then FName.AsString  else '');
      FMTOperation.Next;
    end;
  finally
    if FMTOperation.BookmarkValid(Bm) then FMTOperation.Bookmark:= Bm;
    FMTOperation.EnableControls;
    FSuppressEvents:= False;
  end;
end;

function TBlueprint_ViewModel.FieldByName(const AName: string): REditField;
var
  I: Integer;
begin
  // Ported from Blueprint4.Model.pas.OLD -- resolve an EditFields entry by
  // control name (case-insensitive); EmptyEditField (idx=NonFtrField) if none.
  I:= low(EditFields.Data);
  while (I <= high(EditFields.Data)) and (EditFields[I].Field.ToUpper <> AName.ToUpper) do Inc(I);
  if I > high(EditFields.Data) then Result:= EmptyEditField
  else Result:= EditFields[I];
end;

function TBlueprint_ViewModel.FieldOrderdByName(const AName: string): Integer;
begin
  // Ported from OLD -- index of AName in the dynamic FieldOrder list, or
  // NonFtrField if absent / empty.
  Result:= NonFtrField;
  if AName = '' then Exit;
  Result:= low(FieldOrder.Data);
  while (Result <= high(FieldOrder.Data)) and (AName.ToUpper <> FieldOrder[Result].ToUpper) do Inc(Result);
  if Result > high(FieldOrder.Data) then Result:= NonFtrField;
end;

function TBlueprint_ViewModel.NextField: string;
var
  idx: Integer;
begin
  // Ported from OLD -- next control in the (Spec/Notation-aware) jump order,
  // wrapping to the first. Empty if no active field.
  Result:= '';
  if FActiveField.idx = NonFtrField then Exit;
  idx:= FieldOrderdByName(FActiveField.Field.ToUpper);
  if idx <> NonFtrField then begin Inc(idx); if idx > high(FieldOrder.Data) then idx:= 0; Result:= FieldOrder[idx].ToUpper; end;
end;

function TBlueprint_ViewModel.PriorField: string;
var
  idx: Integer;
begin
  // Ported from OLD -- previous control, wrapping to the last.
  Result:= '';
  if FActiveField.idx = NonFtrField then Exit;
  idx:= FieldOrderdByName(FActiveField.Field.ToUpper);
  if idx <> NonFtrField then begin dec(idx); if idx < low(FieldOrder.Data) then idx:= high(FieldOrder.Data); Result:= FieldOrder[idx].ToUpper; end;
end;

{ ----- IBlueprint_ViewModel ? write/mutate (Phase 2 stubs) ----- }

// 2026-05-14 -- AddCharacteristic now implemented; see Char CRUD section below.
// 2026-05-14 -- AddOperation / AppendCharGroups now implemented; see Operation CRUD section below.
// 2026-05-14 -- ApplyActiveField now implemented; see Char CRUD section below.
procedure TBlueprint_ViewModel.ConnectDsrFtrs; begin FDsrFtrs.Enabled:= True; FDsrFtrs.DataSet:= FMTFtrs; end;
// 2026-05-14 -- DeleteCharacteristic now implemented; see Char CRUD section below.
// 2026-05-14 -- DeleteOperation now implemented; see Operation CRUD section below.
procedure TBlueprint_ViewModel.DisconnectDsrFtrs; begin FDsrFtrs.DataSet:= nil; end;
// 2026-05-14 -- EnterField now implemented; see Char CRUD section below.
// 2026-05-14 -- FromGNGSelected/FromGNGSuffix now implemented; see GNG section below.
// Win64 stack walker -- kernel32!RtlCaptureStackBackTrace. Not in
// Winapi.Windows historically; declare it here so Blueprint4.ViewModel
// can dump the call stack on the open-form AVs without pulling in any
// extra unit.
function RtlCaptureStackBackTrace(FramesToSkip: ULONG; FramesToCapture: ULONG; BackTrace: PPointer; BackTraceHash: PULONG): USHORT; stdcall; external 'kernel32.dll';

// Diagnostic write for the 3 'open child form' call sites below.
// Captures the exception class + message + raise address + Win64 stack
// trace into C:\TEMP1\BP4_OpenForm.log when the DFM streamer (or anything
// else) throws during form construction.
procedure LogOpenFormError(const ASite: string; const E: Exception);
const
  MAX_FRAMES = 64;
var
  C_LOG  : string                              ; // 2026-07-02 host-aware path
  F      : TextFile                            ;
  Addr   : Pointer                             ;
  I      : Integer                             ;
  N      : Integer                             ;
  Frames : array [0..MAX_FRAMES - 1] of Pointer;
  Inner  : Exception                           ;
  StkInfo: string                              ;
begin
  if E = nil then Exit;
  try
    // HTRTEST -> D:\MICDATA_D\ATEST\LOG, else C:\TEMP1.
    C_LOG:= LogFilePath('BP4_OpenForm.log');
    Addr:= ExceptAddr;
    AssignFile(F, C_LOG);
    if FileExists(C_LOG) then Append(F) else Rewrite(F);
    try
      WriteLn(F, '----------------------------------------------------');
      WriteLn(F, Format('[%s] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ASite]));
      WriteLn(F, Format('  Class    : %s', [E.ClassName]));
      WriteLn(F, Format('  Message  : %s', [E.Message  ]));
      WriteLn(F, Format('  ExceptAddr: %s', [IntToHex(NativeUInt(Addr), 16)]));
      // Exception.StackTrace is populated by EurekaLog when EL is engaged.
      StkInfo:= '';
      try StkInfo:= E.StackTrace; except StkInfo:= '(StackTrace raise)'; end;
      if StkInfo <> '' then begin WriteLn(F, '  StackTrace (EurekaLog-provided):'); WriteLn(F, StkInfo ); end;
      // Walk to InnerException chain (EReadError wraps the actual AV).
      Inner:= E.InnerException;
      while Inner <> nil do
      begin
        WriteLn(F, '  --- INNER EXCEPTION ---');
        WriteLn(F, Format('  Class   : %s', [Inner.ClassName]));
        WriteLn(F, Format('  Message : %s', [Inner.Message  ]));
        Inner:= Inner.InnerException;
      end;
      // Capture raw return-address stack via RtlCaptureStackBackTrace.
      // Resolve against Win64\Debug\EXE\Micronite2027.map offline.
      N:= RtlCaptureStackBackTrace(0, MAX_FRAMES, @Frames[0], nil);
      WriteLn(F, Format('  RawStack: %d frames', [N]));
      for I:= 0 to N - 1 do WriteLn(F, Format('    #%2d  %s', [I, IntToHex(NativeUInt(Frames[I]), 16)]));
      WriteLn(F);
    finally
      CloseFile(F);
    end; // try
  except
    // never let the logger raise -- the caller is about to re-raise anyway
  end; // try
end; // procedure

procedure TBlueprint_ViewModel.ImportCAD;
var
  LForm  : TfrmBlueprintCADImport;
  LOperID: Integer               ;
begin
  // Determine current operation ID. The Phase 1 smoke test doesn't strictly
  // require a real OPERID -- the form opens regardless; Save (Phase 6) will
  // refuse with no OPERID. Use whatever is readily available; fall back to 0.
  LOperID:= 0;
  if (FMTOperation <> nil) and FMTOperation.Active and (FMTOperation.RecordCount > 0) then LOperID:= FMTOperation.FieldByName('ID').AsInteger;

  LForm:= nil;
  try
    LForm:= TfrmBlueprintCADImport.CreateForFolderOperation(nil, FConn, FFldrID, LOperID);
    try
      LForm.ShowModal;
    finally
      LForm.Free;
    end;
  except
    on E: Exception do
    begin
      // Diagnostic log to C:\TEMP1\BP4_OpenForm.log. The DFM streamer
      // wraps construction errors as 'Error reading X.Y: <inner>'.
      // EurekaLog may not engage when the streamer catches+rewraps,
      // so we capture the message + address ourselves here.
      LogOpenFormError('ImportCAD', E);
      raise;
    end;
  end; // try
end; // procedure
// 2026-05-15 -- ImportCopyOperation now implemented; see Copy Operation section below.
{ ============================================================
  ImportJenVICI -- CMM importer (backlog B), Jenoptik / VICI exports.
  Faithful port of M2022 Blueprint4.Imports.ImportJenVICI. Shape (like
  Sheffield, characteristics live in COLUMN positions of HEADER ROWS):
   * Row 0: column headers; col[0..1] are Date / Time, col[2..] are
     characteristic names. Legacy validated col[0..1] against
     Jenoptik/VICI*Date/TimeColumnHeader SetupDefaults; those defaults
     don't exist in ORM3 SetupDefaults so this port relaxes that check
     (the values aren't used by the char-import anyway -- they only
     matter for the later real-data import).
   * Row 1: nominal per column.
   * Row UTolRow / LTolRow: tolerance per column. Legacy rule:
       ADevType=0 (Jenoptik): UTolRow=2, LTolRow=3
       ADevType=1 (VICI)    : UTolRow=3, LTolRow=2
   * Min 5 lines required. All rows must have the same column count.
   * Skip the column whose name equals SerialNumberColumnHeader.
   * "Specs" mode: when col-nominal=0 but both tols nonzero, treat
     tols AS USL/LSL and recompute nominal/tols around them.
  Notes = 'Jenoptik' / 'VICI' (legacy used SetupDefaults DEVICENAME
  strings; only VICIDEVICENAME survived into ORM3 SetupDefaults).
  Stamps OPERAT FILENAME=<path>, CMMTYPE=CMMType_Jenoptik/_VICI,
  CMMMULTIPLIER. ============================================================ }
procedure TBlueprint_ViewModel.ImportJenVICI(const ADevType: Integer; const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35;
type
  TJVRow = record
    Name     : string ;
    Abbr     : string ;
    Notes    : string ;
    Num      : Integer;
    Nominal  : double ;
    UTol     : double ;
    LTol     : double ;
    Unilat   : Boolean;
    SpecsMode: Boolean;
  end;
var
  SD             : IGlobalSetupDefaults;
  Lines          : TStringList         ;
  Rows           : TArray<TJVRow>      ;
  RowCount       : Integer             ;
  Issues         : TStringList         ;
  Seen35         : TStringList         ;
  CurrOperID     : Integer             ;
  EncSuspect     : Boolean             ;
  LocalDevName   : string              ;
  SerialColHeader: string              ;
  DevNotes       : string              ;
  CmmType        : string              ;
  UTolRow        : Integer             ;
  LTolRow        : Integer             ;

  function Split(const S: string): TArray<string>;
  var
    raw: string;
  begin
    raw:= StringReplace(S, #9, ',', [rfReplaceAll]);
    Result:= raw.Split([','], '"');
    for var I: Integer:= 0 to high(Result) do Result[I]:= Result[I].DeQuotedString('"').Trim;
  end;

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

// First two whitespace-delimited words of S (legacy ExtractWord 1,2).
  function FirstTwoWords(const S: string): string;
  var
    parts: TArray<string>;
  begin
    parts:= S.Trim.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if Length(parts) >= 2 then Result:= parts[0] + ' ' + parts[1]
    else if Length(parts) = 1 then Result:= parts[0]
    else Result:= '';
  end;

begin
  if (ADevType < 0) or (ADevType > 1) then begin ImportMsg('Import Jenoptik/VICI: bad device type (expected 0=Jenoptik or 1=VICI).', 'Import Jen/VICI', 0); Exit; end;
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import Jenoptik/VICI: pipe not connected.', 'Import Jen/VICI', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then
  begin
    ImportMsg('Import Jenoptik/VICI: select a target operation first.', 'Import Jen/VICI', 0); Exit;
  end;
  if not FileExists(AFileName) then begin ImportMsg('Import Jenoptik/VICI: file not found: ' + AFileName, 'Import Jen/VICI', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;
  if ADevType = 0 then
  begin
    LocalDevName:= 'Jenoptik';
    UTolRow     := 2;
    LTolRow     := 3;
    SerialColHeader:= SD.JenoptikSerialNumberColumnHeader;
    DevNotes:= 'Jenoptik';
    CmmType := CMMType_Jenoptik;
  end
  else
  begin
    LocalDevName:= 'VICI';
    UTolRow     := 3;
    LTolRow     := 2;
    SerialColHeader:= SD.VICISerialNumberColumnHeader;
    DevNotes:= (if SD.VICIDEVICENAME <> '' then SD.VICIDEVICENAME else 'VICI');
    CmmType:= CMMType_VICI;
  end;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import ' + LocalDevName + ': cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import ' + LocalDevName, 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI ' + '-- verify special characters in names.');
    if Lines.Count < 5 then
    begin
      ImportMsg(
        Format('Import %s: file must have at least 5 lines (header + nominal + two tol rows + 1 reading). Got %d.', [LocalDevName, Lines.Count]), 'Import ' + LocalDevName, 0
      ); Exit;
    end;

    var Hdr : TArray<string>:= Split(Lines[0]);
    // legacy trimmed a trailing empty header cell
    if (Length(Hdr) > 2) and (Hdr[high(Hdr)] = '') then SetLength(Hdr, Length(Hdr) - 1);
    var ColCount: Integer:= Length(Hdr);
    if ColCount < 3 then begin ImportMsg(Format('Import %s: header has only %d columns; need at least 3.', [LocalDevName, ColCount]), 'Import ' + LocalDevName, 0); Exit; end;
    // require subsequent rows match header column count (legacy raised)
    var NomRow: TArray<string>:= Split(Lines[1      ]);
    var UTolR : TArray<string>:= Split(Lines[UTolRow]);
    var LTolR : TArray<string>:= Split(Lines[LTolRow]);
    if (Length(NomRow) < ColCount) or (Length(UTolR) < ColCount) or (Length(LTolR) < ColCount) then
    begin
      ImportMsg(
        Format('Import %s: header has %d columns but a tolerance row has fewer ' + '(nom=%d, utol=%d, ltol=%d).', [LocalDevName, ColCount, Length(NomRow), Length(UTolR),
            Length(LTolR)]), 'Import ' + LocalDevName, 0); Exit;
    end;

    SetLength(Rows, ColCount);
    RowCount:= 0;
    for var I: Integer:= 2 to ColCount - 1 do
    begin
      var Name : string:= UpperCase(Hdr[I].Trim);
      // skip the serial-number column (legacy convention)
      if (SerialColHeader <> '') and SameText(Name, SerialColHeader) then Continue;

      var ok: Boolean                               ;
      var nom : double:= ToF(NomRow[I], ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA: Nominal value in column %d non-numeric "%s" -- 0.', [I + 1, NomRow[I]]));
      var utolRaw: double:= ToF(UTolR [I], ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA: Upper-Tol value in column %d non-numeric "%s" -- 0.', [I + 1, UTolR[I]]));
      var ltolRaw: double:= ToF(LTolR [I], ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA: Lower-Tol value in column %d non-numeric "%s" -- 0.', [I + 1, LTolR[I]]));
      var UTol: double:= Abs(utolRaw);
      var LTol: double:= Abs(ltolRaw);

      var Unilat : Boolean:= (nom = 0) and (LTol = 0) and (UTol > 0)    ;
      var SpecsMode: Boolean:= (nom = 0) and (LTol <> 0) and (UTol <> 0);
      if Unilat then LTol:= UTol;

      var R: TJVRow;
      R.Name:= Name;
      var Abbr: string:= FirstTwoWords(Name);
      if Abbr = '' then Abbr:= Name;
      if Abbr.Length > 7 then Abbr:= Copy(Abbr, 1, 7);
      R.Abbr := Abbr;
      R.Notes:= DevNotes;
      R.Num:= RowCount + 1;
      if SpecsMode then
      begin
        // legacy: USL=utol, LSL=ltol, nominal = mid, expand tols around it
        var mid: double:= (UTol + LTol) / 2;
        R.Nominal:= mid;
        R.UTol:= UTol - mid;
        R.LTol:= mid  - LTol;
        R.SpecsMode:= True;
      end
      else begin R.Nominal:= nom; R.UTol:= UTol; R.LTol:= LTol; R.SpecsMode:= False; end;
      R.Unilat:= Unilat;

      if R.Name = '' then begin Issues.Add(Format('NAME_EMPTY@col %d -- characteristic skipped.', [I + 1])); Continue; end;
      if R.Name.Length > C_NAMEMAX then Issues.Add(Format('NAME_TOO_LONG@col %d: "%s" (%d>%d) -- DIMNAME stores only %d.', [I + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
      var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
      if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
          'NAME_NOT_UNIQUE_IN_%d@col %d: "%s" collides within first %d chars ' + '-- real measurement data would attach to the wrong characteristic.',
          [C_NAMEMAX, I + 1, R.Name, C_NAMEMAX]));
      Seen35.Add(key35);

      Rows[RowCount]:= R;
      Inc(RowCount);
    end; // for
    SetLength(Rows, RowCount);

    // dry-run
    var msg: string:= Format('%s dry run: %s'#13#10'%d characteristic(s) parsed, %d issue(s).', [LocalDevName, ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k: Integer:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)'#13#10, [Issues.Count - shown]);
      {$IFDEF DEBUG}CodeSite.Send('Import' + LocalDevName + ' issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import ' + LocalDevName, 0); Exit; end;
    if ImportMsg(
      msg + #13#10#13#10 + Format('Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import ' + LocalDevName + ' -- dry run', MB_YESNO or MB_ICONQUESTION
    ) <> IDYES then Exit;

    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R: Integer:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format('Import %s: failed to reserve MSCLIST.ID at row %d -- aborting (no rows sent).', [LocalDevName, R + 1]), 'Import ' + LocalDevName, 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num);
        FfFtrs_Notes .AsString:= Rows[R].Notes;
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrQClass, 0); // FTRQCLASS is TCharQClass byte-tag, like FtrMClass
        SetTag(FfFtrs_FtrType   , Ord(FtrType_Variable));
        SetTag(FfFtrs_FtrMClass , Ord(CMC_Critical    ));
        SetTag(FfFtrs_CbxPCAPPROP, 1);
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          if Rows[R].SpecsMode then SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('Import' + LocalDevName) then
    begin
      PersistLog('Import' + LocalDevName + ' ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import ' + LocalDevName + ' FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import ' + LocalDevName, MB_ICONERROR);
      Exit;
    end;

    try
      FMTOperation.Edit;
      FfOperation_FileName.AsString:= AFileName;
      FMTOperation.FieldByName('CMMTYPE'      ).AsString:= CmmType;
      FMTOperation.FieldByName('CMMMULTIPLIER').AsFloat := AMulti;
      FMTOperation.Post;
      SendDeltaOperation('Import' + LocalDevName + '(OPERAT stamp)');
    except
      on E: Exception do
        {$IFDEF DEBUG}CodeSite.Send('Import' + LocalDevName + ' OPERAT stamp: ' + E.Message){$ENDIF};
    end;

    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import %s: %d characteristic(s) imported.', [LocalDevName, RowCount]), 'Import ' + LocalDevName, MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin
{ ============================================================
  ImportLK -- CMM importer (backlog B), LK CMM text file.
  Faithful port of M2022 Blueprint4.Imports.ImportLK, restructured per the
  same client-side design as OGP/ZEISS (parser + DRY RUN client-side;
  server write via cmdNextID + cmdDelta; encoding-flexible; bulk append
  under DisableControls/FSuppressEvents). LK specifics:
   * First line must be "Start Template" (legacy validation, preserved).
   * Header row located by scanning for the four required column names:
     'actual', 'nominal', 'hi-tol', 'lo-tol' (case-insensitive). Header
     row col[0] carries the unit string (e.g. 'mm', 'in').
   * Data rows alternate between (a) a variable-definition row whose
     col[0] is "name : abbr<digits>" and (b) one or more measurement rows
     whose col[0] is the sub-feature label and col[nom/utol/ltol/actual]
     are the values. Blank lines reset the variable-definition state.
     "duration..." or "end of report" terminates parsing.
   * Lower-tol is NEGATED on input (legacy: ltol := -StrToFloat(...)),
     then abs() if still negative.
   * Stamps OPERAT FILENAME=<full path>, CMMTYPE=CMMType_LK, CMMMULTIPLIER
     after a successful import (the link the later real-data import uses
     to find this operation's LK measurement files). ============================================================ }
procedure TBlueprint_ViewModel.ImportLK(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35; // MSCLIST.DIMNAME = D_STRTAG35
type
  TLKRow = record
    Name   : string ;
    Abbr   : string ;
    Notes  : string ;
    Suffix : string ;
    Units  : string ;
    Num    : Integer;
    Nominal: double ;
    UTol   : double ;
    LTol   : double ;
    Unilat : Boolean;
  end;
var
  SD         : IGlobalSetupDefaults;
  Lines      : TStringList         ;
  Rows       : TArray<TLKRow>      ;
  RowCount   : Integer             ;
  Issues     : TStringList         ;
  Seen35     : TStringList         ;
  CurrOperID : Integer             ;
  EncSuspect : Boolean             ;
  actcol     : Integer             ;
  nomcol     : Integer             ;
  utolcol    : Integer             ;
  ltolcol    : Integer             ;
  XUnits     : string              ;
  HeaderFound: Boolean             ;
  hdi        : Integer             ;

  // Normalize a row: legacy PrepareTabsCommas folded tabs into commas;
  // CSV split with " quoting matches OGP's idiom. Trim every cell.
  function Split(const S: string): TArray<string>;
  var
    raw: string;
  begin
    raw:= StringReplace(S, #9, ',', [rfReplaceAll]);
    Result:= raw.Split([','], '"');
    for var I: Integer:= 0 to high(Result) do Result[I]:= Result[I].Trim;
  end;

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

  function HdrIdx(const A: TArray<string>; const Name: string): Integer;
  begin
    for var I: Integer:= 0 to high(A) do
      if SameText(A[I], Name) then Exit(I);
    Result:= -1;
  end;

// 10^n without pulling Math into uses (one-line defensive bump value).
  function Pow10(N: Integer): double;
  begin
    Result:= 1.0;
    if N > 0 then for var I     : Integer:= 1 to N do Result:= Result * 10.0
    else if N < 0 then for var I: Integer:= 1 to -N do Result:= Result / 10.0;
  end;

begin
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import LK: pipe not connected.', 'Import LK', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then begin ImportMsg('Import LK: select a target operation first.', 'Import LK', 0); Exit; end;
  if not FileExists(AFileName) then begin ImportMsg('Import LK: file not found: ' + AFileName, 'Import LK', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import LK: cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import LK', 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI ' + '-- verify special characters in names.');
    for var I: Integer:= 0 to Lines.Count - 1 do Lines[I]:= Lines[I].Trim;
    if Lines.Count < 3 then begin ImportMsg('Import LK: file has too few lines (need at least Start Template + header + data).', 'Import LK', 0); Exit; end;

    // line 1 must be "Start Template"
    var c0: TArray<string>:= Split(Lines[0]);
    if (Length(c0) = 0) or not SameText(c0[0], 'Start Template') then
    begin
      ImportMsg(Format('Import LK: first line is not "Start Template" (got "%s").', [Lines[0]]), 'Import LK', 0);
      Exit;
    end;

    // locate header (the row that has actual/nominal/hi-tol/lo-tol)
    actcol:= -1; nomcol:= -1; utolcol:= -1; ltolcol:= -1;
    XUnits     := '';
    HeaderFound:= False;
    hdi        := 2;
    while (not HeaderFound) and (hdi < Lines.Count) do
    begin
      var Hdr: TArray<string>:= Split(Lines[hdi]);
      if Length(Hdr) > 0 then
      begin
        actcol := HdrIdx(Hdr, 'actual' );
        nomcol := HdrIdx(Hdr, 'nominal');
        utolcol:= HdrIdx(Hdr, 'hi-tol' );
        ltolcol:= HdrIdx(Hdr, 'lo-tol' );
        if (actcol >= 0) and (nomcol >= 0) and (utolcol >= 0) and (ltolcol >= 0) then begin XUnits:= Hdr[0]; HeaderFound:= True; break; end;
      end;
      Inc(hdi);
    end;
    if not HeaderFound then begin ImportMsg('Import LK: header row with actual/nominal/hi-tol/lo-tol not found.', 'Import LK', 0); Exit; end;

    // walk data rows: PState=True => expect a variable-definition row next;
    // PState=False => measurement row(s) under the current variable.
    var PState : Boolean:= True;
    var vname : string:= '';
    var vabbr : string:= '';
    var SNum  : string:= '';
    SetLength(Rows, Lines.Count);
    RowCount:= 0;
    for var I: Integer:= hdi + 1 to Lines.Count - 1 do
    begin
      var Cols: TArray<string>:= Split(Lines[I]);
      if Length(Cols) = 0 then begin PState:= True; vname:= ''; vabbr:= ''; SNum:= ''; Continue; end;
      if SameText(Copy(Cols[0], 1, 8), 'duration') then break;
      if SameText(Cols[0], 'end of report') then break;

      if PState then
      begin
        var S: string:= Cols[0]  ;
        var j: Integer:= S.Length;
        // split on ':' for "name : abbr"
        while (j > 0) and (S[j] <> ':') do dec(j);
        if j > 0 then begin vname:= Copy(S, 1, j - 1).Trim; vabbr:= Copy(S, j + 1, 10).Trim; end
        else begin vname:= S.Trim; vabbr:= ''; end;
        // trailing digits -> SNum
        j:= S.Length;
        while (j > 0) and CharInSet(S[j], ['0'..'9']) do dec(j);
        SNum:= Copy(S, j + 1, S.Length - j).Trim;
        PState:= False;
        Continue;
      end; // if

      // measurement row -- bounds-check column indices (legacy raised; we report)
      var maxNeeded: Integer:= actcol;
      if nomcol  > maxNeeded then maxNeeded:= nomcol;
      if utolcol > maxNeeded then maxNeeded:= utolcol;
      if ltolcol > maxNeeded then maxNeeded:= ltolcol;
      if Length(Cols) - 1 < maxNeeded then
      begin
        Issues.Add(Format('CSV_COLUMN_MISMATCH@line %d: %d columns; need at least %d -- row skipped.', [I + 1, Length(Cols), maxNeeded + 1]));
        Continue;
      end;

      var ok: Boolean                        ;
      var cN: string:= Cols[nomcol ];
      var cU: string:= Cols[utolcol];
      var cL: string:= Cols[ltolcol];
      var cA: string:= Cols[actcol ];
      var nom : double:= ToF(cN, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Nominal column has non-numeric "%s" -- taken as 0.', [I + 1, cN]));
      var UTol : double:= ToF(cU, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Upper-Tol column has non-numeric "%s" -- taken as 0.', [I + 1, cU]));
      var ltolRaw: double:= ToF(cL, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Lower-Tol column has non-numeric "%s" -- taken as 0.', [I + 1, cL]));
      var actual : double:= ToF(cA, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Actual column has non-numeric "%s" -- taken as 0.', [I + 1, cA]));
      var LTol: double:= -ltolRaw; // legacy negated sign

      var Unilat: Boolean:= (nom = 0) and (LTol = 0) and (UTol > 0);
      if Unilat then LTol:= UTol;
      if (UTol = 0) and (LTol = 0) then
      begin
        if nom = 0 then begin UTol:= Abs(actual * 5); LTol:= UTol; Unilat:= False; end
        else begin UTol:= nom * 4 ; LTol:= UTol; Unilat:= False; end;
      end;
      if LTol < 0 then LTol:= Abs(LTol);
      if (UTol + LTol < 1E-12) and (UTol + LTol > -1E-12) then begin var bump: double:= Pow10(ADecimals); UTol:= UTol + bump; LTol:= LTol + bump; end;

      var R: TLKRow;
      R.Name:= (vname + ' ' + Cols[0]).Trim;
      R.Abbr   := vabbr;
      R.Suffix := SNum;
      R.Notes  := 'LK';
      R.Units  := XUnits;
      R.Num    := I; // legacy used line index
      R.Nominal:= nom;
      R.UTol   := UTol;
      R.LTol   := LTol;
      R.Unilat := Unilat;

      if R.Name = '' then begin Issues.Add(Format('NAME_EMPTY@line %d -- characteristic skipped.', [I + 1])); Continue; end;
      if R.Name.Length > C_NAMEMAX then Issues.Add(Format('NAME_TOO_LONG@line %d: "%s" (%d>%d) -- DIMNAME stores only %d.', [I + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
      var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
      if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
          'NAME_NOT_UNIQUE_IN_%d@line %d: "%s" collides within first %d chars ' + '-- real measurement data would attach to the wrong characteristic.',
          [C_NAMEMAX, I + 1, R.Name, C_NAMEMAX]));
      Seen35.Add(key35);

      Rows[RowCount]:= R;
      Inc(RowCount);
    end; // for
    SetLength(Rows, RowCount);

    // dry-run report
    var msg: string:= Format('LK dry run: %s'#13#10'%d characteristic(s) parsed, %d issue(s).', [ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k: Integer:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)'#13#10, [Issues.Count - shown]);
      {$IFDEF DEBUG}CodeSite.Send('ImportLK issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import LK', 0); Exit; end;
    if ImportMsg(msg + #13#10#13#10 + Format('Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import LK -- dry run', MB_YESNO
      or MB_ICONQUESTION) <> IDYES then Exit;

    // commit: bulk append under DisableControls, one delta
    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R: Integer:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format('Import LK: failed to reserve MSCLIST.ID at row %d -- aborting (no rows sent).', [R + 1]), 'Import LK', 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num);
        FfFtrs_Notes    .AsString:= Rows[R].Notes;
        FfFtrs_FtrSuffix.AsString:= Rows[R].Suffix;
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else if Rows[R].Units <> '' then Rows[R].Units else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrQClass, 0); // FTRQCLASS is TCharQClass byte-tag, like FtrMClass
        SetTag(FfFtrs_FtrType  , Ord(FtrType_Variable));
        SetTag(FfFtrs_FtrMClass, Ord(CMC_Critical    ));
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          if SD.DefaultNotation + 1 = Ord(SpecNotation_Tolerance) then SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('ImportLK') then
    begin
      // Char delta rejected -- do NOT stamp OPERAT or claim success. Reload the
      // true (unchanged) server state and surface the real error to the user.
      PersistLog('ImportLK ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import LK FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import LK', MB_ICONERROR);
      Exit;
    end;

    // Stamp OPERAT so the later real-data import can find this operation's
    // LK measurement files (legacy filed the FULL file path here, not a job).
    try
      FMTOperation.Edit;
      FfOperation_FileName.AsString:= AFileName;
      FMTOperation.FieldByName('CMMTYPE'      ).AsString:= CMMType_LK;
      FMTOperation.FieldByName('CMMMULTIPLIER').AsFloat := AMulti;
      FMTOperation.Post;
      SendDeltaOperation('ImportLK(OPERAT stamp)');
    except
      on E: Exception do
        {$IFDEF DEBUG}CodeSite.Send('ImportLK OPERAT stamp: ' + E.Message){$ENDIF};
    end;

    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import LK: %d characteristic(s) imported.', [RowCount]), 'Import LK', MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin
{ ============================================================
  ImportNikon -- CMM importer (backlog B), Nikon CSV. Faithful port of
  M2022 Blueprint4.Imports.ImportNikon. Simpler than LK (no var-def
  grouping, no unilat fallback): line 0 is the CSV header; data rows
  follow. Columns:
   * Name / Abbr / NUM via SetupDefaults indices (NIKON*Column).
   * Nominal / UpperTol / LowerTol via header NAMES (NikonNominalColumnHeader
     / NikonUpperTolColumnHeader / NikonLowerTolColumnHeader -- all
     configurable in SetupDefaults so different Nikon exports work).
   * Header columns AFTER the spec triplet must be sequential integers
     1, 2, 3, ... -- legacy raised on mismatch; dry-run now reports as
     CSV_MEASUREMENT_COLS_INVALID (faithful, non-blocking).
  Lower-tol is NEGATED on input (legacy convention, same as LK).
  Stamps OPERAT FILENAME=<full path>, CMMTYPE=CMMType_NIKON, CMMMULTIPLIER. ============================================================ }
procedure TBlueprint_ViewModel.ImportNikon(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35;
type
  TNkRow = record
    Name   : string ;
    Abbr   : string ;
    Notes  : string ;
    Num    : Integer;
    Nominal: double ;
    UTol   : double ;
    LTol   : double ;
    Unilat : Boolean;
  end;
var
  SD        : IGlobalSetupDefaults;
  Lines     : TStringList         ;
  Rows      : TArray<TNkRow>      ;
  RowCount  : Integer             ;
  Issues    : TStringList         ;
  Seen35    : TStringList         ;
  CurrOperID: Integer             ;
  EncSuspect: Boolean             ;
  nomcol    : Integer             ;
  utolcol   : Integer             ;
  ltolcol   : Integer             ;
  namecol1  : Integer             ; // 1-based (SetupDefaults convention)
  abbrcol1  : Integer             ;
  numcol1   : Integer             ;

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

  function Cell(const A: TArray<string>; ACol1: Integer): string;
  begin
    if (ACol1 >= 1) and (ACol1 <= Length(A)) then Result:= A[ACol1 - 1].Trim
    else Result:= '';
  end;

  function ExtractLeadingInt(const S: string): Integer;
  var
    I: Integer; t: string;
  begin
    t:= S.Trim; I:= 1;
    while (I <= t.Length) and CharInSet(t[I], ['0'..'9']) do Inc(I);
    if I > 1 then Result:= StrToIntDef(Copy(t, 1, I - 1), 0) else Result:= 0;
  end;

begin
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import Nikon: pipe not connected.', 'Import Nikon', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then begin ImportMsg('Import Nikon: select a target operation first.', 'Import Nikon', 0); Exit; end;
  if not FileExists(AFileName) then begin ImportMsg('Import Nikon: file not found: ' + AFileName, 'Import Nikon', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;
  namecol1:= SD.NIKONNameColumn;
  abbrcol1:= SD.NIKONAbbreviationColumn;
  numcol1 := SD.NIKONNUMColumn;
  if namecol1 < 1 then begin ImportMsg('Import Nikon: NIKON Name Column is not configured in SetupDefaults.', 'Import Nikon', 0); Exit; end;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import Nikon: cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import Nikon', 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI ' + '-- verify special characters in names.');
    if Lines.Count < 2 then begin ImportMsg('Import Nikon: file has no data row.', 'Import Nikon', 0); Exit; end;

    // header (CSV) -> locate the spec triplet by configurable column NAMES
    var Hdr: TArray<string>:= Lines[0].Split([','], '"')                           ;
    for var I: Integer:= 0 to high(Hdr) do Hdr[I]:= Hdr[I].DeQuotedString('"').Trim;
    nomcol:= -1; utolcol:= -1; ltolcol:= -1;
    for var I: Integer:= 0 to high(Hdr) do
    begin
      if SameText(Hdr[I], SD.NikonNominalColumnHeader ) then nomcol := I;
      if SameText(Hdr[I], SD.NikonUpperTolColumnHeader) then utolcol:= I;
      if SameText(Hdr[I], SD.NikonLowerTolColumnHeader) then ltolcol:= I;
    end;
    var miss: string:= '';
    if nomcol  < 0 then miss:= miss + SD.NikonNominalColumnHeader  + ' ';
    if utolcol < 0 then miss:= miss + SD.NikonUpperTolColumnHeader + ' ';
    if ltolcol < 0 then miss:= miss + SD.NikonLowerTolColumnHeader + ' ';
    if miss <> '' then begin ImportMsg('Import Nikon: required column(s) missing in header: ' + miss.Trim, 'Import Nikon', 0); Exit; end;
    // After the spec triplet the legacy enforced sequential 1,2,3,... markers.
    // Faithful but non-blocking: report mismatches as an issue.
    var actCol1: Integer:= nomcol; if utolcol > actCol1 then actCol1:= utolcol;
    if ltolcol > actCol1 then actCol1:= ltolcol; Inc(actCol1);
    for var I: Integer:= actCol1 to high(Hdr) do
    begin
      var expect: Integer:= I - actCol1 + 1      ;
      var got : Integer:= StrToIntDef(Hdr[I], -1);
      if got <> expect then Issues.Add(Format('CSV_MEASUREMENT_COLS_INVALID: header col %d should be "%d", got "%s".', [I + 1, expect, Hdr[I]]));
    end;

    SetLength(Rows, Lines.Count);
    RowCount:= 0;
    for var li: Integer:= 1 to Lines.Count - 1 do
    begin
      var raw: string:= Lines[li].Trim;
      if raw = '' then Continue;
      var Cols: TArray<string>:= raw.Split([','], '"')                                  ;
      for var j: Integer:= 0 to high(Cols) do Cols[j]:= Cols[j].DeQuotedString('"').Trim;
      var maxNeeded: Integer:= nomcol                                                   ;
      if utolcol > maxNeeded then maxNeeded:= utolcol;
      if ltolcol > maxNeeded then maxNeeded:= ltolcol;
      if Length(Cols) - 1 < maxNeeded then
      begin
        Issues.Add(Format('CSV_COLUMN_MISMATCH@row %d: %d columns; need at least %d -- row skipped.', [li + 1, Length(Cols), maxNeeded + 1]));
        Continue;
      end;

      var ok: Boolean                        ;
      var cN: string:= Cols[nomcol ];
      var cU: string:= Cols[utolcol];
      var cL: string:= Cols[ltolcol];
      var nom : double:= ToF(cN, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@row %d: Nominal column non-numeric "%s" -- 0.', [li + 1, cN]));
      var UTol : double:= ToF(cU, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@row %d: Upper-Tol column non-numeric "%s" -- 0.', [li + 1, cU]));
      var ltolRaw: double:= ToF(cL, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@row %d: Lower-Tol column non-numeric "%s" -- 0.', [li + 1, cL]));
      var LTol: double:= -ltolRaw;
      if LTol < 0 then LTol:= Abs(LTol);

      var Unilat: Boolean:= (nom = 0) and (LTol = 0) and (UTol > 0);
      if Unilat then LTol:= UTol;

      var R: TNkRow;
      R.Name:= Cell(Cols, namecol1);
      R.Abbr:= Cell(Cols, abbrcol1);
      if R.Name = '' then begin Issues.Add(Format('NAME_EMPTY@row %d -- characteristic skipped.', [li + 1])); Continue; end;
      // NUM: 0 in SetupDefaults => sequential; positive 1-based col => extract digits
      if numcol1 = 0 then R.Num:= SD.StartingCharacteristicNumber + RowCount
      else if numcol1 >= 1 then R.Num:= ExtractLeadingInt(Cell(Cols, numcol1))
      else R.Num:= 0;
      if R.Num <= 0 then R.Num:= SD.StartingCharacteristicNumber + RowCount;

      R.Notes:= 'NIKON';
      R.Nominal:= nom; R.UTol:= UTol; R.LTol:= LTol;
      R.Unilat:= Unilat;

      if R.Name.Length > C_NAMEMAX then Issues.Add(Format('NAME_TOO_LONG@row %d: "%s" (%d>%d) -- DIMNAME stores only %d.', [li + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
      var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
      if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
          'NAME_NOT_UNIQUE_IN_%d@row %d: "%s" collides within first %d chars ' + '-- real measurement data would attach to the wrong characteristic.',
          [C_NAMEMAX, li + 1, R.Name, C_NAMEMAX]));
      Seen35.Add(key35);

      Rows[RowCount]:= R;
      Inc(RowCount);
    end; // for
    SetLength(Rows, RowCount);

    // dry-run report
    var msg: string:= Format('Nikon dry run: %s'#13#10'%d characteristic(s) parsed, %d issue(s).', [ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k: Integer:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)'#13#10, [Issues.Count - shown]);
      {$IFDEF DEBUG}CodeSite.Send('ImportNikon issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import Nikon', 0); Exit; end;
    if ImportMsg(msg + #13#10#13#10 + Format('Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import Nikon -- dry run', MB_YESNO
      or MB_ICONQUESTION) <> IDYES then Exit;

    // commit
    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R: Integer:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format('Import Nikon: failed to reserve MSCLIST.ID at row %d -- aborting (no rows sent).', [R + 1]), 'Import Nikon', 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num);
        FfFtrs_Notes .AsString:= Rows[R].Notes;
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrQClass, 0); // FTRQCLASS is TCharQClass byte-tag, like FtrMClass
        SetTag(FfFtrs_FtrType   , Ord(FtrType_Variable));
        SetTag(FfFtrs_FtrMClass , Ord(CMC_Critical    ));
        SetTag(FfFtrs_CbxPCAPPROP, 1); // legacy sets PCAPPROP on
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          if SD.DefaultNotation + 1 = Ord(SpecNotation_Tolerance) then SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('ImportNikon') then
    begin
      PersistLog('ImportNikon ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import Nikon FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import Nikon', MB_ICONERROR);
      Exit;
    end;

    try
      FMTOperation.Edit;
      FfOperation_FileName.AsString:= AFileName;
      FMTOperation.FieldByName('CMMTYPE'      ).AsString:= CMMType_NIKON;
      FMTOperation.FieldByName('CMMMULTIPLIER').AsFloat := AMulti;
      FMTOperation.Post;
      SendDeltaOperation('ImportNikon(OPERAT stamp)');
    except
      on E: Exception do
        {$IFDEF DEBUG}CodeSite.Send('ImportNikon OPERAT stamp: ' + E.Message){$ENDIF};
    end;

    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import Nikon: %d characteristic(s) imported.', [RowCount]), 'Import Nikon', MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin

// Shared CMM-importer encoding sniff (ImportOGP/ImportZEISS/...): UTF-8
// BOM, else valid BOM-less UTF-8, else ANSI (ASuspect when 8-bit
// non-UTF-8). Legacy Paradox was ANSI-only; ORM3 is Unicode.
function TBlueprint_ViewModel.DetectFileEncoding(const AFile: string; out ASuspect: Boolean): TEncoding;
var
  FS : TFileStream                                        ;
  Buf: TBytes                                             ;
  N  : Integer                                            ;
  I  : Integer                                            ;
  hi : Boolean                                            ;
  function ValidUTF8(const B: TBytes; L: Integer): Boolean;
  var
    P    : Integer;
    extra: Integer;
  begin
    P:= 0;
    while P < L do
    begin
      if B[P] < $80 then begin Inc(P); Continue; end;
      if (B[P] and $E0)      = $C0 then extra:= 1
      else if (B[P] and $F0) = $E0 then extra:= 2
      else if (B[P] and $F8) = $F0 then extra:= 3
      else Exit(False);
      if P + extra >= L then Exit(True); // truncated tail in sniff window
      for var k:= 1 to extra do if (B[P + k] and $C0) <> $80 then Exit(False);
      Inc(P, extra + 1);
    end;
    Result:= True;
  end; // function
begin
  ASuspect:= False;
  FS:= TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  try
    N:= FS.Size; if N > 65536 then N:= 65536;
    SetLength(Buf, N);
    if N > 0 then FS.ReadBuffer(Buf[0], N);
  finally
    FS.Free;
  end;
  if (N >= 3) and (Buf[0] = $EF) and (Buf[1] = $BB) and (Buf[2] = $BF) then Exit(TEncoding.UTF8);
  hi:= False;
  for I:= 0 to N - 1 do if Buf[I] >= $80 then begin hi:= True; break; end;
  if not hi then Exit(TEncoding.ASCII);
  if ValidUTF8(Buf, N) then Exit(TEncoding.UTF8);
  ASuspect:= True; // 8-bit content, not UTF-8 -> ANSI, flagged
  Result:= TEncoding.ANSI;
end; // begin

{ ----- CMM-import headless seam ------------------------------------------
  ImportMsg replaces Application.MessageBox in every Import*. In UI mode it
  is Application.MessageBox verbatim. In headless mode (--autotest sets
  ImportHeadless) it records the text to FImportReport, logs it, and returns
  IDYES for a dry-run YESNO gate / IDOK otherwise -- so the importer runs to
  completion against the real pipe/SERVER without ever blocking. The
  documented hard rule (never MessageBox in a ViewModel save path under
  --autotest) is satisfied for the whole import family by this one router. }
function TBlueprint_ViewModel.ImportMsg(const AText, ACaption: string; AFlags: UINT): Integer;
begin
  if FImportHeadless then
  begin
    FImportReport.Add('[' + ACaption + '] ' + StringReplace(AText, #13#10, ' | ', [rfReplaceAll]));
    {$IFDEF DEBUG}CodeSite.Send('ImportMsg(headless): ' + ACaption, AText);{$ENDIF}
    if (AFlags and $0000000F) = MB_YESNO then Result:= IDYES else Result:= IDOK;
    Exit;
  end;
  Result:= Application.MessageBox(PChar(AText), PChar(ACaption), AFlags);
end;

procedure TBlueprint_ViewModel.SetImportHeadless(const V: Boolean);
begin
  FImportHeadless:= V;
  // Clear the report only when ENTERING headless mode -- otherwise the
  // post-import SetImportHeadless(False) (in the autotest scaffold) would
  // wipe the report before the test reads it.
  if V then FImportReport.Clear;
end;

function TBlueprint_ViewModel.GetImportHeadless: Boolean;
begin
  Result:= FImportHeadless;
end;

function TBlueprint_ViewModel.GetLastImportReport: string;
begin
  Result:= FImportReport.Text;
end;

function TBlueprint_ViewModel.GetLastPersistError: string;
begin
  Result:= FLastPersistError;
end;

procedure TBlueprint_ViewModel.ClearLastPersistError;
begin
  FLastPersistError:= '';
end;

{ ============================================================
  ImportOGP -- CMM importer (backlog B), OGP CSV. Faithful port of
  M2022 Blueprint4.Imports.ImportOGP, restructured per the agreed
  design (project_imports_cmm / MICRONITE_CONCEPTS.MD):
   * parser + DRY RUN run CLIENT-side; the server write reuses the
     existing cmdNextID + cmdDelta path (no new server command);
   * encoding-flexible         : UTF-8 (BOM or BOM-less) and upper-ASCII/ANSI;
   * NEW validations vs Paradox: CSV column-count mismatch,
     DIMNAME>35 / not-unique-within-first-35 (DIMNAME is D_STRTAG35 and
     is the real-data CMM match key -> a within-35 collision attaches
     measurements to the WRONG characteristic), encoding-suspect;
   * bulk append under DisableControls/FSuppressEvents (long files must
     not repaint the grid per row), then one SendDeltaFtrs.
  Column mapping + defaults come from station SetupDefaults
  (SetupDefaultsRec, loaded from MyStation.SETTINGS at bootstrap).
  ============================================================ }
procedure TBlueprint_ViewModel.ImportOGP(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35; // MSCLIST.DIMNAME = D_STRTAG35 (real-data match key)
type
  TOGPRow = record
    Name   : string ;
    Abbr   : string ;
    Notes  : string ;
    Suffix : string ;
    Num    : Integer;
    Nominal: double ;
    UTol   : double ;
    LTol   : double ;
    Unilat : Boolean;
  end;
var
  SD        : IGlobalSetupDefaults;
  Lines     : TStringList         ;
  Rows      : TArray<TOGPRow>     ;
  RowCount  : Integer             ;
  Issues    : TStringList         ;
  Seen35    : TStringList         ; // first-35 uppercased -> dup detection
  CurrOperID: Integer             ;
  EncSuspect: Boolean             ;
  idcol     : Integer             ;
  abbrcol   : Integer             ;
  numcol    : Integer             ;
  nomcol    : Integer             ;
  utolcol   : Integer             ;
  ltolcol   : Integer             ;
  sufcol    : Integer             ;
  devcol    : Integer             ;
  rdgcol    : Integer             ;
  datecol   : Integer             ;
  timecol   : Integer             ;
  maxcol    : Integer             ;

  function Cell(const A: TArray<string>; ACol1: Integer): string;
  begin // ACol1 is 1-based (SetupDefaults convention); 0/oob -> ''
    if (ACol1 >= 1) and (ACol1 <= Length(A)) then Result:= A[ACol1 - 1].Trim
    else Result:= '';
  end;

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

begin
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import OGP: pipe not connected.', 'Import OGP', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then begin ImportMsg('Import OGP: select a target operation first.', 'Import OGP', 0); Exit; end;
  if not FileExists(AFileName) then begin ImportMsg('Import OGP: file not found: ' + AFileName, 'Import OGP', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;

  idcol  := SD.OGPSNameColumn    ; abbrcol:= SD.OGPSAbbreviationColumn;
  numcol := SD.OGPSNUMColumn     ; nomcol := SD.OGPSNominalColumn;
  utolcol:= SD.OGPSUpperTolColumn; ltolcol:= SD.OGPSLowerTolColumn;
  sufcol := SD.OGPSSuffixColumn  ; devcol := SD.OGPSDeviceColumn;
  rdgcol:= SD.OGPSReadingColumn; // validate-only (not stored by char import)
  // 0 = absent. Date/Time become the reading timestamp in the Data Entry /
  // actual file-data import (NOT Blueprint char import) -- here the dry
  // run only VALIDATES they parse as date/time (FlexDateTime).
  datecol:= SD.OGPSDateColumn;
  timecol:= SD.OGPSTimeColumn;
  maxcol:= idcol;
  for var V in [abbrcol, numcol, nomcol, utolcol, ltolcol, sufcol, devcol] do if V > maxcol then maxcol:= V;
  if idcol < 1 then begin ImportMsg('Import OGP: OGPS Name Column is not configured in SetupDefaults.', 'Import OGP', 0); Exit; end;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import OGP: cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import OGP', 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI -- ' + 'verify special characters in names.');
    if SD.OGPSIgnoreHeader and (Lines.Count > 0) then Lines.Delete(0);

    RowCount:= 0;
    SetLength(Rows, Lines.Count);
    for var li:= 0 to Lines.Count - 1 do
    begin
      var raw: string:= Lines[li].Trim;
      if raw.Length < 5 then Continue;
      var Cols: TArray<string>:= raw.Split([','], '"');
      for var j:= 0 to high(Cols) do Cols[j]:= Cols[j].Trim;
      if (Length(Cols) > 0) and (SD.OGPDMIS_TRACE.Trim <> '') and (Cols[0].ToUpper = SD.OGPDMIS_TRACE.Trim.ToUpper) then Continue;
      var dcc: Integer:= 0;
      for var j:= 0 to high(Cols) do if not Cols[j].IsEmpty then Inc(dcc);
      if (dcc < maxcol) and (dcc > 3) then
      begin
        Issues.Add(Format('CSV_COLUMN_MISMATCH@row %d: %d columns, %d required -- row skipped.', [li + 1, Length(Cols), maxcol]));
        Continue;
      end;
      if dcc <= 3 then Continue;

      var R : TOGPRow;
      var ok: Boolean;
      R.Name:= Cell(Cols, idcol  );
      R.Abbr:= Cell(Cols, abbrcol);
      R.Notes:= Cell(Cols, devcol); if R.Notes = '' then R.Notes:= SD.OGPSDEVICENAME;
      R.Suffix:= Cell(Cols, sufcol);
      // A numeric column carrying alpha is the classic column-mix-up
      // symptom (OGP/CSV) -- report each offending column by ROLE + value
      // so the operator can see the mapping is wrong (NOT in Paradox).
      var cN: string:= Cell(Cols, nomcol );
      var cU: string:= Cell(Cols, utolcol);
      var cL: string:= Cell(Cols, ltolcol);
      R.Nominal:= ToF(cN, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Nominal ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cN]));
      R.UTol:= ToF(cU, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Upper-Tol ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cU]));
      R.LTol:= Abs(ToF(cL, ok)) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Lower-Tol ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cL]));
      // Actual-Reading column is not stored by characteristic import, but
      // alpha there is still a strong column-mix-up signal -> validate-only.
      if rdgcol >= 1 then
      begin
        var cR: string:= Cell(Cols, rdgcol);
        if cR <> '' then
        begin
          ToF(cR, ok);
          if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: ' + 'Actual-Reading column has non-numeric "%s" -- likely a column ' + 'mix-up.', [li + 1, cR]));
        end;
      end;
      // Date/Time columns are NOT stored by Blueprint char import (they
      // become the reading timestamp in the Data Entry / file-data
      // import). Here, validate-only: if configured and the cell is
      // non-empty it must parse via FlexDateTime, else it is a column
      // mix-up (FlexDateTime.ReadDate/ReadTime return 0 on failure).
      if datecol >= 1 then
      begin
        var cD: string:= Cell(Cols, datecol);
        if (cD <> '') and (FlexDateTime.ReadDate(cD) <= 0) then
          Issues.Add(Format('DATE_COL_INVALID@line %d: Date column value "%s" ' + 'is not a recognizable date -- likely a column mix-up.', [li + 1, cD]));
      end;
      if timecol >= 1 then
      begin
        var cT: string:= Cell(Cols, timecol);
        if cT <> '' then
        begin
          var tbad: Boolean:= FlexDateTime.ReadTime(cT) <= 0;
          if tbad then
          begin
            // ReadTime returns 0 both on failure AND for a legit midnight
            // (00:00:00) -- don't false-flag an all-zero time reading.
            var z: string:= cT.Replace(':', '').Replace(' ', '').Replace('AM', '', [rfReplaceAll, rfIgnoreCase]).Replace('PM', '', [rfReplaceAll, rfIgnoreCase]);
            tbad:= not ((z = '') or (StrToIntDef(z, -1) = 0));
          end;
          if tbad then Issues.Add(Format('TIME_COL_INVALID@line %d: Time column value "%s" ' + 'is not a recognizable time -- likely a column mix-up.', [li + 1, cT]));
        end;
      end; // if
      R.Unilat:= (R.Nominal = 0) and (R.LTol = 0) and (R.UTol > 0);
      if R.Unilat then R.LTol:= R.UTol;
      var ns: string:= Cell(Cols, numcol);
      if (numcol >= 1) and (ns <> '') and not TryStrToInt(ns, R.Num) then R.Num:= 0;
      if R.Num <= 0 then R.Num:= SD.StartingCharacteristicNumber + RowCount;

      if R.Name = '' then Issues.Add(Format('NAME_EMPTY@line %d -- characteristic skipped.', [li + 1]))
      else
      begin
        if R.Name.Length > C_NAMEMAX then
          Issues.Add(Format('NAME_TOO_LONG@line %d: "%s" (%d>%d) -- DIMNAME stores only %d.', [li + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
        var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
        if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
            'NAME_NOT_UNIQUE_IN_%d@line %d: "%s" collides within first %d chars ' + '-- real measurement data would attach to the wrong characteristic.',
            [C_NAMEMAX, li + 1, R.Name, C_NAMEMAX]));
        Seen35.Add(key35);
        Rows[RowCount]:= R;
        Inc(RowCount);
      end;
    end; // for
    SetLength(Rows, RowCount);

    // ---- dry-run report; user decides --------------------------------
    var msg: string:= Format('OGP dry run: %s'#13#10 + '%d characteristic(s) parsed, %d issue(s).', [ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)', [Issues.Count - shown]) + #13#10;
      {$IFDEF DEBUG}CodeSite.Send('ImportOGP issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import OGP', 0); Exit; end;
    if ImportMsg(msg + #13#10#13#10 + Format( 'Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import OGP -- dry run', MB_YESNO
      or MB_ICONQUESTION) <> IDYES then Exit;

    // ---- commit: bulk append under DisableControls, one delta --------
    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format( 'Import OGP: failed to reserve MSCLIST.ID at row %d -- aborting (no rows sent).', [R + 1]), 'Import OGP', 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num); // NUM is D_CHARNUM (varchar)
        FfFtrs_Notes    .AsString:= Rows[R].Notes;
        FfFtrs_FtrSuffix.AsString:= Rows[R].Suffix;
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrType  , Ord(FtrType_Variable )); // ==FtrType_Dimension(1)
        SetTag(FfFtrs_FtrMClass, Ord(CMC_Critical     ));
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          // DefaultNotation is 0-based in SetupDefaults; legacy used +1.
          if SD.DefaultNotation + 1 = Ord(SpecNotation_Tolerance) then SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('ImportOGP') then
    begin
      PersistLog('ImportOGP ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import OGP FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import OGP', MB_ICONERROR);
      Exit;
    end;
    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import OGP: %d characteristic(s) imported.', [RowCount]), 'Import OGP', MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin
procedure TBlueprint_ViewModel.ImportPDF;
var
  LForm  : TfrmBlueprintPDFImport;
  LOperID: Integer               ;
begin
  LOperID:= 0;
  if (FMTOperation <> nil) and FMTOperation.Active and (FMTOperation.RecordCount > 0) then LOperID:= FMTOperation.FieldByName('ID').AsInteger;

  LForm:= nil;
  try
    LForm:= TfrmBlueprintPDFImport.CreateForFolderOperation(nil, FConn, FFldrID, LOperID);
    try
      LForm.ShowModal;
    finally
      LForm.Free;
    end;
  except
    on E: Exception do begin LogOpenFormError('ImportPDF', E); raise; end;
  end;
end; // procedure

procedure TBlueprint_ViewModel.OpenControlPlan2;
var
  LForm: TfrmControlPlan2;
begin
  // Open the real Process Control Planning editor (TfrmControlPlan2) as an MDI
  // child of frmMAIN. CreateForFolder stashes the folder id + builds the pipe
  // ViewModel; FormStyle=fsMDIChild registers it with the MDI manager, and the
  // explicit Show makes it visible (CP2's .dfm has no form-level Visible=True).
  // The current characteristic is discovered by CP2's own grid navigation, so
  // no char id is passed. Caller (TfrmBlueprint4.btnExitToPCPClick) closes
  // Blueprint4 immediately after this returns.
  // 2026-07-02 - per-folder singleton: reactivate an open CP2 for this folder
  // instead of stacking a duplicate MDI child.
  try
    if Assigned(FindMDIChildForFolder(TfrmControlPlan2, FFldrID,
      function(F: TForm): Int64 begin Result:= TfrmControlPlan2(F).FldrID; end)) then Exit;
    LForm:= TfrmControlPlan2.CreateForFolder(Application, FFldrID);
    LForm.Show;
  except
    on E: Exception do begin LogOpenFormError('ControlPlan2', E); raise; end;
  end;
end; // procedure

{ ============================================================
  ImportSheffield -- CMM importer (backlog B), Sheffield text export.
  Faithful port of M2022 Blueprint4.Imports.ImportSheffield. Unusual
  shape: characteristics are NOT in data ROWS; they live in column
  POSITIONS of four named HEADER ROWS that must all be present:
   * Row whose col[0] = "Nominal"         -> per-char nominal value
   * Row whose col[0] = "Plus Tol"        -> per-char +tolerance
   * Row whose col[0] = "Minus Tol"       -> per-char -tolerance
   * Row whose col[0] = "Seq# Datatype"   -> per-char abbreviation (also used
                                              as the DIMNAME)
  All four rows must have the same column count. Columns before the
  first fully-numeric triplet are skipped (legacy header padding).
  Notes='Sheffield'; OPERAT stamped with FILENAME=<path>, CMMTYPE=
  CMMType_SHEFFIELD, CMMMULTIPLIER. ============================================================ }
procedure TBlueprint_ViewModel.ImportSheffield(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35;
type
  TShRow = record
    Name   : string ;
    Abbr   : string ;
    Notes  : string ;
    Num    : Integer;
    Nominal: double ;
    UTol   : double ;
    LTol   : double ;
    Unilat : Boolean;
  end;
var
  SD        : IGlobalSetupDefaults;
  Lines     : TStringList         ;
  Rows      : TArray<TShRow>      ;
  RowCount  : Integer             ;
  Issues    : TStringList         ;
  Seen35    : TStringList         ;
  CurrOperID: Integer             ;
  EncSuspect: Boolean             ;
  HdrN      : TArray<string>      ;
  HdrP      : TArray<string>      ;
  HdrM      : TArray<string>      ;
  HdrS      : TArray<string>      ;
  HdrNFound : Boolean             ;
  HdrPFound : Boolean             ;
  HdrMFound : Boolean             ;
  HdrSFound : Boolean             ;

  function Split(const S: string): TArray<string>;
  var
    raw: string;
  begin
    raw:= StringReplace(S, #9, ',', [rfReplaceAll]);
    Result:= raw.Split([','], '"');
    for var I: Integer:= 0 to high(Result) do Result[I]:= Result[I].DeQuotedString('"').Trim;
  end;

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

  function Pow10(N: Integer): double;
  begin
    Result:= 1.0;
    if N > 0 then for var I     : Integer:= 1 to N do Result:= Result * 10.0
    else if N < 0 then for var I: Integer:= 1 to -N do Result:= Result / 10.0;
  end;

begin
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import Sheffield: pipe not connected.', 'Import Sheffield', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then
  begin
    ImportMsg('Import Sheffield: select a target operation first.', 'Import Sheffield', 0); Exit;
  end;
  if not FileExists(AFileName) then begin ImportMsg('Import Sheffield: file not found: ' + AFileName, 'Import Sheffield', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import Sheffield: cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import Sheffield', 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI ' + '-- verify special characters in names.');

    // locate the four header rows by their first-column tag
    HdrNFound:= False; HdrPFound:= False; HdrMFound:= False; HdrSFound:= False;
    for var I: Integer:= 0 to Lines.Count - 1 do
    begin
      var Cols: TArray<string>:= Split(Lines[I]);
      if Length(Cols) = 0 then Continue;
      if SameText(Cols[0], 'nominal' ) then begin HdrN:= Cols; HdrNFound:= True; end
      else if SameText(Cols[0], 'plus tol'  ) then begin HdrP:= Cols; HdrPFound:= True; end
      else if SameText(Cols[0], 'minus tol' ) then begin HdrM:= Cols; HdrMFound:= True; end
      else if SameText(Cols[0], 'seq# datatype') then begin HdrS:= Cols; HdrSFound:= True; end;
      if HdrNFound and HdrPFound and HdrMFound and HdrSFound then break;
    end;
    var miss: string:= '';
    if not HdrNFound then miss:= miss + '"Nominal" ';
    if not HdrPFound then miss:= miss + '"Plus Tol" ';
    if not HdrMFound then miss:= miss + '"Minus Tol" ';
    if not HdrSFound then miss:= miss + '"Seq# Datatype" ';
    if miss <> '' then begin ImportMsg('Import Sheffield: missing required header row(s): ' + miss.Trim, 'Import Sheffield', 0); Exit; end;
    if (Length(HdrN) <> Length(HdrP)) or (Length(HdrN) <> Length(HdrM)) or (Length(HdrN) <> Length(HdrS)) then
    begin
      ImportMsg(
        Format('Import Sheffield: header rows have different column counts (%d / %d / %d / %d).', [Length(HdrN), Length(HdrP), Length(HdrM), Length(HdrS)]), 'Import Sheffield', 0);
      Exit;
    end;

    // find first column whose triplet parses as numbers (skip header padding)
    var firstDataCol: Integer:= -1;
    var skipping: Boolean:= True  ;
    for var I: Integer:= 1 to Length(HdrN) - 1 do
    begin
      var hits: Integer:= 0;
      var ok: Boolean      ;
      if HdrN[I].Trim <> '' then begin ToF(HdrN[I], ok); if ok then Inc(hits); end;
      if HdrP[I].Trim <> '' then begin ToF(HdrP[I], ok); if ok then Inc(hits); end;
      if HdrM[I].Trim <> '' then begin ToF(HdrM[I], ok); if ok then Inc(hits); end;
      if HdrS[I].Trim <> '' then Inc(hits); // any non-empty seq label counts
      if hits >= 4 then begin if skipping then firstDataCol:= I; skipping:= False; end
      else if not skipping then begin Issues.Add(Format('NUMERIC_COL_ALPHA: non-numeric in header column %d after data started.', [I + 1])); end;
    end; // for
    if firstDataCol <= 0 then begin ImportMsg('Import Sheffield: no fully-numeric data columns found.', 'Import Sheffield', 0); Exit; end;

    SetLength(Rows, Length(HdrN));
    RowCount:= 0;
    for var I: Integer:= firstDataCol to Length(HdrN) - 1 do
    begin
      var ok: Boolean                                                 ;
      var nom : double:= 0; var UTol: double:= 0; var LTol: double:= 0;
      if HdrN[I].Trim <> '' then nom := ToF(HdrN[I], ok);
      if HdrP[I].Trim <> '' then UTol:= ToF(HdrP[I], ok);
      if HdrM[I].Trim <> '' then LTol:= ToF(HdrM[I], ok);
      var vabbr: string:= HdrS[I].Trim;
      var vname: string:= vabbr       ;
      nom := nom  * AMulti;
      UTol:= UTol * AMulti;
      LTol:= LTol * AMulti;

      var Unilat: Boolean:= (nom = 0) and (LTol = 0) and (UTol > 0);
      if Unilat then LTol:= UTol;
      if (UTol = 0) and (LTol = 0) then
      begin
        if nom = 0 then begin UTol:= 1; LTol:= UTol; Unilat:= False; end
        else begin UTol:= nom * 4; LTol:= UTol; Unilat:= False; end;
      end;
      if LTol < 0 then LTol:= Abs(LTol);
      if (UTol + LTol < 1E-12) and (UTol + LTol > -1E-12) then begin var bump: double:= Pow10(ADecimals); UTol:= UTol + bump; LTol:= LTol + bump; end;

      var R: TShRow;
      R.Name:= vname; R.Abbr:= vabbr;
      R.Notes:= 'Sheffield';
      R.Num:= SD.StartingCharacteristicNumber + RowCount;
      R.Nominal:= nom; R.UTol:= UTol; R.LTol:= LTol;
      R.Unilat:= Unilat;
      if R.Name = '' then begin Issues.Add(Format('NAME_EMPTY@col %d -- characteristic skipped.', [I + 1])); Continue; end;
      if R.Name.Length > C_NAMEMAX then Issues.Add(Format('NAME_TOO_LONG@col %d: "%s" (%d>%d) -- DIMNAME stores only %d.', [I + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
      var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
      if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
          'NAME_NOT_UNIQUE_IN_%d@col %d: "%s" collides within first %d chars ' + '-- real measurement data would attach to the wrong characteristic.',
          [C_NAMEMAX, I + 1, R.Name, C_NAMEMAX]));
      Seen35.Add(key35);

      Rows[RowCount]:= R;
      Inc(RowCount);
    end; // for
    SetLength(Rows, RowCount);

    // dry-run
    var msg: string:= Format('Sheffield dry run: %s'#13#10'%d characteristic(s) parsed, %d issue(s).', [ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k: Integer:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)'#13#10, [Issues.Count - shown]);
      {$IFDEF DEBUG}CodeSite.Send('ImportSheffield issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import Sheffield', 0); Exit; end;
    if ImportMsg(msg + #13#10#13#10 + Format('Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import Sheffield -- dry run', MB_YESNO
      or MB_ICONQUESTION) <> IDYES then Exit;

    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R: Integer:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format('Import Sheffield: failed to reserve MSCLIST.ID at row %d -- aborting (no rows sent).', [R + 1]), 'Import Sheffield', 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num);
        FfFtrs_Notes .AsString:= Rows[R].Notes;
        FfFtrs_FtrSuffix .AsString:= '';
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrQClass, 0); // FTRQCLASS is TCharQClass byte-tag, like FtrMClass
        SetTag(FfFtrs_FtrType   , Ord(FtrType_Variable));
        SetTag(FfFtrs_FtrMClass , Ord(CMC_Critical    ));
        SetTag(FfFtrs_CbxPCAPPROP, 1);
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          if SD.DefaultNotation + 1 = Ord(SpecNotation_Tolerance) then SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('ImportSheffield') then
    begin
      PersistLog('ImportSheffield ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import Sheffield FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import Sheffield', MB_ICONERROR);
      Exit;
    end;

    try
      FMTOperation.Edit;
      FfOperation_FileName.AsString:= AFileName;
      FMTOperation.FieldByName('CMMTYPE'      ).AsString:= CMMType_SHEFFIELD;
      FMTOperation.FieldByName('CMMMULTIPLIER').AsFloat := AMulti;
      FMTOperation.Post;
      SendDeltaOperation('ImportSheffield(OPERAT stamp)');
    except
      on E: Exception do
        {$IFDEF DEBUG}CodeSite.Send('ImportSheffield OPERAT stamp: ' + E.Message){$ENDIF};
    end;

    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import Sheffield: %d characteristic(s) imported.', [RowCount]), 'Import Sheffield', MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin
{ ============================================================
  ImportZEISS -- CMM importer (backlog B), ZEISS Calypso. Faithful
  port of M2022 Blueprint4.Imports.ImportZEISS, same client design as
  ImportOGP (parser+dry-run client-side; server write via the existing
  cmdNextID+cmdDelta path; encoding-flexible; bulk append under
  DisableControls). ZEISS specifics vs OGP:
   * TAB-delimited; columns located by HEADER NAME (id / featureid /
     nominal / uppertol / lowertol / comment), not SetupDefaults indices;
   * required-column + trailing 'END'-terminator checks;
   * NUM from comment/ID digits per ZEISSUseCommentForNUM / ZEISSUseIDForNUM;
   * the chosen file is the '<job>_<resultnum>_chr' BLUEPRINT file; after
     import the OPERAT row is stamped FILENAME=<job>, CMMTYPE=Zeiss('A'),
     CMMMULTIPLIER -- that linkage is how the OTHER ZEISS data files get
     matched by the later Data Entry / real-data import.
  DEFERRED follow-up (parity with OGP): GDTImportCheckup GD&T pairing.
  ============================================================ }
procedure TBlueprint_ViewModel.ImportZEISS(const AFileName: string; const AMulti: double; const ADecimals: Integer; const AUnits: string);
const
  C_NAMEMAX = 35;
type
  TZRow = record
    Name   : string ;
    Abbr   : string ;
    Notes  : string ;
    Suffix : string ;
    Num    : Integer;
    Nominal: double ;
    UTol   : double ;
    LTol   : double ;
    Unilat : Boolean;
  end;
var
  SD        : IGlobalSetupDefaults;
  Lines     : TStringList         ;
  Rows      : TArray<TZRow>       ;
  RowCount  : Integer             ;
  Issues    : TStringList         ;
  Seen35    : TStringList         ;
  CurrOperID: Integer             ;
  EncSuspect: Boolean             ;
  idcol     : Integer             ;
  abbrcol   : Integer             ;
  nomcol    : Integer             ;
  utolcol   : Integer             ;
  ltolcol   : Integer             ;
  comcol    : Integer             ;
  ZJob      : string              ; // parsed job name from <job>_<num>_chr ('' = invalid)

  function ToF(const S: string; out AOk: Boolean): double;
  begin
    AOk:= True;
    if S.Trim = '' then Exit(0);
    if not TryStrToFloat(S.Trim, Result) then begin AOk:= False; Result:= 0; end;
  end;

  function HdrIdx(const ACols: TArray<string>; const AName: string): Integer;
  begin
    for var I:= 0 to high(ACols) do if SameText(ACols[I].Trim, AName) then Exit(I);
    Result:= -1;
  end;

  function Col(const ACols: TArray<string>; AIdx: Integer): string;
  begin
    if (AIdx >= 0) and (AIdx <= high(ACols)) then Result:= ACols[AIdx].Trim
    else Result:= '';
  end;

  function LeadingDigits(const S: string): Integer;
  var
    d: string; k: Integer;
  begin
    d:= ''; k:= 1;
    while (k <= S.Length) and CharInSet(S[k], ['0'..'9']) do
    begin d:= d + S[k]; Inc(k); end;
    Result:= StrToIntDef(d, 0);
  end;

begin
  if not (Assigned(FConn) and FConn.Connected) then begin ImportMsg('Import ZEISS: pipe not connected.', 'Import ZEISS', 0); Exit; end;
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then begin ImportMsg('Import ZEISS: select a target operation first.', 'Import ZEISS', 0); Exit; end;
  if not FileExists(AFileName) then begin ImportMsg('Import ZEISS: file not found: ' + AFileName, 'Import ZEISS', 0); Exit; end;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  SD:= SetupDefaultsRec;

  Lines := TStringList.Create;
  Issues:= TStringList.Create;
  Seen35:= TStringList.Create;
  try
    Seen35.Sorted:= True; Seen35.Duplicates:= dupAccept;
    try
      Lines.LoadFromFile(AFileName, DetectFileEncoding(AFileName, EncSuspect));
    except
      on E: Exception do begin ImportMsg('Import ZEISS: cannot read file (' + E.ClassName + ': ' + E.Message + ')', 'Import ZEISS', 0); Exit; end;
    end;
    if EncSuspect then Issues.Add('ENCODING_SUSPECT: file is 8-bit non-UTF-8; read as ANSI ' + '-- verify special characters in names.');
    if Lines.Count < 2 then begin ImportMsg('Import ZEISS: file has no data.', 'Import ZEISS', 0); Exit; end;

    // header (TAB) -> locate required columns by name
    var Hdr: TArray<string>:= Lines[0].Split([#9], '"');
    idcol  := HdrIdx(Hdr, 'id'      ); abbrcol:= HdrIdx(Hdr, 'featureid');
    nomcol := HdrIdx(Hdr, 'nominal' ); utolcol:= HdrIdx(Hdr, 'uppertol' );
    ltolcol:= HdrIdx(Hdr, 'lowertol'); comcol := HdrIdx(Hdr, 'comment'  );
    var miss: string:= '';
    if idcol  < 0 then miss:= miss + 'id ';
    if abbrcol< 0 then miss:= miss + 'featureid ';
    if nomcol < 0 then miss:= miss + 'nominal ';
    if utolcol< 0 then miss:= miss + 'uppertol ';
    if ltolcol< 0 then miss:= miss + 'lowertol ';
    if comcol < 0 then miss:= miss + 'comment ';
    if miss <> '' then begin ImportMsg('Import ZEISS: required column(s) missing in ' + 'header: ' + miss.Trim, 'Import ZEISS', 0); Exit; end;

    // trim trailing blank/NUL lines; require 'END' terminator
    while (Lines.Count > 0) and ((Lines[Lines.Count - 1].Trim = '') or (Lines[Lines.Count - 1][low(string)] = #0)) do Lines.Delete(Lines.Count - 1);
    if (Lines.Count = 0) or not SameText(Lines[Lines.Count - 1].Trim, 'END') then
    begin
      ImportMsg('Import ZEISS: ''END'' is missing at the end of the ' + 'data file (file incomplete?).', 'Import ZEISS', 0);
      Exit;
    end;

    // filename pattern <job>_<resultnum>_chr (links the ZEISS data files)
    ZJob:= '';
    begin
      var bn: string:= ChangeFileExt(ExtractFileName(AFileName), '').ToLower;
      if bn.Length < 7 then Issues.Add('FILENAME_PATTERN: name too short "' + bn + '" -- OPERAT not linked to ZEISS data files.')
      else if not bn.EndsWith('_chr') then Issues.Add('FILENAME_PATTERN: missing "_chr" suffix "' + bn + '" -- OPERAT not linked to ZEISS data files.')
      else
      begin
        var stem: string:= Copy(bn, 1, bn.Length - 4);
        var j: Integer:= stem.Length                 ;
        while (j >= 1) and CharInSet(stem[j], ['0'..'9']) do dec(j);
        if (j < 1) or (j >= stem.Length) or (stem[j] <> '_') or (j <= 1) then
          Issues.Add('FILENAME_PATTERN: result-number/job missing in "' + bn + '" -- OPERAT not linked to ZEISS data files.')
        else ZJob:= Copy(stem, 1, j - 1);
      end;
    end; // begin

    RowCount:= 0;
    SetLength(Rows, Lines.Count);
    for var li:= 1 to Lines.Count - 2 do // skip header + END
    begin
      var raw: string:= Lines[li];
      if raw.Trim = '' then Continue;
      var C: TArray<string>:= raw.Split([#9], '"');

      var R : TZRow;
      var ok: Boolean;
      var cN: string:= Col(C, nomcol );
      var cU: string:= Col(C, utolcol);
      var cL: string:= Col(C, ltolcol);
      R.Nominal:= ToF(cN, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Nominal ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cN]));
      R.UTol:= ToF(cU, ok) * AMulti;
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Upper-Tol ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cU]));
      // legacy ZEISS sign: ltol := 0 - parsed*AMulti
      R.LTol:= -(ToF(cL, ok) * AMulti);
      if not ok then Issues.Add(Format('NUMERIC_COL_ALPHA@line %d: Lower-Tol ' + 'column has non-numeric "%s" -- likely a column mix-up; taken as 0.', [li + 1, cL]));
      R.Unilat:= (R.Nominal = 0) and (R.LTol = 0) and (R.UTol > 0);
      if R.Unilat then R.LTol:= R.UTol;

      R.Name:= Col(C, idcol  );
      R.Abbr:= Col(C, abbrcol);
      R.Notes:= 'ZEISS Calypso:' + Col(C, comcol);
      R.Suffix:= '';
      var numComment: Integer:= LeadingDigits(Col(C, comcol));
      R.Num:= SD.StartingCharacteristicNumber + RowCount;
      if (SD.ZEISSUseCommentForNUM = 1) and (numComment <> 0) then R.Num:= numComment;
      if SD.ZEISSUseIDForNUM = 1 then
      begin
        var numId: Integer:= LeadingDigits(R.Name);
        if numId <> 0 then
        begin
          R.Num:= numId;
          // suffix = up to 6 non-space chars after the leading digit run
          var k: Integer:= 1;
          while (k <= R.Name.Length) and CharInSet(R.Name[k], ['0'..'9']) do Inc(k);
          var st: Integer:= k;
          while (k <= R.Name.Length) and (k - st < 6) and (R.Name[k] <> ' ') do Inc(k);
          if k > st then R.Suffix:= Copy(R.Name, st, k - st);
        end
        else R.Num:= SD.StartingCharacteristicNumber + RowCount;
      end;

      if R.Name = '' then Issues.Add(Format('NAME_EMPTY@line %d -- characteristic skipped.', [li + 1]))
      else
      begin
        if R.Name.Length > C_NAMEMAX then
          Issues.Add(Format('NAME_TOO_LONG@line %d: "%s" (%d>%d) -- DIMNAME ' + 'stores only %d.', [li + 1, R.Name, R.Name.Length, C_NAMEMAX, C_NAMEMAX]));
        var key35: string:= UpperCase(Copy(R.Name, 1, C_NAMEMAX));
        if Seen35.IndexOf(key35) >= 0 then Issues.Add(Format(
            'NAME_NOT_UNIQUE_IN_%d@line %d: "%s" collides within ' + 'first %d chars -- real measurement data would attach to the ' + 'wrong characteristic.',
            [C_NAMEMAX, li + 1, R.Name, C_NAMEMAX]));
        Seen35.Add(key35);
        Rows[RowCount]:= R;
        Inc(RowCount);
      end;
    end; // for
    SetLength(Rows, RowCount);

    var msg: string:= Format('ZEISS dry run: %s'#13#10 + '%d characteristic(s) parsed, %d issue(s).', [ExtractFileName(AFileName), RowCount, Issues.Count]);
    if Issues.Count > 0 then
    begin
      var shown: Integer:= Issues.Count; if shown > 12 then shown:= 12;
      msg:= msg + #13#10#13#10;
      for var k:= 0 to shown - 1 do msg:= msg + Issues[k] + #13#10;
      if Issues.Count > shown then msg:= msg + Format('... (+%d more)', [Issues.Count - shown]) + #13#10;
      {$IFDEF DEBUG}CodeSite.Send('ImportZEISS issues', Issues);{$ENDIF}
    end;
    if RowCount = 0 then begin ImportMsg(msg + #13#10#13#10 + 'Nothing to import.', 'Import ZEISS', 0); Exit; end;
    if ImportMsg(msg + #13#10#13#10 + Format( 'Import %d characteristic(s) into the selected operation?', [RowCount]), 'Import ZEISS -- dry run', MB_YESNO
      or MB_ICONQUESTION) <> IDYES then Exit;

    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      for var R:= 0 to high(Rows) do
      begin
        var NewID: Integer;
        if not ReserveNextID('GEN_MSCLIST_ID', NewID) then
        begin
          ImportMsg(Format('Import ZEISS: failed to reserve ' + 'MSCLIST.ID at row %d -- aborting (no rows sent).', [R + 1]), 'Import ZEISS', 0);
          FMTFtrs.CancelUpdates; Exit;
        end;
        FMTFtrs.Append;
        FfFtrs_ID    .AsLargeInt:= NewID;
        FfFtrs_FldrID.AsLargeInt:= FFldrID;
        FfFtrs_OperID.AsLargeInt:= CurrOperID;
        FfFtrs_MasterID .AsLargeInt:= NewID; // self-master: MASTERID = ID (Paradox model; sub-features point at a real master)
        FfFtrs_OperOrd .AsInteger:= R;
        FfFtrs_DimName .AsString:= Copy(Rows[R].Name, 1, C_NAMEMAX);
        FfFtrs_DimAbbr .AsString:= Rows[R].Abbr;
        FfFtrs_Num .AsString:= IntToStr(Rows[R].Num);
        FfFtrs_Notes    .AsString:= Rows[R].Notes;
        FfFtrs_FtrSuffix.AsString:= Rows[R].Suffix;
        FfFtrs_DimUnits .AsString:= (if AUnits <> '' then AUnits else SD.DefaultUnits);
        FfFtrs_Decimals .AsInteger:= (if ADecimals > 0 then ADecimals else SD.DefaultDecimals);
        FfFtrs_Nominal .AsFloat:= Rows[R].Nominal;
        FfFtrs_UpperTol.AsFloat:= Rows[R].UTol;
        FfFtrs_LowerTol.AsFloat:= Rows[R].LTol;
        FfFtrs_USL .AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_LSL .AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_OriginalUSL.AsFloat:= Rows[R].Nominal + Rows[R].UTol;
        FfFtrs_OriginalLSL.AsFloat:= Rows[R].Nominal - Rows[R].LTol;
        FfFtrs_InspAsVar.AsBoolean:= True; // INSPASVAR is BOOLEAN -- not byte-tag, not Integer
        SetTag(FfFtrs_FtrQClass, 0); // FTRQCLASS is TCharQClass byte-tag, like FtrMClass
        SetTag(FfFtrs_FtrType  , Ord(FtrType_Variable));
        SetTag(FfFtrs_FtrMClass, Ord(CMC_Critical    ));
        SetTag(FfFtrs_CbxPCAPPROP, 1); // ZEISS sets PCAPPROP on (unlike OGP)
        if Rows[R].Unilat then begin SetTag(FfFtrs_SpecType, Ord(SpecType_SingleUpper)); SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec )); end
        else
        begin
          SetTag(FfFtrs_SpecType, Ord(SpecType_Double));
          if SD.DefaultNotation + 1 = Ord(SpecNotation_Tolerance) then SetTag(FfFtrs_Notation, Ord(SpecNotation_Tolerance))
          else SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
        end;
        FMTFtrs.Post;
      end; // for
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end; // try
    if not SendDeltaFtrs('ImportZEISS') then
    begin
      PersistLog('ImportZEISS ABORTED: char delta rejected. ' + GetLastPersistError);
      LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
      ImportMsg('Import ZEISS FAILED to save the characteristics:'#13#10#13#10 + GetLastPersistError + #13#10#13#10 + 'No characteristics were imported.', 'Import ZEISS', MB_ICONERROR);
      Exit;
    end;

    // Stamp the OPERAT row so the later Data Entry / real-data import can
    // find this operation's ZEISS data files (only if filename was valid).
    if ZJob <> '' then
    begin
      try
        FMTOperation.Edit;
        FfOperation_FileName.AsString:= ZJob;
        FMTOperation.FieldByName('CMMTYPE'      ).AsString:= CMMType_Zeiss; // 'A'
        FMTOperation.FieldByName('CMMMULTIPLIER').AsFloat := AMulti;
        FMTOperation.Post;
        SendDeltaOperation('ImportZEISS(OPERAT stamp)');
      except
        on E: Exception do
          {$IFDEF DEBUG}CodeSite.Send('ImportZEISS OPERAT stamp: ' + E.Message){$ENDIF};
      end;
    end;

    LoadOneTable(FMTFtrs, 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
    if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
    FRequireRefresh:= True;
    ImportMsg(Format('Import ZEISS: %d characteristic(s) ' + 'imported.', [RowCount]), 'Import ZEISS', MB_ICONINFORMATION);
  finally
    Seen35.Free; Issues.Free; Lines.Free;
  end; // try
end; // begin
// 2026-05-14 -- LoadFtrRecord now implemented; see Char CRUD section below.
// 2026-05-14 -- RefreshFieldOrder now implemented; see Char CRUD section below.
// 2026-05-14 -- SaveFtrRecord now implemented; see Char CRUD section below.
procedure TBlueprint_ViewModel.DoSmartClassify(const ATolGramLim, AGramLim1, AGramLim2, AGramLim3: array of double);
// 2026-05-17 -- Ported from Blueprint4.Model.pas.OLD SmartClassifyInches/MM.
// Pass 1: tally each variable characteristic's spec tolerance into 6 bands ->
// pick a ClassCase from which band is first populated. Pass 2: assign
// FtrMClass (Safety/Critical/Major/Minor) per the chosen case's limits.
// Adaptations vs OLD: (1) gate on FtrType=Variable via TagOf(FfFtrs_FtrType)
// (OLD used the BDE 'Attribute' boolean -- variable chars are exactly
// FtrType_Variable); (2) SpecType/FtrMClass are D_BYTETAG TBytesField now ->
// TagOf/SetTag, not .AsInteger; (3) local ALMOST_ZERO (OLD AlmoustZero not in
// this unit's scope); (4) batched + SendDeltaFtrs so it persists.
const
  ALMOST_ZERO = 1E-9;
var
  ClassCase: Integer                  ;
  I        : Integer                  ;
  tol      : double                   ;
  TolGram  : array [1 .. 6] of Integer;
  BM       : TBookmark                ;
begin
  if (not FMTFtrs.Active) or FMTFtrs.IsEmpty then Exit;
  for I:= 1 to 6 do TolGram[I]:= 0;
  FSuppressEvents:= True;
  BM:= FMTFtrs.GetBookmark;
  FMTFtrs.DisableControls;
  try
    // Pass 1 -- tally tolerance bands over variable characteristics only.
    FMTFtrs.First;
    while not FMTFtrs.Eof do
    begin
      if TagOf(FfFtrs_FtrType) = Ord(FtrType_Variable) then
      begin
        tol:= Abs(FfFtrs_USL.AsFloat - FfFtrs_LSL.AsFloat);
        if TagOf(FfFtrs_SpecType) = SpecType_SingleUpper.ToInteger then tol:= Abs(FfFtrs_USL.AsFloat);
        if tol > ALMOST_ZERO * 4 then
        begin
          if tol <= ATolGramLim[0] then Inc(TolGram[1])
          else if tol <= ATolGramLim[1] then Inc(TolGram[2])
          else if tol <= ATolGramLim[2] then Inc(TolGram[3])
          else if tol <= ATolGramLim[3] then Inc(TolGram[4])
          else if tol <= ATolGramLim[4] then Inc(TolGram[5])
          else Inc(TolGram[6]);
        end;
      end;
      FMTFtrs.Next;
    end; // while
    if TolGram[1] > 0 then ClassCase:= 1
    else if TolGram[2] > 0 then ClassCase:= 2
    else ClassCase:= 3;

    // Pass 2 -- assign FtrMClass per the chosen case's limits.
    FMTFtrs.First;
    while not FMTFtrs.Eof do
    begin
      if TagOf(FfFtrs_FtrType) = Ord(FtrType_Variable) then
      begin
        tol:= Abs(FfFtrs_USL.AsFloat - FfFtrs_LSL.AsFloat);
        if TagOf(FfFtrs_SpecType) = SpecType_SingleUpper.ToInteger then tol:= Abs(FfFtrs_USL.AsFloat);
        if tol > ALMOST_ZERO * 4 then
        try
          FMTFtrs.Edit;
          var GL: TArray<double>;
          case ClassCase of
            1: GL:= [AGramLim1[0], AGramLim1[1], AGramLim1[2]];
            2: GL:= [AGramLim2[0], AGramLim2[1], AGramLim2[2]];
            else GL:= [AGramLim3[0], AGramLim3[1], AGramLim3[2]];
          end;
          if tol <= GL[0] then SetTag(FfFtrs_FtrMClass, CMC_Safety.ToInteger)
          else if tol <= GL[1] then SetTag(FfFtrs_FtrMClass, CMC_Critical.ToInteger)
          else if tol <= GL[2] then SetTag(FfFtrs_FtrMClass, CMC_Major .ToInteger)
          else SetTag(FfFtrs_FtrMClass, CMC_Minor.ToInteger);
          FMTFtrs.Post;
        except
          on E: Exception do
          begin
            if FMTFtrs.State in [dsEdit, dsInsert] then FMTFtrs.Cancel;
            {$IFDEF DEBUG}CodeSite.Send(csmRed, 'SmartClassify row: ' + E.Message);{$ENDIF}
          end;
        end; // try
      end; // if
      FMTFtrs.Next;
    end; // while
  finally
    if FMTFtrs.BookmarkValid(BM) then FMTFtrs.GotoBookmark(BM);
    FMTFtrs.FreeBookmark(BM);
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end; // try
  SendDeltaFtrs('SmartClassify');
end; // procedure

procedure TBlueprint_ViewModel.SmartClassifyInches;
begin
  DoSmartClassify(
    [0.00100000001, 0.00300000001, 0.00500000001, 0.00800000001, 0.0100000001], [0.00100000001, 0.00300000001, 0.0100000001], [0.00300000001, 0.00500000001, 0.0100000001],
    [0.00500000001, 0.00800000001, 0.0100000001]);
end;

procedure TBlueprint_ViewModel.SmartClassifyMM;
begin
  DoSmartClassify(
    [0.02540000001, 0.07620000001, 0.12700000001, 0.20320000001, 0.2540000001], [0.02540000001, 0.07620000001, 0.2540000001], [0.07620000001, 0.12700000001, 0.2540000001],
    [0.12700000001, 0.20320000001, 0.2540000001]);
end;
// 2026-05-14 -- ToGNGSelected/Suffix now implemented; see GNG section below.

{ ============================================================
  MSCLIST persistence + GNG (Go/No-Go) cluster
  ============================================================
  - AfterPost/AfterDelete on FMTFtrs trigger cmdDelta to server.
  - GNG transforms a characteristic to a binary 0=PASS / 1=FAIL spec
    (USL=0.9, LSL=-0.9, ZeroAt=1.0, SpecType=SingleUpper, suffix=GNG).
  - The original USL/LSL pair is preserved in MathLine so FromGNG
    can restore the real spec.
  - Suffix variants scan FMTFtrs for chars where FtrSuffix is GNG;
    Selected variants apply transform to caller-supplied ID array.
  - Each public method batches its changes (FSuppressEvents=True
    during the loop), then sends one cmdDelta with all pending rows.
  ============================================================ }

procedure TBlueprint_ViewModel.DoAfterPostFtrs(DataSet: TDataSet);
begin
  if FSuppressEvents then Exit;
  SendDeltaFtrs('AfterPost');
end;

procedure TBlueprint_ViewModel.DoAfterDeleteFtrs(DataSet: TDataSet);
begin
  if FSuppressEvents then Exit;
  SendDeltaFtrs('AfterDelete');
end;

function TBlueprint_ViewModel.SendDeltaFtrs(const AContext: string): Boolean;
var
  MS         : TMemoryStream     ;
  StreamBytes: TBytes            ;
  Prefix     : TBytes            ;
  Payload    : TBytes            ;
  RspHdr     : TPipeMessageHeader;
  RspPayload : TBytes            ;
  GLE        : DWORD             ;
begin
  // 2026-05-26 -- mirrors SendDeltaFolder: clear error, CancelUpdates on
  // reject, no modal MessageBox (would deadlock the headless autotest).
  // The form-level surface (ShowPersistErrorIfAny) reads LastPersistError.
  FLastPersistError:= '';
  Result           := False;
  PersistLog(Format('SendDeltaFtrs enter: ctx=%s ChangeCount=%d FConn.Connected=%d',
    [AContext, FMTFtrs.ChangeCount, Ord(Assigned(FConn) and FConn.Connected)]));
  if FMTFtrs.ChangeCount = 0 then Exit(True);
  if not (Assigned(FConn) and FConn.Connected) then Exit;

  MS:= TMemoryStream.Create;
  try
    FMTFtrs.SaveToStream(MS, sfBinary);
    SetLength(StreamBytes, MS.Size);
    if MS.Size > 0 then begin MS.Position:= 0; MS.ReadBuffer(StreamBytes[0], MS.Size); end;
    Prefix:= TEncoding.UTF8.GetBytes('TABLE=MSCLIST|');
    SetLength(Payload, Length(Prefix) + Length(StreamBytes));
    Move(Prefix[0], Payload[0], Length(Prefix));
    if Length(StreamBytes) > 0 then Move(StreamBytes[0], Payload[Length(Prefix)], Length(StreamBytes));
    GLE:= FConn.ExecuteCommand(cmdDelta, Payload, RspHdr, RspPayload);
  finally
    MS.Free;
  end; // try

  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
  begin
    if Length(RspPayload) > 0 then FLastPersistError:= 'MSCLIST ' + AContext + ': ' + TEncoding.UTF8.GetString(RspPayload)
    else FLastPersistError:= Format('MSCLIST %s FAILED (GLE=%d)', [AContext, GLE]);
    PersistLog(Format('MSCLIST %s REJECTED by server: %s', [AContext, FLastPersistError]));
    CodeSite.Send(csmError, FLastPersistError);
    // Drop the rejected delta so the bad row doesn't poison subsequent
    // posts -- otherwise every following AddCharacteristic / edit would
    // be re-shipped with the failing row and rejected again.
    FSuppressEvents:= True;
    FMTFtrs.DisableControls;
    try
      FMTFtrs.CancelUpdates;
    finally
      FMTFtrs.EnableControls;
      FSuppressEvents:= False;
    end;
    Exit;
  end; // if

  // Server accepted -- clear local delta tracking. Values are already correct.
  // Log the server's apply summary ("MSCLIST: ins=X upd=Y del=Z"): an accepted
  // delta with ins=0/upd=N means the client's new INSERT rows were silently
  // applied as no-op UPDATEs (usInserted flipped to usModified) -- rows vanish.
  PersistLog(Format('SendDeltaFtrs: server ACCEPTED ctx=%s payloadBytes=%d serverSummary=[%s]',
    [AContext, Length(Payload),
     (if Length(RspPayload) > 0 then TEncoding.UTF8.GetString(RspPayload) else '')]));
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    FMTFtrs.CommitUpdates;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  Result:= True;
end; // function

function TBlueprint_ViewModel.FlushFolder: Boolean;
// 2026-06-23 -- Called from FormClose to ensure any FOLDERS (Job Header)
// edit the user typed but did not explicitly Post is saved before the form
// tears down. Without this, edits in dsEdit/dsInsert state skip AfterPost
// and are silently lost.
// Pattern: Post drives AfterPost -> DoAfterPostFolder -> SendDeltaFolder.
// If nothing is pending, SendDeltaFolder exits immediately (ChangeCount=0).
begin
  Result:= False;
  if not (Assigned(FMTFolder) and FMTFolder.Active) then begin Result:= True; Exit; end;
  if FMTFolder.State in [dsEdit, dsInsert] then
  begin
    try
      FMTFolder.Post; // triggers DoAfterPostFolder -> SendDeltaFolder
    except
      on E: Exception do
      begin
        FLastPersistError:= 'FlushFolder Post failed: ' + E.Message;
        PersistLog(FLastPersistError);
        Exit; // Result stays False
      end;
    end;
  end;
  // If Post already triggered SendDeltaFolder via AfterPost, ChangeCount is
  // now 0 and SendDeltaFolder will return True immediately (nothing to send).
  // If FSuppressEvents was True during the Post, the AfterPost was skipped,
  // so we send the delta explicitly here.
  if FMTFolder.ChangeCount > 0 then
    Result:= SendDeltaFolder('FlushFolder')
  else
    Result:= True;
end;

// 2026-05-19 -- Job Header persistence. FMTFolder is the single FOLDERS row
// loaded by LoadAllForFolder (CachedUpdates=True set by LoadOneTable). When a
// repointed header DB-edit (Main Tags edtF1..F5 / Lot / Ext / MRB / Part /
// Machine / Date) posts the row, push the delta via the same generic cmdDelta
// path MSCLIST/OPERAT use. The server's TGenericTableRoute keys on TABLE= and
// the table's PK (FOLDERS.FLDR_SYSTID) from FIB$DATASETS_INFO.
procedure TBlueprint_ViewModel.DoAfterPostFolder(DataSet: TDataSet);
var
  LMsg: string;
begin
  LMsg:= Format('DoAfterPostFolder: FSuppressEvents=%d, ChangeCount=%d, FMTFolder.Active=%d', [Ord(FSuppressEvents), FMTFolder.ChangeCount, Ord(FMTFolder.Active)]);
  CodeSite.Send(LMsg);
  PersistLog(LMsg);
  if FSuppressEvents then begin PersistLog('DoAfterPostFolder: FSuppressEvents=True -> SendDeltaFolder SKIPPED'); Exit; end;
  SendDeltaFolder('AfterPost');
end;

function TBlueprint_ViewModel.SendDeltaFolder(const AContext: string): Boolean;
var
  MS         : TMemoryStream     ;
  StreamBytes: TBytes            ;
  Prefix     : TBytes            ;
  Payload    : TBytes            ;
  RspHdr     : TPipeMessageHeader;
  RspPayload : TBytes            ;
  GLE        : DWORD             ;
begin
  // 2026-05-26 -- clear any prior rejection BEFORE work so callers that
  // read LastPersistError after a successful Post see ''.
  FLastPersistError:= '';
  PersistLog(Format('SendDeltaFolder enter: ctx=%s ChangeCount=%d FConn.Connected=%d', [AContext, FMTFolder.ChangeCount, if Assigned(FConn) then Ord(FConn.Connected) else -1]));
  CodeSite.Send('SendDeltaFolder enter: ctx=%s ChangeCount=%d FConn.Connected=%d', [AContext, FMTFolder.ChangeCount, if Assigned(FConn) then Ord(FConn.Connected) else -1]);
  Result:= False;
  if FMTFolder.ChangeCount = 0 then
  begin
    PersistLog('SendDeltaFolder: ChangeCount=0 -> nothing to send');
    CodeSite.Send(csmYellow, 'SendDeltaFolder: ChangeCount=0 -> nothing to send');
    Exit(True);
  end;
  if not (Assigned(FConn) and FConn.Connected) then
  begin
    PersistLog('SendDeltaFolder: FConn not connected -> delta LOST');
    CodeSite.Send(csmRed, 'SendDeltaFolder: FConn not connected -> delta LOST');
    Exit;
  end;

  MS:= TMemoryStream.Create;
  try
    FMTFolder.SaveToStream(MS, sfBinary);
    SetLength(StreamBytes, MS.Size);
    if MS.Size > 0 then begin MS.Position:= 0; MS.ReadBuffer(StreamBytes[0], MS.Size); end;
    Prefix:= TEncoding.UTF8.GetBytes('TABLE=FOLDERS|');
    SetLength(Payload, Length(Prefix) + Length(StreamBytes));
    Move(Prefix[0], Payload[0], Length(Prefix));
    if Length(StreamBytes) > 0 then Move(StreamBytes[0], Payload[Length(Prefix)], Length(StreamBytes));
    GLE:= FConn.ExecuteCommand(cmdDelta, Payload, RspHdr, RspPayload);
  finally
    MS.Free;
  end; // try

  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
  begin
    // Headless-safe: NEVER a modal MessageBox here. The autotest harness
    // (and any server-side reject) would deadlock forever waiting for a
    // click. Surface via FLastPersistError instead -- the form polls it
    // post-Post and the autotest reads VM.LastPersistError.
    if Length(RspPayload) > 0 then FLastPersistError:= TEncoding.UTF8.GetString(RspPayload)
    else FLastPersistError:= Format('FOLDERS %s FAILED (GLE=%d cmd=%d)', [AContext, GLE, Ord(TCommandID(RspHdr.CommandID))]);
    PersistLog(Format('FOLDERS %s REJECTED by server: %s', [AContext, FLastPersistError]));
    CodeSite.Send(csmError, Format('FOLDERS %s rejected by server: %s', [AContext, FLastPersistError]));
    // 2026-05-26 -- CRITICAL: drop the rejected delta. Without this, the
    // bad row stays in FMTFolder.ChangeCount > 0 and rides along on every
    // subsequent Post -- the next legit edit (e.g. BATCHID) gets bundled
    // with the FK-violating XTOLERANCE and is rejected too. That's the
    // "all my edits disappear" bug the user reported. CancelUpdates
    // reverts every pending row to its server-snapshot values so the
    // user (or another field edit) starts from a clean baseline.
    FSuppressEvents:= True;
    FMTFolder.DisableControls;
    try
      FMTFolder.CancelUpdates;
    finally
      FMTFolder.EnableControls;
      FSuppressEvents:= False;
    end;
    Exit;
  end; // if

  // Server accepted -- clear local delta tracking. Values are already correct.
  PersistLog(Format('SendDeltaFolder: server ACCEPTED ctx=%s payloadBytes=%d', [AContext, Length(Payload)]));
  CodeSite.Send(csmGreen, 'SendDeltaFolder: server ACCEPTED ctx=%s payloadBytes=%d', [AContext, Length(Payload)]);
  FSuppressEvents:= True;
  FMTFolder.DisableControls;
  try
    FMTFolder.CommitUpdates;
  finally
    FMTFolder.EnableControls;
    FSuppressEvents:= False;
  end;
  Result:= True;
end; // function

procedure TBlueprint_ViewModel.ToGNG1Char;
const
  tol = 0.0001;
var
  instr: string;
  LSL  : double;
  USL  : double;
begin
  USL:= tblFtrsUSL.AsFloat;
  LSL:= tblFtrsLSL.AsFloat;
  instr:= UpperCase(tblFtrsNotes.AsString);
  // Idempotent: skip if already shaped as GNG
  if (Abs(USL - 0.9) < tol) and (Abs(LSL + 0.9) < tol) and (Abs(tblFtrsZeroAt.AsFloat - 1.0) < tol) and isGNG(tblFtrsFtrSuffix.AsString) then Exit;
  FMTFtrs.Edit;
  SetTag(tblFtrsNotation, Ord(SpecNotation_Spec   ));
  SetTag(tblFtrsSpecType, Ord(SpecType_SingleUpper));
  tblFtrsOriginalUSL .AsFloat:= 0.9;
  tblFtrsOriginalLSL .AsFloat:= -0.9;
  tblFtrsUSL .AsFloat:= 0.9;
  tblFtrsLSL .AsFloat:= -0.9;
  tblFtrsUpperTol   .AsFloat  := 0.9;
  tblFtrsLowerTol   .AsFloat  := 0.9;
  tblFtrsNominal    .AsFloat  := 0;
  tblFtrsFtrSuffix  .AsString := GNG_SUFFIX;
  tblFtrsZeroAt     .AsFloat  := 1.0;
  tblFtrsIndicator  .AsBoolean:= False;
  tblFtrsUseMathLine.AsBoolean:= False;
  tblFtrsGagePortNmbr.AsInteger:= -1;
  tblFtrsMathLine .AsString:= Format('%s / %s', [ FloatToStrF(USL, ffFixed, 11, tblFtrsDecimals.AsInteger), FloatToStrF(LSL, ffFixed, 11, tblFtrsDecimals.AsInteger)]);
  if Pos(GNG_INSTRUCTIONS, instr) <= 0 then tblFtrsNotes.AsString:= tblFtrsNotes.AsString + GNG_INSTRUCTIONS;
  FMTFtrs.Post;
end; // procedure

procedure TBlueprint_ViewModel.FromGNG1Char;
var
  instr: string ;
  j    : Integer;
  LSL  : double ;
  USL  : double ;
  nom  : double ;
begin
  instr:= tblFtrsMathLine.AsString;
  ExtractUSLLSL(instr, USL, LSL);
  nom:= (USL + LSL) / 2;
  instr:= tblFtrsNotes.AsString;
  j:= Pos(GNG_INSTRUCTIONS, UpperCase(instr));
  if j > 0 then System.Delete(instr, j, Length(GNG_INSTRUCTIONS));
  FMTFtrs.Edit;
  SetTag(tblFtrsNotation, Ord(SpecNotation_Spec));
  SetTag(tblFtrsSpecType, Ord(SpecType_Double  ));
  tblFtrsOriginalUSL.AsFloat:= USL;
  tblFtrsOriginalLSL.AsFloat:= LSL;
  tblFtrsUSL        .AsFloat:= USL;
  tblFtrsLSL        .AsFloat:= LSL;
  tblFtrsUpperTol.AsFloat:= USL - nom;
  tblFtrsLowerTol.AsFloat:= nom - LSL;
  tblFtrsNominal     .AsFloat  := nom;
  tblFtrsFtrSuffix   .AsString := '';
  tblFtrsZeroAt      .AsFloat  := 0.0;
  tblFtrsIndicator   .AsBoolean:= False;
  tblFtrsUseMathLine .AsBoolean:= False;
  tblFtrsGagePortNmbr.AsInteger:= 0;
  tblFtrsMathLine    .AsString := '';
  tblFtrsNotes       .AsString := instr;
  FMTFtrs.Post;
end; // procedure

procedure TBlueprint_ViewModel.ToGNGSuffix;
var
  IDs: TArray<Integer>;
  I  : Integer        ;
begin
  if (not FMTFtrs.Active) or FMTFtrs.IsEmpty then Exit;
  SetLength(IDs, 0);
  FMTFtrs.DisableControls;
  try
    FMTFtrs.First;
    while not FMTFtrs.Eof do
    begin
      if isGNG(tblFtrsFtrSuffix.AsString) then begin SetLength(IDs, Length(IDs) + 1); IDs[high(IDs)]:= tblFtrsID.AsInteger; end;
      FMTFtrs.Next;
    end;
  finally
    FMTFtrs.EnableControls;
  end;
  if Length(IDs) = 0 then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(IDs) to high(IDs) do if FMTFtrs.Locate('ID', IDs[I], []) then ToGNG1Char;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaFtrs('ToGNGSuffix');
end; // procedure

procedure TBlueprint_ViewModel.FromGNGSuffix;
var
  IDs: TArray<Integer>;
  I  : Integer        ;
begin
  if (not FMTFtrs.Active) or FMTFtrs.IsEmpty then Exit;
  SetLength(IDs, 0);
  FMTFtrs.DisableControls;
  try
    FMTFtrs.First;
    while not FMTFtrs.Eof do
    begin
      if isGNG(tblFtrsFtrSuffix.AsString) then begin SetLength(IDs, Length(IDs) + 1); IDs[high(IDs)]:= tblFtrsID.AsInteger; end;
      FMTFtrs.Next;
    end;
  finally
    FMTFtrs.EnableControls;
  end;
  if Length(IDs) = 0 then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(IDs) to high(IDs) do if FMTFtrs.Locate('ID', IDs[I], []) then FromGNG1Char;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaFtrs('FromGNGSuffix');
end; // procedure

procedure TBlueprint_ViewModel.ToGNGSelected(AID: TArray<Integer>);
var
  I: Integer;
begin
  if Length(AID) <= 0 then Exit;
  if (not FMTFtrs.Active) or FMTFtrs.IsEmpty then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(AID) to high(AID) do if FMTFtrs.Locate('ID', AID[I], []) then ToGNG1Char;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaFtrs('ToGNGSelected');
end;

procedure TBlueprint_ViewModel.FromGNGSelected(AID: TArray<Integer>);
var
  I: Integer;
begin
  if Length(AID) <= 0 then Exit;
  if (not FMTFtrs.Active) or FMTFtrs.IsEmpty then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(AID) to high(AID) do if FMTFtrs.Locate('ID', AID[I], []) then FromGNG1Char;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaFtrs('FromGNGSelected');
end;

{ ============================================================
  OPERAT persistence + Operation CRUD
  ============================================================
  - AfterPost/AfterDelete on FMTOperation trigger cmdDelta to server.
  - AddOperation: reserves a new ID via cmdNextID(GEN_OPERAT_ID),
    appends a row with the next Num for this folder, posts (saves),
    then AppendCharGroups seeds a default group-visual characteristic.
  - DeleteOperation: deletes the OPERAT row; database FK cascade
    (per cascade audit) drops MSCLIST/GINSP/OSUBLOT/TOOL*/etc., and
    SET DEFAULT FKs null OPERID on log/state tables (GONOFF, LOGEDON,
    MACHINESTAT, etc.).
  - ReserveNextID: generic cmdNextID helper; reads a Pascal int from
    the server's text reply.
  ============================================================ }

procedure TBlueprint_ViewModel.DoAfterPostOperation(DataSet: TDataSet);
begin
  if FSuppressEvents then Exit;
  SendDeltaOperation('AfterPost');
end;

procedure TBlueprint_ViewModel.DoAfterDeleteOperation(DataSet: TDataSet);
begin
  if FSuppressEvents then Exit;
  SendDeltaOperation('AfterDelete');
end;

function TBlueprint_ViewModel.SendDeltaOperation(const AContext: string): Boolean;
var
  MS         : TMemoryStream     ;
  StreamBytes: TBytes            ;
  Prefix     : TBytes            ;
  Payload    : TBytes            ;
  RspHdr     : TPipeMessageHeader;
  RspPayload : TBytes            ;
  GLE        : DWORD             ;
begin
  // 2026-05-26 -- mirrors SendDeltaFolder/Ftrs. See the comment there.
  FLastPersistError:= '';
  Result           := False;
  if FMTOperation.ChangeCount = 0 then Exit(True);
  if not (Assigned(FConn) and FConn.Connected) then Exit;

  MS:= TMemoryStream.Create;
  try
    FMTOperation.SaveToStream(MS, sfBinary);
    SetLength(StreamBytes, MS.Size);
    if MS.Size > 0 then begin MS.Position:= 0; MS.ReadBuffer(StreamBytes[0], MS.Size); end;
    Prefix:= TEncoding.UTF8.GetBytes('TABLE=OPERAT|');
    SetLength(Payload, Length(Prefix) + Length(StreamBytes));
    Move(Prefix[0], Payload[0], Length(Prefix));
    if Length(StreamBytes) > 0 then Move(StreamBytes[0], Payload[Length(Prefix)], Length(StreamBytes));
    GLE:= FConn.ExecuteCommand(cmdDelta, Payload, RspHdr, RspPayload);
  finally
    MS.Free;
  end; // try

  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
  begin
    if Length(RspPayload) > 0 then FLastPersistError:= 'OPERAT ' + AContext + ': ' + TEncoding.UTF8.GetString(RspPayload)
    else FLastPersistError:= Format('OPERAT %s FAILED (GLE=%d)', [AContext, GLE]);
    PersistLog(Format('OPERAT %s REJECTED by server: %s', [AContext, FLastPersistError]));
    CodeSite.Send(csmError, FLastPersistError);
    FSuppressEvents:= True;
    FMTOperation.DisableControls;
    try
      FMTOperation.CancelUpdates;
    finally
      FMTOperation.EnableControls;
      FSuppressEvents:= False;
    end;
    Exit;
  end; // if

  FSuppressEvents:= True;
  FMTOperation.DisableControls;
  try
    FMTOperation.CommitUpdates;
  finally
    FMTOperation.EnableControls;
    FSuppressEvents:= False;
  end;
  Result:= True;
end; // function

function TBlueprint_ViewModel.ReserveNextID(const AGenName: string; out ANewID: Integer): Boolean;
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
  NewID64   : Int64             ;
begin
  Result:= False;
  ANewID:= 0;
  if not (Assigned(FConn) and FConn.Connected) then Exit;
  Payload:= TEncoding.UTF8.GetBytes('GEN=' + AGenName);
  GLE:= FConn.ExecuteCommand(cmdNextID, Payload, RspHdr, RspPayload);
  if GLE <> ERROR_SUCCESS then Exit;
  // 2026-05-17 -- The cmdNextID server (HandleNextID) returns the new ID as an
  // 8-byte Int64 BINARY payload with CommandID = rspData -- NOT a UTF-8 string
  // with rspOK. The previous rspOK + UTF8-string parse never matched, so every
  // call failed ("Failed to reserve new OPERAT/MSCLIST ID"). This now mirrors
  // the canonical <TABLE>_CLIENT.NextID decode (e.g. uCAUSFAIL_CLIENT.PAS).
  if (TCommandID(RspHdr.CommandID) = rspData) and (Length(RspPayload) = 8) then
  begin
    Move(RspPayload[0], NewID64, SizeOf(NewID64));
    ANewID:= Integer(NewID64);
    Result:= ANewID > 0;
  end;
end; // function

function TBlueprint_ViewModel.TagOf(F: TField): Integer;
var
  B: TBytes;
begin
  Result:= 0;
  if (F = nil) or F.IsNull then Exit;
  if F is TBytesField then begin B:= F.AsBytes; if Length(B) > 0 then Result:= B[0]; end
  else begin var S: string:= F.AsString; if S <> '' then Result:= Ord(S[1]); end;
end;

procedure TBlueprint_ViewModel.SetTag(F: TField; AOrd: Integer);
begin
  if F = nil then Exit;
  if F is TBytesField then F.AsBytes:= TBytes.Create(Byte(AOrd))
  else F.AsString:= Chr(AOrd);
end;

procedure TBlueprint_ViewModel.AddOperation;
var
  NewOpID : Integer  ;
  NewOpNum: Integer  ;
  MaxNum  : Integer  ;
  BM      : TBookmark;
begin
  if not FMTOperation.Active then Exit;
  // Compute next Num for this folder (local scan of FMTOperation)
  MaxNum:= 0;
  BM:= FMTOperation.GetBookmark;
  FMTOperation.DisableControls;
  try
    FMTOperation.First;
    while not FMTOperation.Eof do begin if FMTOperation.FieldByName('NUM').AsInteger > MaxNum then MaxNum:= FMTOperation.FieldByName('NUM').AsInteger; FMTOperation.Next; end;
  finally
    if FMTOperation.BookmarkValid(BM) then FMTOperation.GotoBookmark(BM);
    FMTOperation.FreeBookmark(BM);
    FMTOperation.EnableControls;
  end;
  NewOpNum:= MaxNum + 1;

  if not ReserveNextID('GEN_OPERAT_ID', NewOpID) then begin Application.MessageBox('Failed to reserve new OPERAT ID via cmdNextID.', 'AddOperation', 0); Exit; end;

  FSuppressEvents:= True;
  FMTOperation.DisableControls;
  try
    FMTOperation.Append;
    FMTOperation.FieldByName('ID'      ).AsInteger:= NewOpID;
    FMTOperation.FieldByName('FLDRID'  ).AsInteger:= FFldrID;
    FMTOperation.FieldByName('NUM'     ).AsInteger:= NewOpNum;
    FMTOperation.FieldByName('SYSTEMOP').AsInteger:= 0;
    FMTOperation.Post;
  finally
    FMTOperation.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaOperation('AddOperation');

  // Seed a default group-visual characteristic for the new operation
  AppendCharGroups(FFldrID, NewOpID);
end; // procedure

procedure TBlueprint_ViewModel.AppendCharGroups(const FldrID: TSystID; const pID: TSystID);
var
  NewID   : Integer;
  OpNum   : Integer;
  OpNumStr: string ;
begin
  if not FMTFtrs.Active then Exit;
  // 2026-05-17 -- Idempotent: skip if a group-visual char already exists for
  // this operation. FTRTYPE is a TBytesField (D_BYTETAG, FIELD_AS_TYPE=AsByte)
  // so it CANNOT be a Locate key (raised "Invalid variant type or size for
  // field 'FTRTYPE'"). Scan instead, decoding the byte tag via TagOf. FMTFtrs
  // is master-detail filtered to the current operation, which is exactly the
  // scope we want to check.
  var BM: TBookmark:= FMTFtrs.GetBookmark;
  var Found: Boolean:= False             ;
  FMTFtrs.DisableControls;
  try
    FMTFtrs.First;
    while not FMTFtrs.Eof do
    begin
      if (FfFtrs_FldrID.AsInteger = FldrID) and (FfFtrs_OperID.AsInteger = pID) and (TagOf(FfFtrs_FtrType) = Ord(FtrType_GroupVisual)) then begin Found:= True; break; end;
      FMTFtrs.Next;
    end;
  finally
    if FMTFtrs.BookmarkValid(BM) then FMTFtrs.GotoBookmark(BM);
    FMTFtrs.FreeBookmark(BM);
    FMTFtrs.EnableControls;
  end; // try
  if Found then Exit;

  if FMTOperation.Locate('ID', pID, []) then begin OpNum:= FMTOperation.FieldByName('NUM').AsInteger; OpNumStr:= IntToStr(OpNum); end
  else OpNumStr:= '';

  if not ReserveNextID('GEN_MSCLIST_ID', NewID) then begin Application.MessageBox('Failed to reserve new MSCLIST ID via cmdNextID.', 'AppendCharGroups', 0); Exit; end;

  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    FMTFtrs.Append;
    FMTFtrs.FieldByName('ID'      ).AsInteger:= NewID;
    FMTFtrs.FieldByName('MASTERID').AsInteger:= NewID; // self-master (MASTERID = ID), matching the server group-visual seed
    FMTFtrs.FieldByName('FLDRID'  ).AsInteger:= FldrID;
    FMTFtrs.FieldByName('OPERID'  ).AsInteger:= pID;
    SetTag(tblFtrsNotation, Ord(SpecNotation_Spec));
    SetTag(tblFtrsSpecType, Ord(SpecType_Double  ));
    tblFtrsDimName .AsString:= 'GROUP';
    FMTFtrs.FieldByName('ATTRNAME').AsString:= 'A&G';
    FMTFtrs.FieldByName('ATTRTYPE').AsString:= 'GRP';
    FMTFtrs.FieldByName('ATTRCODE').AsString:= 'GRP';
    tblFtrsNum .AsString:= '0'; // 2026-05-17 MSCLIST.NUM is D_CHARNUM VARCHAR, not int
    SetTag(tblFtrsFtrType, Ord(FtrType_GroupVisual));
    tblFtrsFtrSuffix.AsString:= OpNumStr;
    FMTFtrs.Post;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end; // try
  SendDeltaFtrs('AppendCharGroups');
end; // procedure

procedure TBlueprint_ViewModel.DeleteOperation(const AID: Integer);
// Ask the server to delete the operation: cmdDeleteOperation guards on
// has-data, then in one transaction cascades the OPERAT delete (FK drops
// MSCLIST/GINSP/IINSP/INSPRSLT/etc.) AND deletes the operation's
// characteristics' PLANLIST plans (no orphan plans -- Rule 4). Only on rspOK
// is the local memtable row removed (with events suppressed: the server
// already committed the delete, so no SendDeltaOperation must follow).
begin
  if not FMTOperation.Active then Exit;
  if not FMTOperation.Locate('ID', AID, []) then Exit;
  if not ServerDeleteOperation(AID) then
  begin
    Application.MessageBox(PChar('Delete Operation failed: ' + FLastPersistError),
      'Delete Operation', 0);
    Exit;
  end;
  FSuppressEvents:= True;
  FMTOperation.DisableControls;
  try
    if FMTOperation.Locate('ID', AID, []) then FMTOperation.Delete;
  finally
    FMTOperation.EnableControls;
    FSuppressEvents:= False;
  end;
  // Server already committed the DELETE; no SendDeltaOperation here.
end;

{ ============================================================
  Copy Operation (cmdCopyOperation)
  ============================================================
  - Server-side command (uPipeSessionBuilder.HandleCopyOperation) does the
    full multi-table copy in one UpdateTransaction; the command boundary lets
    future non-Delphi clients reuse it.
  - pID    = SOURCE operation (the one picked from the Copy submenu).
  - target = the CURRENTLY-selected operation (FMTOperation cursor) -- this is
    the "new" operation the user just added and is sitting on.
  - pClass = severity threshold; server copies chars with FTRMCLASS<=ToInteger
    (CMC_Safety=0 strictest .. CMC_Minor=9 = everything).
  - After success: reload MSCLIST + PLANLIST, keep the target operation
    selected (master-detail re-filters chars to it), characteristics to top.
  ============================================================ }

procedure TBlueprint_ViewModel.ImportCopyOperation(const pID: Integer; const pClass: TCharMClass);
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
  TgtOp     : Integer           ;
begin
  if not (Assigned(FConn) and FConn.Connected) then begin Application.MessageBox('Copy Operation: pipe not connected.', 'Copy Operation', 0); Exit; end;
  if (not FMTOperation.Active) or FMTOperation.IsEmpty then begin Application.MessageBox('Select a target operation first.', 'Copy Operation', 0); Exit; end;
  TgtOp:= FMTOperation.FieldByName('ID').AsInteger;
  if pID = TgtOp then begin Application.MessageBox('Cannot import an operation into itself.', 'Copy Operation', 0); Exit; end;

  // Flush any in-flight char edit so the server copies a consistent source.
  if FMTFtrs.State in [dsEdit, dsInsert] then FMTFtrs.Post;
  if FMTFtrs.ChangeCount > 0 then SendDeltaFtrs('ImportCopyOperation(pre-flush)');

  Payload:= TEncoding.UTF8.GetBytes(Format('FLDRID=%d|SRCOP=%d|TGTOP=%d|MCLASS=%d', [FFldrID, pID, TgtOp, pClass.ToInteger]));
  GLE:= FConn.ExecuteCommand(cmdCopyOperation, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
  begin
    if Length(RspPayload) > 0 then Application.MessageBox(PChar('Copy Operation failed: ' + TEncoding.UTF8.GetString(RspPayload)), 'Copy Operation', 0)
    else Application.MessageBox(PChar(Format('Copy Operation failed (GLE=%d cmd=%d)', [GLE, Ord(TCommandID(RspHdr.CommandID))])), 'Copy Operation', 0);
    Exit;
  end;

  // ---- immediate refresh ---------------------------------------------------
  // MSCLIST is a detail of FMTOperation (MasterFields ID -> DetailFields
  // OPERID); reloading the whole folder then keeping the target op current
  // re-filters the grid to exactly the freshly-copied chars.
  LoadOneTable(FMTFtrs    , 'MSCLIST' , Format('FLDRID=%d', [FFldrID]));
  LoadOneTable(FMTPlanList, 'PLANLIST', Format('FLDRID=%d', [FFldrID]));
  FMTOperation.Locate('ID', TgtOp, []); // keep the "new" operation selected
  if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First; // characteristics jump to the top
  FRequireRefresh:= True;
end; // procedure

{ ============================================================
  VerifyAll (cmdVerifyFolder + [future] cmdPrePlanPreset)
  ============================================================
  The Paradox TBlueprint4_Model.VerifyAll was split into TWO server
  functions (concern separation)                                  :
    fn #1 cmdVerifyFolder -- folder cleanup core (the ppNone path):
       runs for EVERY call, no matter the preset.
    fn #2 cmdPrePlanPreset -- the APP<>ppNone engine (per-FtrMClass
       MSCLIST plan-field preset from station IPDef* defaults + PLANLIST
       plan create/load). NOT YET PORTED server-side (prereq: the
       inspection-plan subsystem). Wired as a TODO below so the menu
       variants that pass a non-ppNone preset still get the cleanup.
  Thin client: flush pending char edits, send cmdVerifyFolder, reload
  the affected tables so the grids reflect the server's changes.
  ============================================================ }
procedure TBlueprint_ViewModel.VerifyAll(const APP: TPrePlan);
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
begin
  if not (Assigned(FConn) and FConn.Connected) then begin Application.MessageBox('Verify Folder: pipe not connected.', 'Verify Folder', 0); Exit; end;
  if FFldrID <= 0 then begin Application.MessageBox('Verify Folder: no folder loaded.', 'Verify Folder', 0); Exit; end;

  // Flush any in-flight edits so the server verifies a consistent folder.
  if FMTFtrs.Active and (FMTFtrs.State in [dsEdit, dsInsert]) then FMTFtrs.Post;
  if FMTFtrs.Active and (FMTFtrs.ChangeCount > 0) then SendDeltaFtrs('VerifyAll(pre-flush)');
  if FMTOperation.Active and (FMTOperation.State in [dsEdit, dsInsert]) then FMTOperation.Post;
  if FMTOperation.Active and (FMTOperation.ChangeCount > 0) then SendDeltaOperation('VerifyAll(pre-flush)');

  Payload:= TEncoding.UTF8.GetBytes(Format('FLDRID=%d', [FFldrID]));
  GLE:= FConn.ExecuteCommand(cmdVerifyFolder, Payload, RspHdr, RspPayload);
  if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
  begin
    if Length(RspPayload) > 0 then Application.MessageBox(PChar('Verify Folder failed: ' + TEncoding.UTF8.GetString(RspPayload)), 'Verify Folder', 0)
    else Application.MessageBox(PChar(Format('Verify Folder failed (GLE=%d cmd=%d)', [GLE, Ord(TCommandID(RspHdr.CommandID))])), 'Verify Folder', 0);
    Exit;
  end;
  {$IFDEF DEBUG}
  if Length(RspPayload) > 0 then CodeSite.Send('VerifyAll server: ' + TEncoding.UTF8.GetString(RspPayload));
  {$ENDIF}

  // fn #2 -- the APP<>ppNone engine. cmdVerifyFolder cleanup ran above;
  // now preset the inspection-plan fields + create/clone plans server-side
  // (per-char by FtrMClass from the session station's SetupDefaults).
  if APP <> ppNone then
  begin
    Payload:= TEncoding.UTF8.GetBytes(Format('FLDRID=%d|APP=%d', [FFldrID, Ord(APP)]));
    GLE:= FConn.ExecuteCommand(cmdPrePlanPreset, Payload, RspHdr, RspPayload);
    if (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) then
    begin
      if Length(RspPayload) > 0 then Application.MessageBox(PChar('Pre-Plan Preset failed: ' + TEncoding.UTF8.GetString(RspPayload)), 'Verify Folder', 0)
      else Application.MessageBox(PChar(Format('Pre-Plan Preset failed (GLE=%d cmd=%d)', [GLE, Ord(TCommandID(RspHdr.CommandID))])), 'Verify Folder', 0);
      Exit;
    end;
    {$IFDEF DEBUG}
    if Length(RspPayload) > 0 then CodeSite.Send('PrePlanPreset server: ' + TEncoding.UTF8.GetString(RspPayload));
    {$ENDIF}
  end; // if

  // Server changed OPERAT/MSCLIST/PROCPARO -- refresh the visible tables.
  LoadOneTable(FMTOperation, 'OPERAT' , Format('FLDRID=%d', [FFldrID]));
  LoadOneTable(FMTFtrs     , 'MSCLIST', Format('FLDRID=%d', [FFldrID]));
  if FMTFtrs.Active and not FMTFtrs.IsEmpty then FMTFtrs.First;
  FRequireRefresh:= True;
end; // procedure

{ ============================================================
  Characteristic CRUD + FTR Load/Save
  ============================================================
  - LoadFtrRecord(ID): locate row in FMTFtrs, copy fields into FFTR.
    Covers the ~30 fields the form's UI actually displays/edits;
    other columns retain their defaults until referenced.
  - SaveFtrRecord(ID): mirror -- copy FFTR back into FMTFtrs row,
    Post -> cmdDelta saves to server.
  - AddCharacteristic: cmdNextID(GEN_MSCLIST_ID), append row with
    FtrType_Variable + sensible defaults inheriting current OPERID.
  - DeleteCharacteristic(AID): iterate, Locate, Delete; one cmdDelta
    sends all deletions in a batch.
  - EnterField / ApplyActiveField: active-field tracking for the
    "apply this value to selected chars" workflow.
  - RefreshFieldOrder: re-applies IndexFieldNames so the master-detail
    filter rebuilds after manual sort/reorder.
  ============================================================ }

procedure TBlueprint_ViewModel.LoadFtrRecord(const ID: Integer);
begin
  if not Assigned(FFTR) then Exit;
  if not FMTFtrs.Active then Exit;
  if not FMTFtrs.Locate('ID', ID, []) then Exit;
  // Identifiers
  FFTR.ID      := FfFtrs_ID      .AsLargeInt;
  FFTR.FldrID  := FfFtrs_FldrID  .AsLargeInt;
  FFTR.OPERID  := FfFtrs_OperID  .AsLargeInt;
  FFTR.MASTERID:= FfFtrs_MasterID.AsLargeInt;
  // Names / suffix
  FFTR.Num      := FfFtrs_Num      .AsString;
  FFTR.DIMNAME  := FfFtrs_DimName  .AsString;
  FFTR.DIMABBR  := FfFtrs_DimAbbr  .AsString;
  FFTR.DIMUNITS := FfFtrs_DimUnits .AsString;
  FFTR.FTRSUFFIX:= FfFtrs_FtrSuffix.AsString;
  FFTR.ATTRCODE:= FMTFtrs.FieldByName('ATTRCODE').AsString;
  FFTR.ATTRNAME:= FMTFtrs.FieldByName('ATTRNAME').AsString;
  FFTR.ATTRTYPE:= FMTFtrs.FieldByName('ATTRTYPE').AsString;
  // Spec
  FFTR.FtrType:= TFtrType(TagOf(FfFtrs_FtrType));
  FFTR.FTRCLASS:= TCharClass(TagOf(FMTFtrs.FieldByName('FTRCLASS')));
  FFTR.FTRMCLASS:= TCharMClass  (TagOf(FfFtrs_FtrMClass));
  FFTR.FTRQCLASS:= TCharQClass  (TagOf(FfFtrs_FtrQClass));
  FFTR.NOTATION := TSpecNotation(TagOf(FfFtrs_Notation ));
  FFTR.SPECTYPE := TSpecType    (TagOf(FfFtrs_SpecType ));
  FFTR.USL        := FfFtrs_USL        .AsFloat;
  FFTR.LSL        := FfFtrs_LSL        .AsFloat;
  FFTR.UPPERTOL   := FfFtrs_UpperTol   .AsFloat;
  FFTR.LOWERTOL   := FfFtrs_LowerTol   .AsFloat;
  FFTR.Nominal    := FfFtrs_Nominal    .AsFloat;
  FFTR.ORIGINALUSL:= FfFtrs_OriginalUSL.AsFloat;
  FFTR.ORIGINALLSL:= FfFtrs_OriginalLSL.AsFloat;
  FFTR.ZEROAT     := FfFtrs_ZeroAt     .AsFloat;
  FFTR.DECIMALS   := FfFtrs_Decimals   .AsInteger;
  // Math / flags
  FFTR.MATHLINE     := FfFtrs_MathLine     .AsString;
  FFTR.Notes        := FfFtrs_Notes        .AsString;
  FFTR.USEMATHLINE  := FfFtrs_UseMathLine  .AsBoolean;
  FFTR.FINDICATOR   := FfFtrs_Indicator    .AsBoolean;
  FFTR.FCONVERT     := FfFtrs_Convert      .AsBoolean;
  FFTR.INSPASVAR    := FfFtrs_InspAsVar    .AsBoolean;
  FFTR.ABSOLUTEVALUE:= FfFtrs_AbsoluteValue.AsBoolean;
  FFTR.GAGEPORTNMBR := FfFtrs_GagePortNmbr .AsInteger;
  FFTR.OPERORD      := FMTFtrs.FieldByName('OPERORD').AsInteger;
  // 2026-06-30 -- REVERTED: setting FTRCreated:=True here enabled LocalSaveFtr on
  // every record change, but LocalSaveFtr's GatherFTRRecord runs AFTER the grid
  // cursor has already scrolled to the NEW record, so it read the new record's
  // bound-field values and wrote them onto the OLD record (values bled between
  // records). The correct fix is to persist each unbound control's value into the
  // memtable ON CHANGE (as edtClass does) and drop LocalSaveFtr entirely -- to be
  // done carefully. Until then, DO NOT re-enable this without fixing LocalSaveFtr.
  // FFTRCreated:= True;
end; // procedure

procedure TBlueprint_ViewModel.SaveFtrRecord(const ID: Integer);
begin
  if not Assigned(FFTR) then Exit;
  if not FMTFtrs.Active then Exit;
  if not FMTFtrs.Locate('ID', ID, []) then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    FMTFtrs.Edit;
    // Identifiers -- ID/FLDRID/OPERID typically immutable, skip in normal save
    FfFtrs_MasterID.AsLargeInt:= FFTR.MASTERID;
    // Names / suffix
    FfFtrs_Num      .AsString:= FFTR.Num;
    FfFtrs_DimName  .AsString:= FFTR.DIMNAME;
    FfFtrs_DimAbbr  .AsString:= FFTR.DIMABBR;
    FfFtrs_DimUnits .AsString:= FFTR.DIMUNITS;
    FfFtrs_FtrSuffix.AsString:= FFTR.FTRSUFFIX;
    FMTFtrs.FieldByName('ATTRCODE').AsString:= FFTR.ATTRCODE;
    FMTFtrs.FieldByName('ATTRNAME').AsString:= FFTR.ATTRNAME;
    FMTFtrs.FieldByName('ATTRTYPE').AsString:= FFTR.ATTRTYPE;
    // Spec
    SetTag(FfFtrs_FtrType, Ord(FFTR.FtrType));
    SetTag(FMTFtrs.FieldByName('FTRCLASS'), Ord(FFTR.FTRCLASS));
    SetTag(FfFtrs_FtrMClass, Ord(FFTR.FTRMCLASS));
    SetTag(FfFtrs_FtrQClass, Ord(FFTR.FTRQCLASS));
    SetTag(FfFtrs_Notation , Ord(FFTR.NOTATION ));
    SetTag(FfFtrs_SpecType , Ord(FFTR.SPECTYPE ));
    FfFtrs_USL        .AsFloat  := FFTR.USL;
    FfFtrs_LSL        .AsFloat  := FFTR.LSL;
    FfFtrs_UpperTol   .AsFloat  := FFTR.UPPERTOL;
    FfFtrs_LowerTol   .AsFloat  := FFTR.LOWERTOL;
    FfFtrs_Nominal    .AsFloat  := FFTR.Nominal;
    FfFtrs_OriginalUSL.AsFloat  := FFTR.ORIGINALUSL;
    FfFtrs_OriginalLSL.AsFloat  := FFTR.ORIGINALLSL;
    FfFtrs_ZeroAt     .AsFloat  := FFTR.ZEROAT;
    FfFtrs_Decimals   .AsInteger:= FFTR.DECIMALS;
    // Math / flags
    FfFtrs_MathLine     .AsString := FFTR.MATHLINE;
    FfFtrs_Notes        .AsString := FFTR.Notes;
    FfFtrs_UseMathLine  .AsBoolean:= FFTR.USEMATHLINE;
    FfFtrs_Indicator    .AsBoolean:= FFTR.FINDICATOR;
    FfFtrs_Convert      .AsBoolean:= FFTR.FCONVERT;
    FfFtrs_InspAsVar    .AsBoolean:= FFTR.INSPASVAR;
    FfFtrs_AbsoluteValue.AsBoolean:= FFTR.ABSOLUTEVALUE;
    FfFtrs_GagePortNmbr .AsInteger:= FFTR.GAGEPORTNMBR;
    FMTFtrs.FieldByName('OPERORD').AsInteger:= FFTR.OPERORD; // Custom Order
    FMTFtrs.Post;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end; // try
  SendDeltaFtrs('SaveFtrRecord');
end; // procedure

procedure TBlueprint_ViewModel.AddCharacteristic;
begin
  AddCharacteristic(Ord(FtrType_Variable));
end; // procedure

procedure TBlueprint_ViewModel.AddCharacteristic(const AFtrType: Integer);
var
  NewID     : Integer;
  CurrOperID: Integer;
begin
  if (not FMTFtrs.Active) or (not FMTOperation.Active) or FMTOperation.IsEmpty then Exit;
  CurrOperID:= FMTOperation.FieldByName('ID').AsInteger;
  if not ReserveNextID('GEN_MSCLIST_ID', NewID) then begin Application.MessageBox('AddCharacteristic: failed to reserve MSCLIST.ID', 'Add failed', 0); Exit; end;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    FMTFtrs.Append;
    FfFtrs_ID      .AsLargeInt:= NewID;
    FfFtrs_MasterID.AsLargeInt:= NewID; // self-master (MASTERID = ID) -- else HandleVerifyFolder's orphan sweep deletes it
    FfFtrs_FldrID  .AsLargeInt:= FFldrID;
    FfFtrs_OperID  .AsLargeInt:= CurrOperID;
    SetTag(FfFtrs_FtrType , AFtrType            );
    SetTag(FfFtrs_Notation, Ord(SpecNotation_Spec));
    SetTag(FfFtrs_SpecType, Ord(SpecType_Double  ));
    FfFtrs_Decimals.AsInteger:= 4;
    FMTFtrs.Post;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  SendDeltaFtrs('AddCharacteristic');
  LoadFtrRecord(NewID              );
end; // procedure

function TBlueprint_ViewModel.ServerDeleteCharacteristic(AID: Integer): Boolean;
// Send cmdDeleteCharacteristic to the server for one MSCLIST row.
// Returns True only when the server replies rspOK.
// On any failure sets FLastPersistError and returns False (conservative:
// the local memtable row is NOT removed so the UI stays consistent).
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
begin
  Result:= False;
  if (AID <= 0) or not (Assigned(FConn) and FConn.Connected) then
  begin
    FLastPersistError:= 'ServerDeleteCharacteristic: not connected';
    Exit;
  end;
  Payload:= TEncoding.UTF8.GetBytes(Format('CHARID=%d', [AID]));
  GLE:= FConn.ExecuteCommand(cmdDeleteCharacteristic, Payload, RspHdr, RspPayload);
  if (GLE = ERROR_SUCCESS) and (TCommandID(RspHdr.CommandID) = rspOK) then
    Result:= True
  else
  begin
    if Length(RspPayload) > 0 then
      FLastPersistError:= TEncoding.UTF8.GetString(RspPayload)
    else
      FLastPersistError:= Format('ServerDeleteCharacteristic: GLE=%d', [GLE]);
  end;
end; // function

function TBlueprint_ViewModel.ServerDeleteOperation(AID: Integer): Boolean;
// Send cmdDeleteOperation to the server for one OPERAT row.
// Returns True only when the server replies rspOK (it has then guarded on
// has-data, cascaded the delete and cleaned up the plans). On any failure
// sets FLastPersistError and returns False (the local row is NOT removed).
var
  Payload   : TBytes            ;
  RspPayload: TBytes            ;
  RspHdr    : TPipeMessageHeader;
  GLE       : DWORD             ;
begin
  Result:= False;
  if (AID <= 0) or not (Assigned(FConn) and FConn.Connected) then
  begin
    FLastPersistError:= 'ServerDeleteOperation: not connected';
    Exit;
  end;
  Payload:= TEncoding.UTF8.GetBytes(Format('OPERID=%d', [AID]));
  GLE:= FConn.ExecuteCommand(cmdDeleteOperation, Payload, RspHdr, RspPayload);
  if (GLE = ERROR_SUCCESS) and (TCommandID(RspHdr.CommandID) = rspOK) then
    Result:= True
  else
  begin
    if Length(RspPayload) > 0 then
      FLastPersistError:= TEncoding.UTF8.GetString(RspPayload)
    else
      FLastPersistError:= Format('ServerDeleteOperation: GLE=%d', [GLE]);
  end;
end; // function

procedure TBlueprint_ViewModel.DeleteCharacteristic(AID: TArray<Integer>);
// Per-id: ask the server to delete (double-check + cascade in one transaction).
// Only on rspOK remove the local memtable row so the grid stays consistent.
// The server already deleted from DB; no SendDeltaFtrs needed.
var
  I: Integer;
begin
  if Length(AID) <= 0 then Exit;
  if not FMTFtrs.Active then Exit;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(AID) to high(AID) do
      if ServerDeleteCharacteristic(AID[I]) then
        if FMTFtrs.Locate('ID', AID[I], []) then FMTFtrs.Delete;
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end;
  // Server already committed the DELETE; no SendDeltaFtrs here.
end;

procedure TBlueprint_ViewModel.EnterField(const AFieldName: string);
begin
  // 2026-05-17 -- Resolve the full EditFields record so FActiveField drives
  // NextField/PriorField (ported from OLD SetEditField/EnterField). FEditField
  // kept in sync for ApplyActiveField's AsVariant copy.
  FActiveField:= FieldByName(AFieldName);
  FEditField:= FActiveField;
end;

procedure TBlueprint_ViewModel.ApplyActiveField(AID: TArray<Integer>);
var
  I       : Integer;
  SrcID   : Integer;
  SrcField: TField ;
  DstField: TField ;
begin
  // Apply the value of the currently-focused field (FEditField) on the
  // current FMTFtrs row to each char in AID. Minimal impl using FieldByName;
  // skips if no active field or empty selection.
  if Length(AID)      = 0 then Exit;
  if FEditField.Field = '' then Exit;
  if not FMTFtrs.Active then Exit;
  SrcField:= FMTFtrs.FindField(FEditField.Field);
  if SrcField = nil then Exit;
  SrcID:= FfFtrs_ID.AsInteger;
  FSuppressEvents:= True;
  FMTFtrs.DisableControls;
  try
    for I:= low(AID) to high(AID) do
    begin
      if AID[I] = SrcID then Continue;
      if not FMTFtrs.Locate('ID', AID[I], []) then Continue;
      DstField:= FMTFtrs.FindField(FEditField.Field);
      if DstField = nil then Continue;
      FMTFtrs.Edit;
      DstField.AsVariant:= SrcField.AsVariant;
      FMTFtrs.Post;
    end;
    FMTFtrs.Locate('ID', SrcID, []);
  finally
    FMTFtrs.EnableControls;
    FSuppressEvents:= False;
  end; // try
  SendDeltaFtrs('ApplyActiveField');
end; // procedure

procedure TBlueprint_ViewModel.RefreshFieldOrder;
var
  I: Integer;
begin
  // 2026-05-17 -- Ported from Blueprint4.Model.pas.OLD. Rebuilds the Tab/Enter
  // jump order to match the current Spec/Notation state: Spec notation walks
  // USL(+LSL if Double); Tolerance notation walks Nominal/Upper(+Lower if
  // Double); then the fixed RestOfThem tail. (The prior stub mis-used this to
  // poke IndexFieldNames -- master-detail is wired in BuildSchema, a separate
  // concern. CMDialogKey calls this expecting the jump order.)
  FieldOrder[0]:= 'edtName';
  FieldOrder.Length:= 1;
  if FCNotation                                                                            = SpecNotation_Spec then begin FieldOrder.Add(['btnNotationSpec', 'edtUSL']); if FCSpec = SpecType_Double then FieldOrder.Add(['edtLSL']); end
  else begin FieldOrder.Add(['btnNotationTolerance', 'edtNominal', 'edtUpper']); if FCSpec = SpecType_Double then FieldOrder.Add(['edtLower']); end;
  FieldOrder.Add(RestOfThem);
  for I:= 0 to FieldOrder.Count - 1 do FieldOrder[I]:= FieldOrder[I].ToUpper.Trim;
end; // procedure

procedure TBlueprint_ViewModel.ExtractActiveFieldValue(out AStr: string; out AINT: Integer; out AFloat: double; out ABool: Boolean);
var
  EditDBName: string;
  EditName  : string;
  XField    : TField;
begin
  {$IFDEF TRACE_BP}CodeSite.TraceMethod(Self, 'ExtractActiveFieldValue', tmoTiming); {$ENDIF}
  AStr:= '';
  AINT  := - 1;
  AFloat:= - 1;
  EditName:= FActiveField.Field.ToUpper; // EditFields[FActiveFieldIdx].Field.ToUpper;
  if FActiveField.idx = NonFtrField then raise Exception.CreateFmt('TBlueprint4_Model.ExtractActiveFieldValue ERROR Edit Field <%s> not found.', [FActiveField.Field]);
  EditDBName:= FActiveField.DBField.ToUpper; // EditFields[FActiveFieldIdx].DBField.ToUpper;
  // TFieldType = (ftUnknown, ftString, ftSmallint, ftInteger, ftWord, // 0..4
  // ftBoolean, ftFloat, ftCurrency, ftBCD, ftDate, ftTime, ftDateTime, // 5..11
  // ftBytes, ftVarBytes, ftAutoInc, ftBlob, ftMemo, ftGraphic, ftFmtMemo, // 12..18
  // ftParadoxOle, ftDBaseOle, ftTypedBinary, ftCursor, ftFixedChar, ftWideString, // 19..24
  // ftLargeint, ftADT, ftArray, ftReference, ftDataSet, ftOraBlob, ftOraClob, // 25..31
  // ftVariant, ftInterface, ftIDispatch, ftGuid, ftTimeStamp, ftFMTBcd, // 32..37
  // ftFixedWideChar, ftWideMemo, ftOraTimeStamp, ftOraInterval, // 38..41
  // ftLongWord, ftShortint, ftByte, ftExtended, ftConnection, ftParams, ftStream, //42..48
  // ftTimeStampOffset, ftObject, ftSingle); //49..51
  XField:= tblFtrs.FieldByName(EditDBName);
  if not Assigned(XField) then raise Exception.CreateFmt('TBlueprint4_Model.ExtractActiveFieldValue ERROR Field <%s> <%s> not found.', [EditName, EditDBName]);
  if XField.DataType in [ftString, ftFixedChar, ftWideString, ftMemo, ftFmtMemo, ftFixedWideChar, ftWideMemo] then AStr:= XField.AsString
  else if XField.DataType in [ftSmallint, ftInteger, ftWord, ftLargeint, ftLongWord, ftShortint, ftByte] then AINT:= XField.AsInteger
  else if XField.DataType in [ftFloat, ftCurrency, ftBCD, Data.DB.ftExtended, Data.DB.ftSingle] then AFloat:= XField.AsFloat
  else if XField.DataType in [ftBoolean] then ABool:= XField.AsBoolean
  else raise Exception.CreateFmt('TBlueprint4_Model.ExtractActiveFieldValue ERROR Field <%s> <%s> has unknown data type.', [EditName, EditDBName]);
  if Assigned(XField) then CodeSite.Send(
    csmGreen, 'TBlueprint4_Model.ExtractActiveFieldValue  ID=%d; NUM=<%s> MCLASS=%d  Extracted <%s> <%s> %s= <%s> %d %f',
    [ tblFtrsID.AsInteger, tblFtrsNum.AsString, TagOf(tblFtrsFtrMClass), EditDBName, XField.AsString, GetEnumName(TypeInfo(TFieldType), Ord(XField.DataType)), AStr, AINT, AFloat]);
end; // procedure

procedure TBlueprint_ViewModel.AssignActiveFieldValue(const AStr: string; const AINT: Integer; const AFloat: double; const ABool: Boolean);
var
  EditDBName: string;
  EditName  : string;
  XField    : TField;
begin
  {$IFDEF TRACE_BP}CodeSite.TraceMethod(Self, 'AssignActiveFieldValue', tmoTiming); {$ENDIF}
  EditName:= FActiveField.Field.ToUpper; // EditFields[FActiveFieldIdx].Field.ToUpper;
  if FActiveField.idx = NonFtrField then raise Exception.CreateFmt('TBlueprint4_Model.AssignActiveFieldValue ERROR Edit Field <%s> not found.', [FActiveField.Field]);
  EditDBName:= FActiveField.DBField.ToUpper; // EditFields[FActiveFieldIdx].DBField.ToUpper;
  XField:= tblFtrs.FieldByName(EditDBName);
  if not Assigned(XField) then raise Exception.CreateFmt('TBlueprint4_Model.AssignActiveFieldValue ERROR Field <%s> <%s> not found.', [EditName, EditDBName]);
  {
    if EditName = 'btnSpecDouble'.ToUpper then
    begin

    end
}
  if XField.DataType in [ftString, ftFixedChar, ftWideString, ftMemo, ftFmtMemo, ftFixedWideChar, ftWideMemo] then XField.AsString:= AStr
  else if XField.DataType in [ftSmallint, ftInteger, ftWord, ftLargeint, ftLongWord, ftShortint, ftByte] then XField.AsInteger:= AINT
  else if XField.DataType in [Data.DB.ftFloat, ftCurrency, ftBCD, Data.DB.ftExtended, Data.DB.ftSingle] then XField.AsFloat:= AFloat
  else if XField.DataType in [ftBoolean] then XField.AsBoolean:= ABool
  else raise Exception.CreateFmt('TBlueprint4_Model.AssignActiveFieldValue ERROR Field <%s> <%s> has unknown data type.', [EditName, EditDBName]);
  CodeSite.Send(
    csmGreen, 'TBlueprint4_Model.AssignActiveFieldValue  ID=%d; NUM=<%s>; MCLASS=%d ASSIGNED  EditDBName=%s/%s; XField.AsString=%s; ASTR=<%s> AINT=%d',
    [tblFtrsID.AsInteger, tblFtrsNum.AsString, TagOf(tblFtrsFtrMClass), EditDBName, GetEnumName(TypeInfo(TFieldType), Ord(XField.DataType)), XField.AsString, AStr, AINT]);
end; // procedure

procedure TBlueprint_ViewModel.FtrsOnFilterRecord(DataSet: TDataSet; var Accept: Boolean);
var
  F: TField;
begin
  F:= DataSet.FindField('FTRTYPE');
  Accept:= (F = nil) or (TagOf(F) in [Ord(FtrType_Variable), Ord(FtrType_Attribute)]);
end;

end.

