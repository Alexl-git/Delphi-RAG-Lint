unit ConvRules.MainForm;

{ ConvRulesEditor main window -- built entirely in code (no .dfm), plain VCL, no
  DevExpress. This is the v1 core loop:

    Load a conversion.rules file  ->  see its #convert rules in a library list with
    a % complete column  ->  select one to load the 3-column mapping grid (From /
    To-assigned / To-unassigned pool)  ->  assign/unassign properties  ->  Save
    (writes a .bak backup, re-emits canonical DSL, runs convert-validate).

  The property trees behind the grid come from the engine adapter (drag-lint
  proptree). All model edits go through TRuleBook so the DSL file stays the single
  source of truth. Directive tabs + a raw-DSL view expose the full grammar. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , Winapi.Windows
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.CheckLst
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , Vcl.Grids
  , Vcl.Dialogs
  , Vcl.Menus
  , Vcl.Graphics
  , Vcl.Themes
  , ConvRules.Model
  , ConvRules.Casts
  , ConvRules.Engine
  , ConvRules.Platform
  , DRagLint.Convert.CastLib
  , ConvRules.ConvCatalog
  , ConvRules.Theme
  , ConvRules.OpenSourceClient
  , ConvRules.Mappings
  , ConvRules.MappingForm
  , ConvRules.FormTypes
  , ConvRules.RuleCatalog
  , ConvRules.Usage // TUsedUnitRef: a field's type, so this has to be INTERFACE-visible
  ;

const
  /// <summary>HKCU key holding this editor's per-user settings.</summary>
  EDITOR_REG_KEY = 'Software\DragLint\ConvRulesEditor';
  /// <summary>Value under EDITOR_REG_KEY holding the theme preference token
  /// (see ConvRules.Theme.ThemePrefToStr). The .dpr reads it at start-up; the
  /// View &gt; Theme menu writes it back.</summary>
  EDITOR_REG_THEME = 'Theme';
  /// <summary>Value under EDITOR_REG_KEY holding the folder the form-file Open
  /// dialog last started in, so browsing resumes where the user left off rather
  /// than at the process working directory.</summary>
  /// <remarks>Seeded by --form on the command line, then updated by every
  /// successful browse. A missing or stale folder is harmless: TOpenDialog falls
  /// back on its own when InitialDir does not exist.</remarks>
  EDITOR_REG_FORMDIR = 'LastFormDir';

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (ConvRulesEditor.dpr)</para>
  /// <para>Used in units: ConvRulesEditor</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TConvRulesForm = class(TForm)
    private
      FBook     : TRuleBook     ;
      FEngine   : TEngineAdapter;
      FFilePath : string        ;
      FActiveHdr: Integer       ; // index of the selected #convert node (-1 none)
      FFromTree : TProptree     ; // active F property tree
      FToTree   : TProptree     ; // active T property tree

      FFromClasses: TArray<string>; // FROM picker: all TComponent descendants (Win32+Win64 union)
      FToClasses  : TArray<string>; // TO picker: TControl descendants (target platform)
      FUnitsLoaded: Boolean       ; // project-unit picker populated?

      FFromPlatform: TConvPlatform; // FROM picker library platform
      FToPlatform  : TConvPlatform; // TO picker library platform

      FThemeMode    : TThemeMode                    ; // mode currently applied (drives GridDrawCell)
      FMnuTheme     : array[TThemePref] of TMenuItem; // View > Theme radio items
      FStatusIsError: Boolean                       ; // last status was SetError (red bold)

      // action toolbar -- ONE grouped TToolBar owns every action that used to be a
      // loose TButton scattered over the top panel, the pool panel, the grid filter
      // bar and the Unit Rules tab. Only the buttons UpdateToolbarEnabled gates, or
      // whose caption flips at runtime, need a field; the rest are wired and dropped.
      FToolbar       : TToolBar   ;
      FTbAssign      : TToolButton; // mapping: assign the pool leaf to the grid row
      FTbUnassign    : TToolButton; // mapping: drop the selected row's assignment
      FTbFindInFrom  : TToolButton; // mapping: select the same-named From row
      FTbOnlyType    : TToolButton; // mapping: pool type-narrowing toggle (caption flips)
      FTbMappings    : TToolButton; // mapping: open the conditional #mapping editor
      FTbExamine     : TToolButton; // examine: pick .dfm/.pas, mark used From props
      FTbClearExamine: TToolButton; // examine: drop the current examination
      FPanelTop      : TPanel     ;
      FLblFile       : TLabel     ;
      FLblStatus     : TLabel     ;
      FStatusBar     : TStatusBar ; // bottom-of-form status (mirrors FLblStatus)
      // new-conversion row
      FCbFrom       : TComboBox       ;
      FCbTo         : TComboBox       ;
      FCbUnit       : TComboBox       ; // From Unit picker (project units)
      FCbFromPlat   : TComboBox       ; // FROM platform (Win32/Win64/Both)
      FCbToPlat     : TComboBox       ; // TO platform
      FCbSurface    : TComboBox       ; // target surface: DFM (published) | PAS (public + fields)
      FSurfaceMinVis: string          ; // '' | 'published' | 'public' -- proptree --min-visibility
      FCastDefs     : TArray<TCastDef>; // shipped class-cast library (.castlib)
    { The ENUM half of the same file. LoadCastLib returns only the casts, so the
      enum blocks were parsed and thrown away; the conversion catalog needs them
      to offer an enum target (TabcButtonLayout -> TdxButtonLayout). }
    FEnumDefs     : TArray<TEnumDef>;
    { Targets the SELECTED From row could convert to. Populated on row change --
      see RefreshConvOptions. Read-only: it answers "what is possible", the pool
      above it is still where a target is chosen. }
    FConvList     : TListBox;
    FLblConv      : TLabel;
      // rules library
      FRules : TListView;
      // grid
      FGrid        : TStringGrid   ; // col0 From, col1 To-assigned, col2 cast
      FGridFindFrom: TEdit         ; // grid filter: From column substring
      FGridFindTo  : TEdit         ; // grid filter: To column substring
      FLblGridMatch: TLabel        ; // "N of M" count shown while a grid filter is active
      FUsedProps   : TArray<string>; // Examine result; empty = no examination active
      FUsedFiles   : TArray<string>; // the examined file set, retained for the session
      FExamineInfo : string        ; // status summary, re-shown when blocks change
      // Units harvested from the examined .pas files (ConvRules.Usage.ScanUsesClauses).
      // CANDIDATES ONLY -- never rules: RefreshUnitList shows them as extra rows under
      // the real #use/#unuse/#useswap ones and nothing here touches FBook, so an Examine
      // can never dirty the rule book. Filtered against the current rules at DISPLAY
      // time, so authoring a rule for one makes its candidate row go away by itself.
      FUnitCandidates: TArray<string>;
      // The SAME harvest, carrying the clause each unit was written in, so the Unit
      // Rules tab can mark interface vs implementation. Kept alongside the flat array
      // rather than replacing it: FUnitCandidates is what the derive/check paths
      // filter on, and both are written from one scan so they cannot drift.
      FUsedUnitRefs: TArray<TUsedUnitRef>;
      // --- form-types panel (leftmost): what is ON the examined form(s) ---
      // FFormTypeRows is the decorated model the list paints; ScanDfmTypes fills
      // TypeName/Count and RefreshFormTypes applies Visual/Ruled on top.
      // Skipped is the user's per-row mark and is preserved ACROSS a refilter and a
      // re-scan, which is the whole reason the mark lives on the row and is not
      // recomputed.
      FFormTypeList : TCheckListBox; // owner-drawn checklist: dfm [V] TOvcTable  (28)
      FFormTypeRows : TFormTypeRows;
      // List index -> FFormTypeRows index. The list shows only the rows the search
      // box leaves visible, so the two are NOT the same number. Every handler must
      // go through SelectedRowIndex; indexing FFormTypeRows with ItemIndex directly
      // addresses the wrong class the moment a search is active.
      FVisibleRows  : TArray<Integer>;
      FFilterMemo   : TMemo        ; // one exclusion regex per line
      FChkStdCtrls  : TCheckBox    ; // also exclude Vcl./FMX. declared types
      FLblFormTypes : TLabel       ; // "N types, M shown"
      FFilterError  : string       ; // first malformed regex, surfaced in the label
      FSelectedFormType: string    ; // type selected in FFormTypeList (filter FRules to this type)
      FCatalog      : TRuleCatalog ; // every #convert the rules folder already has
      // Types claimed by MORE THAN ONE rule. A rule lives in exactly one
      // file; two claims mean two versions waiting to diverge, so the panel must
      // say so rather than let FindRuleForType silently pick the first.
      FCatalogDups : TCatalogDuplicates;
      { The scanned rules folder. PER-SESSION ONLY -- it is written by
      RescanRulesFolder and never read back from the registry, so it starts EMPTY
      on every launch. It said "registry-backed" until 2026-09-09; that comment is
      why the --form startup gap was easy to miss, because it implied the folder
      survived a restart and the marking would work from the second run on. It does
      not, and it did not. }
      FRulesFolder : string;
      FLastFormDir : string; // where the Open-form dialog resumes
      // Three descendant sets, fetched ONCE each (~1.5 s per call, measured against
      // the 3.4 GB Win32 library). They replace a per-type DeclaringUnitOf, which
      // costs 1.7 s PER TYPE and blocked the UI for ~78 s on VARINSP's 46 types.
      FVisualSet    : TStringList                ; // TControl descendants    -> [V]
      FComponentSet : TStringList                ; // TComponent descendants  -> [N] when not TControl
      FPersistentSet: TStringList                ; // TPersistent descendants -> [N] (catches TField)
      FDeclUnits    : TDictionary<string, string>; // type -> declaring unit, memoised
      FPool         : TListBox                   ; // unassigned T pool
      FPoolFind     : TEdit                      ;
      // "Go to definition of <T>": ONE popup shared by the grid and the pool, because
      // both show cells in the same 'Path : Type' shape and TypeOfCell reads either.
      // PopupComponent tells the handler which control was clicked.
      FTypePopup     : TPopupMenu;
      FMnuGotoDef    : TMenuItem ;
      FCtxType       : string    ; // the type under the cursor when the menu opened
      FPoolTypeFilter: string    ; // active pool type-narrowing ('' = off)
      // directives / raw
      FTabs : TPageControl;
      FRaw  : TMemo       ;
      // unit rules tab + rules-library filter
      FUnitList   : TListView;
      FRulesFilter: TEdit    ;

      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.BuildMenu, ConvRules.MainForm.TConvRulesForm.BuildToolbar, ConvRules.MainForm.TConvRulesForm.BuildTypePopup, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled, TLabel</para>
      /// <para>Reads: FStatusBar, FPanelTop, FLblStatus, FCbUnit, FCbSurface, FCbFrom, FCbTo, FCbFromPlat (+19 more)   Writes: FStatusBar, FPanelTop, FLblStatus, FCbUnit, FCbSurface, FCbFrom, FCbTo, FCbFromPlat (+17 more)</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildMenu"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildToolbar"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildTypePopup"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildUI;
      { Builds the single top-aligned action toolbar. Called from BuildUI right after
      the menu, so its strip is claimed before the panels below take the client
      area. Every TToolButton.OnClick points at the SAME handler the loose TButton
      it replaced used -- no handler body was copied. }
      /// <summary><!-- drag-lint:auto sum -->Builds the single top-aligned action toolbar.
      /// Called from BuildUI right after the menu, so its strip is claimed before the
      /// panels below take the client area. Every TToolButton.OnClick points at the SAME
      /// handler the loose TButton it replaced used -- no handler body was copied.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.BuildUI (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.BuildToolbar.AddBtn, ConvRules.MainForm.TConvRulesForm.BuildToolbar.AddSep</para>
      /// <para>Reads: FToolbar   Writes: FToolbar, FTbAssign, FTbUnassign, FTbFindInFrom, FTbOnlyType, FTbMappings, FTbExamine, FTbClearExamine</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildToolbar.AddBtn"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildToolbar.AddSep"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildToolbar;
      { Enables only what the current selection supports; see the implementation for
      why the always-enabled-then-complain behaviour was worth replacing. }
      /// <summary><!-- drag-lint:auto sum -->Enables only what the current selection
      /// supports; see the implementation for why the always-enabled-then-complain
      /// behaviour was worth replacing.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.BuildUI (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoClearExamine (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoDeleteUnit (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoUnassign (ConvRules.MainForm.pas) (+5 more)</para>
      /// <para>Reads: FTbAssign, FActiveHdr, FGrid, FPool, FTbUnassign, FTbFindInFrom, FTbExamine, FTbClearExamine (+3 more)</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure UpdateToolbarEnabled;
      { FGrid.OnSelectCell -- re-gates the toolbar when the grid row changes. Never
      vetoes (CanSelect is left alone). }
      /// <summary><!-- drag-lint:auto sum -->FGrid.OnSelectCell -- re-gates the toolbar
      /// when the grid row changes. Never vetoes (CanSelect is left alone).</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ARow"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="CanSelect"><!-- drag-lint:auto type -->var Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    /// <summary>Fill the conversion catalog list for the From property on ARow.</summary>
    /// <param name="ARow">Grid row; &lt; 1 or past the end clears the list.</param>
    /// <remarks>Read-only. Pass OnSelectCell's ARow, not FGrid.Row -- the grid has
    /// not committed the move when that event fires.</remarks>
    procedure RefreshConvOptions(ARow: Integer);
      { FPool.OnClick -- re-gates the toolbar when the pool highlight changes. }
      /// <summary><!-- drag-lint:auto sum -->FPool.OnClick -- re-gates the toolbar when the
      /// pool highlight changes.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PoolSelectionChanged(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="Action"><!-- drag-lint:auto type -->var TCloseAction</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Mutates: Action (var)</para>
      /// <para>UI thread only -- touches Application</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormCloseHandler(Sender: TObject; var Action: TCloseAction);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadFile</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFile"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoLoad(Sender: TObject);
      /// <summary>Back the file up, write the canonical DSL, validate it and report.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <returns>True when the file was written; False when nothing reached disk --
      /// the backup failed, or no target file was chosen. The status bar always
      /// carries the reason.</returns>
      /// <remarks>
      /// A Boolean, not a procedure, because DoCurate must NOT open the
      /// curation window (which reads the file from DISK and can later force a reload
      /// over the editor's buffer) after a save the user asked for and did not get.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoCurate (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoSaveClick (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.OpenOwningRule (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ValidateText, ConvRules.MainForm.TConvRulesForm.RefreshFormTypes, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.RescanRulesFolder, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Model.TRuleBook.SaveCompleteToString, ConvRules.Units.NormalizeUnitSets, ConvRules.WorkingSet.BackupPath, ExtractFileName, Format, Trim</para>
      /// <para>Returns: False; True</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 94 lines (full implementation)</para>
      /// <para>Reads: FFilePath, FLblFile, FBook, FActiveHdr, FEngine, FFormTypeRows, FLblStatus   Writes: FFilePath</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ValidateText"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RescanRulesFolder"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DoSave(Sender: TObject): Boolean;
      /// <summary>OnClick shim for the Save button -- an event handler must be a
      /// procedure, so the result is dropped here and nowhere else.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.DoSave</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoSave"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoSaveClick(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ValidateText, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Model.TRuleBook.SaveToString</para>
      /// <para>Reads: FFilePath, FActiveHdr, FBook, FEngine</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ValidateText"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.SaveToString"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoValidate(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Open the curation window on the file currently
      /// loaded here. Curation moves VERBATIM block text and deliberately does NOT go
      /// through this form's canonical re-emitter, so a block that was merely moved stays
      /// byte-identical. It works on the file ON DISK, so unsaved edits here are invisible
      /// to it: Yes = save first, No = curate the on-disk version anyway, Cancel = out.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.CurationForm.TCurationForm.Execute, ConvRules.MainForm.TConvRulesForm.DoSave, ConvRules.MainForm.TConvRulesForm.LoadFile, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ExtractFileName, MessageDlg</para>
      /// <para>Reads: FFilePath, FBook, FFormTypeRows</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.CurationForm.TCurationForm.Execute"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoSave"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFile"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoCurate(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.GetProptree, ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule, ConvRules.MainForm.TConvRulesForm.DoAutoMatch, ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.Model.TRuleBook.Add, Default, Format, Integer, SameText, Trim</para>
      /// <para>Complexity: 19 (cyclomatic, outer body), 92 lines (full implementation)</para>
      /// <para>Reads: FCbFrom, FCbTo, FEngine, FActiveHdr, FBook, FRules</para>
      /// <para>UI thread only -- touches Application</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.GetProptree"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoAutoMatch"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadGridForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoNewConversion(Sender: TObject);
      /// <summary>Decides WHERE a new rule should be written, prompting as needed.</summary>
      /// <param name="AFrom">From type, already resolved.</param>
      /// <param name="ATo">To type, already resolved.</param>
      /// <param name="ACompletingStub">True when the selected rule is a From-only stub
      /// for AFrom -- finishing that is not authoring a second rule, so both prompts
      /// are skipped.</param>
      /// <returns>True to go on creating the rule in the current book, whose FFilePath
      /// may by then point at a fresh rule file. False when the caller must abandon: the user
      /// cancelled, or was routed to the existing rule instead.</returns>
      /// <remarks>
      /// Split out of DoNewConversion so that routine keeps one exit for this
      /// whole decision. Everything here is prompting and bookkeeping; no rule is
      /// created and no file is written -- the unchanged save path does that.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoNewConversion (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.DoSave, ConvRules.MainForm.TConvRulesForm.OpenOwningRule, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.RescanRulesFolder, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Model.TRuleBook.Clear, ConvRules.RuleCatalog.FindRuleForType, ConvRules.RuleCatalog.RuleFileNameFor (+6 more)</para>
      /// <para>Returns: False; True</para>
      /// <para>Complexity: 18 (cyclomatic, outer body), 100 lines (full implementation)</para>
      /// <para>Reads: FCatalog, FCbFrom, FRulesFolder, FFilePath, FBook, FLblFile   Writes: FFilePath, FActiveHdr</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoSave"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.OpenOwningRule"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RescanRulesFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ChooseTargetForNewRule(const AFrom, ATo: string; ACompletingStub: Boolean): Boolean;
      /// <summary><!-- drag-lint:auto sum -->Auto-Match: for every UNassigned From leaf, if
      /// exactly ONE unassigned To leaf matches by leaf-name (case-insensitive) AND is
      /// castable, create the #link. Skips ambiguous names (more than one candidate) so the
      /// user resolves those by hand.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoNewConversion (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Casts.ResolveUnknownTypes, ConvRules.MainForm.TConvRulesForm.AssignLink, ConvRules.MainForm.TConvRulesForm.CanCast, ConvRules.MainForm.TConvRulesForm.DoAutoMatch.LeafName, ConvRules.MainForm.TConvRulesForm.FindLinkForFrom, ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.Mappings.ConditionalCasesOf (+6 more)</para>
      /// <para>Complexity: 19 (cyclomatic, outer body), 114 lines (full implementation)</para>
      /// <para>Reads: FActiveHdr, FToTree, FFromTree</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Casts.ResolveUnknownTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.CanCast"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoAutoMatch.LeafName"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.FindLinkForFrom"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoAutoMatch(Sender: TObject);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoLoadUnit (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoMappings (ConvRules.MainForm.pas) (+4 more)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.BlockPercent, ConvRules.Model.TRuleBook.ConvertHeaders, IntToStr, LowerCase, Pointer, Pos, Trim</para>
      /// <para>Reads: FRules, FRulesFilter, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BlockPercent"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.ConvertHeaders"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshRulesList;
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="Item"><!-- drag-lint:auto type -->TListItem</param>
      /// <param name="Selected"><!-- drag-lint:auto type -->Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, Integer</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadGridForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
      /// <param name="AHdrIdx"><!-- drag-lint:auto type -->Integer</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoMappings (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoNewConversion (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.OpenOwningRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RulesSelectItem (ConvRules.MainForm.pas) (+1 more)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.GetProptree, ConvRules.MainForm.TConvRulesForm.RefreshGrid, ConvRules.MainForm.TConvRulesForm.RefreshPool, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled, Default, Format, Trim</para>
      /// <para>Reads: FTbOnlyType, FBook, FCbFrom, FCbTo, FFromTree, FSurfaceMinVis, FEngine, FToTree (+3 more)   Writes: FActiveHdr, FPoolTypeFilter, FFromTree, FToTree</para>
      /// <para>UI thread only -- touches Application</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.GetProptree"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshGrid"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshPool"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadGridForBlock(AHdrIdx: Integer);
      /// <summary><!-- drag-lint:auto sum -->A From leaf with no #link may still be spoken
      /// for: an applied #mapping can decide it conditionally, and such a row shows
      /// '&lt;conditional: N cases&gt;' in the To column rather than reading as unassigned.
      /// The conditional list is built ONCE per refresh (the two passes below both consult
      /// it), because the alternative is rescanning every node for every leaf.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoClearGridFindFrom (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoClearGridFindTo (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.GridFilterChange (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LoadGridForBlock (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConditionalCasesOf, ConvRules.MainForm.GridRowMatchesFilter, ConvRules.MainForm.TConvRulesForm.FindLinkForFrom, ConvRules.MainForm.TConvRulesForm.RefreshGrid.ToCellFor, ConvRules.Model.PropCellText, Format, LeafType, Max, Trim</para>
      /// <para>Complexity: 10 (cyclomatic, outer body), 68 lines (full implementation)</para>
      /// <para>Reads: FGridFindFrom, FGridFindTo, FFromTree, FGrid, FLblGridMatch</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.GridRowMatchesFilter"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.FindLinkForFrom"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshGrid.ToCellFor"/>
      /// <seealso cref="ConvRules.Model.PropCellText"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshGrid;
      /// <summary><!-- drag-lint:auto sum -->Shared OnChange for both grid filter boxes --
      /// narrows the grid to the current From/To substrings on every keystroke. Guarded
      /// like PoolFilter: no active block means no trees to filter yet.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshGrid</para>
      /// <para>Reads: FActiveHdr</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshGrid"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure GridFilterChange(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Clear button for the From grid filter: empties
      /// only its own box and refreshes.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshGrid</para>
      /// <para>Reads: FGridFindFrom, FActiveHdr</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshGrid"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoClearGridFindFrom(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Clear button for the To grid filter: empties
      /// only its own box and refreshes.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshGrid</para>
      /// <para>Reads: FGridFindTo, FActiveHdr</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshGrid"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoClearGridFindTo(Sender: TObject);
      /// <summary>Prompts for one or more .dfm/.pas files, scans them via
      /// ConvRules.Usage.ComputeUsage for the active rule's From class, and marks the
      /// used From properties green in the grid. No-op with a status message when no
      /// conversion is selected.</summary>
      /// <summary>Harvests the component types of the examined .dfm file(s) into the
      /// form-types panel.</summary>
      /// <param name="ADfmTexts">The .dfm contents Examine just read.</param>
      /// <remarks>
      /// Deliberately independent of FActiveHdr: the panel exists to CHOOSE
      /// a From class, so it must work before any conversion is selected. Manual
      /// re-enables are carried over by type name so a re-Examine of the same form
      /// does not silently undo them.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.FormTypes.MergeFormTypes, ConvRules.FormTypes.ScanDfmTypes, ConvRules.MainForm.TConvRulesForm.LoadDescendantSet, ConvRules.MainForm.TConvRulesForm.RefreshFormTypes, ConvRules.MainForm.TConvRulesForm.RescanRulesFolder, SameText</para>
      /// <para>Reads: FFormTypeRows, FVisualSet, FCatalog   Writes: FFormTypeRows, FVisualSet, FComponentSet, FPersistentSet</para>
      /// <seealso cref="ConvRules.FormTypes.MergeFormTypes"/>
      /// <seealso cref="ConvRules.FormTypes.ScanDfmTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadDescendantSet"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RescanRulesFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HarvestFormTypes(const ADfmTexts: TArray<string>);
      /// <summary>Re-applies Visual/Ruled decoration and repaints the list.</summary>
      /// <remarks>
      /// Cheap and idempotent -- called on every filter keystroke. The
      /// TypeIsExcluded filter pass moves to the Apply button in Task 9; until then
      /// this only tallies RowState.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoSave (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.FilterChanged (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LoadFile (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RescanRulesFolder (ConvRules.MainForm.pas) (+1 more)</para>
      /// <para>Calls: ConvRules.FormTypes.RowState, ConvRules.MainForm.TConvRulesForm.DeclaringUnitCached, ConvRules.MainForm.TConvRulesForm.DuplicateSitesFor, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.RuleCatalog.FindRuleForType, ExtractFileName, Format, UpperCase</para>
      /// <para>Complexity: 23 (cyclomatic, outer body), 96 lines (full implementation)</para>
      /// <para>Reads: FFormTypeList, FFilterMemo, FChkStdCtrls, FFormTypeRows, FDeclUnits, FVisualSet, FComponentSet, FPersistentSet (+3 more)   Writes: FFilterError</para>
      /// <para>UI thread only -- touches Application</para>
      /// <seealso cref="ConvRules.FormTypes.RowState"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DeclaringUnitCached"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DuplicateSitesFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshFormTypes;
      /// <summary>The FFormTypeRows index the user has selected, or -1.</summary>
      /// <returns>-1 when FFormTypeList does not exist yet, nothing is selected, or
      /// the selection maps (via FVisibleRows) to a row index that no longer fits
      /// FFormTypeRows.</returns>
      /// <remarks>
      /// The one legal way to turn a FFormTypeList.ItemIndex into a
      /// FFormTypeRows index -- the two are the same number only when nothing is
      /// filtered, so every handler routes through this rather than indexing
      /// FFormTypeRows with ItemIndex directly. The bounds logic itself is
      /// ConvRules.FormTypes.ResolveSelectedRow, tested there headlessly; this is
      /// just the UI-facing wrapper that supplies FFormTypeList.ItemIndex.
      /// </remarks>
      function SelectedRowIndex: Integer;
      /// <summary>The class-search text, or '' when the search box does not exist
      /// yet (Task 8 wires FRulesFilter to this list).</summary>
      /// <remarks>
      /// FRulesFilter is the class search box: a partial, case-insensitive match
      /// against form-type class names. It changes only which rows RefreshFormTypes
      /// shows -- never a check state.
      /// </remarks>
      function ClassSearchText: string;
      /// <summary>TNotifyEvent shim so the filter controls can re-run RefreshFormTypes.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FilterChanged(Sender: TObject);
      /// <summary>Rescans FRulesFolder into FCatalog and rewrites its index file.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoSave (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LoadFile (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.RuleCatalog.CatalogToIndexText, ConvRules.RuleCatalog.FindDuplicates, ConvRules.RuleCatalog.ScanRulesFolder, ExtractFileName, ExtractFilePath, Format, Trim</para>
      /// <para>Reads: FRulesFolder, FFilePath, FCatalog, FCatalogDups   Writes: FCatalog, FCatalogDups, FRulesFolder</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.RuleCatalog.CatalogToIndexText"/>
      /// <seealso cref="ConvRules.RuleCatalog.FindDuplicates"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RescanRulesFolder(Sender: TObject);
      /// <summary>Copies the clicked type into the From picker.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// Fires whether the row is greyed or not, by design: a greyed row is
      /// a hint, never a prohibition.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.SetStatus, Format</para>
      /// <para>Reads: FFormTypeList, FFormTypeRows, FCbFrom</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormTypeClick(Sender: TObject);
      /// <summary>Double-click a RULED type: open the book that owns it and select
      /// the block.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// The conservative reading of "edit an individual conversion": it
      /// loads the whole owning FILE and selects the rule inside it, so FFilePath
      /// keeps meaning exactly what it meant before and there is no new way to lose a
      /// file. Switching books goes through the same three-way prompt Curate uses,
      /// worded with DISCARD because that is what No does.
      /// <para>For a type claimed by several rules it opens the FIRST site -- the one
      /// FindRuleForType reports as the owner and the panel already names -- and says
      /// how many others exist, because picking silently between two rules is the
      /// mistake this whole catalog exists to prevent.</para>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.OpenOwningRule, ConvRules.MainForm.TConvRulesForm.SetStatus, Format</para>
      /// <para>Reads: FFormTypeList, FFormTypeRows</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.OpenOwningRule"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormTypeDblClick(Sender: TObject);
      /// <summary>Opens the book that owns ATypeName's rule and selects the block.</summary>
      /// <param name="ATypeName">A bare or qualified type name.</param>
      /// <returns>False when nothing was opened -- not catalogued, the user cancelled,
      /// a save failed, or the index is stale. The reason is already on the status bar.</returns>
      /// <remarks>
      /// The single way to reach an existing rule, shared by the form-types
      /// double-click and by New Conversion when it finds the type already ruled. One
      /// implementation because both must apply the same discard prompt and the same
      /// stale-index handling.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.FormTypeDblClick (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.DoSave, ConvRules.MainForm.TConvRulesForm.DuplicateSitesFor, ConvRules.MainForm.TConvRulesForm.LoadFile, ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.RuleCatalog.FindRuleForType, ConvRules.RuleCatalog.HeaderIndexFor, ExtractFileName, Format, Integer, MessageDlg, SameText</para>
      /// <para>Returns: False; True</para>
      /// <para>Complexity: 13 (cyclomatic, outer body), 75 lines (full implementation)</para>
      /// <para>Reads: FCatalog, FFilePath, FBook, FRules</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoSave"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DuplicateSitesFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFile"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadGridForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function OpenOwningRule(const ATypeName: string): Boolean;
      /// <summary>Toggles the selected row's Skipped mark.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes</para>
      /// <para>Reads: FFormTypeList, FFormTypeRows</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ToggleFormTypeSkip(Sender: TObject);
      /// <summary>Applies the checklist's ticked state to the selected row's
      /// Skipped flag and persists it immediately.</summary>
      /// <param name="Sender">Unused; required by TCheckListBox.OnClickCheck.</param>
      /// <remarks>
      /// Checked means "we are not converting this class" -- an explicit user
      /// decision, saved on the spot rather than at some later Save the user
      /// may never reach.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes, ConvRules.MainForm.TConvRulesForm.SaveSkipList</para>
      /// <para>Reads: FFormTypeRows, FFormTypeList</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SaveSkipList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormTypeCheckClick(Sender: TObject);
      /// <summary>Owner-draws one form-type row: V/N/? mark, name, count, why dimmed.</summary>
      /// <param name="AControl"><!-- drag-lint:auto type -->TWinControl</param>
      /// <param name="AIndex"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ARect"><!-- drag-lint:auto type -->TRect</param>
      /// <param name="AState"><!-- drag-lint:auto type -->TOwnerDrawState</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.FormTypes.DescribeFormTypeRow, ConvRules.FormTypes.ResolveSelectedRow, ConvRules.FormTypes.RowState, TCheckListBox</para>
      /// <para>Reads: FVisibleRows, FFormTypeRows</para>
      /// <para>UI thread only -- touches AControl</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.FormTypes.DescribeFormTypeRow"/>
      /// <seealso cref="ConvRules.FormTypes.ResolveSelectedRow"/>
      /// <seealso cref="ConvRules.FormTypes.RowState"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormTypeDrawItem(AControl: TWinControl; AIndex: Integer; ARect: TRect; AState: TOwnerDrawState);
      /// <summary>Bare names of every descendant of AAncestor, as a fast lookup set.</summary>
      /// <param name="AAncestor">e.g. 'TControl'. One engine call, ~1.5 s.</param>
      /// <returns>An owned list; EMPTY (never nil) when the engine cannot answer, so
      /// callers cannot mistake "no answer" for "not a descendant".</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestFormTypes (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListDescendantsOf/3, Trim</para>
      /// <para>Returns: TStringList.Create</para>
      /// <para>Reads: FEngine</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListDescendantsOf"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LoadDescendantSet(const AAncestor: string): TStringList;
      /// <summary>How many rules in the catalog claim ATypeName; 0 or 1 is healthy.</summary>
      /// <param name="ATypeName">A bare or qualified type name.</param>
      /// <returns>The number of sites, so a caller can render "+N DUPLICATE".</returns>
      /// <remarks>
      /// <!-- drag-lint:auto -->The same .pas texts are also run through ScanUsesClauses, and the
      /// units they name become CANDIDATE rows on the Unit Rules tab -- a work list, not an edit. The
      /// rule book is not touched by any of this.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.OpenOwningRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.RuleCatalog.BareTypeName, SameText</para>
      /// <para>Returns: 0; Length(Dup.Entries)</para>
      /// <para>Reads: FCatalogDups</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.RuleCatalog.BareTypeName"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DuplicateSitesFor(const ATypeName: string): Integer;
      /// <summary>The declaring unit of ATypeName, memoised for the session.</summary>
      /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
      /// <returns>'' when the engine cannot resolve it -- which must NOT be read as
      /// "not a standard control".</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DeclaringUnitOf, UpperCase</para>
      /// <para>Returns: FEngine.DeclaringUnitOf(ATypeName)</para>
      /// <para>Reads: FDeclUnits, FEngine   Writes: FDeclUnits</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DeclaringUnitOf"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DeclaringUnitCached(const ATypeName: string): string;
      /// <summary>Browses for form/source files, starting in the last-used folder.</summary>
      /// <param name="AFiles">Receives the chosen paths, sibling-expanded.</param>
      /// <returns>False when the user cancels; AFiles is then untouched.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoExamine (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoOpenForm (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings, ConvRules.MainForm.TConvRulesForm.SetLastFormDir, ExtractFileDir</para>
      /// <para>Returns: False; Length(AFiles) &gt; 0</para>
      /// <para>Reads: FLastFormDir</para>
      /// <para>Mutates: AFiles (out)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetLastFormDir"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function PickFormFiles(out AFiles: TArray<string>): Boolean;
      /// <summary>Reads the given files, harvests their types, and -- only when a
      /// conversion is selected -- marks its used From properties.</summary>
      /// <param name="AFiles">Absolute paths; unreadable ones are reported, not fatal.</param>
      /// <remarks>
      /// The single load path. The toolbar's Examine, the panel's Open form
      /// button and --form all funnel through here, so none of them can drift.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoExamine (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoOpenForm (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.HarvestFormTypes, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.ShowUsageReport, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled, ConvRules.Usage.ComputeUsage, ConvRules.Usage.MergeUsage, ConvRules.Usage.ScanUsesClauses, Copy, ExtractFileExt, ExtractFileName, Format, LastDelimiter, SameText</para>
      /// <para>Reads: FUsedFiles, FActiveHdr, FFormTypeRows, FExamineInfo, FFromTree, FBook, FUnitCandidates, FGrid   Writes: FUsedFiles, FExamineInfo, FUsedProps, FUnitCandidates</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.HarvestFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ShowUsageReport"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadFormFiles(const AFiles: TArray<string>);
      /// <summary>Adds each path's sibling .pas/.dfm when it exists.</summary>
      /// <param name="APaths">Chosen paths.</param>
      /// <returns>The input plus any siblings, de-duplicated.</returns>
      /// <remarks>
      /// A Delphi form IS the pair: the .dfm carries the component types and
      /// the .pas carries the uses clause and the property access sites. Opening one
      /// and silently ignoring the other would answer half of every question.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.PickFormFiles (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ChangeFileExt, ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings.Take, ExtractFileExt, LowerCase, Trim</para>
      /// <para>Returns: nil</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings.Take"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExpandUnitSiblings(const APaths: TArray<string>): TArray<string>;
      /// <summary>Records and persists the folder the Open dialog should start in.</summary>
      /// <param name="ADir"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.PickFormFiles (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.SetStatus, Trim</para>
      /// <para>Writes: FLastFormDir</para>
      /// <para>Touches: registry</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetLastFormDir(const ADir: string);
      /// <summary>Panel button: browse for a form, then load it.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadFormFiles, ConvRules.MainForm.TConvRulesForm.PickFormFiles</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFormFiles"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.PickFormFiles"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      /// <summary>Put a NON-PROJECT unit into the From Unit box: browse for a
      /// loose .pas/.dfm pair and select its path in the combo.</summary>
      /// <remarks>The combo itself only ever lists project members
      /// (<see cref="CbLoadUnits"/>), so this is the only route to converting a
      /// unit the project has never included.</remarks>
      procedure DoBrowseFromUnit(Sender: TObject);
      procedure DoOpenForm      (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadFormFiles, ConvRules.MainForm.TConvRulesForm.PickFormFiles</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFormFiles"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.PickFormFiles"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoExamine(Sender: TObject);
      /// <summary>Drops the current examination (FUsedProps/FUsedFiles/FExamineInfo)
      /// and repaints the grid with no rows marked.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled</para>
      /// <para>Reads: FGrid   Writes: FUsedProps, FUsedFiles, FUnitCandidates, FExamineInfo</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoClearExamine(Sender: TObject);
      /// <summary>Shows a small read-only report window listing used property names
      /// that matched no From-tree leaf (ConvRules.Usage TUsageSet.Missing).</summary>
      /// <param name="AMissing"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadFormFiles (ConvRules.MainForm.pas)</para>
      /// <para>Calls: Format</para>
      /// <para>UI thread only -- touches F</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ShowUsageReport(const AMissing, ALoose: TArray<string>);
      /// <summary>FGrid.OnDrawCell: paints a row green when its From path is used per
      /// the active examination (FUsedProps), else the normal fixed/selected/window
      /// colours. Every colour is resolved through StyleServices, so the grid follows
      /// the active VCL style. Requires FGrid.DefaultDrawing = False to own painting.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="ACol"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ARow"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="Rect"><!-- drag-lint:auto type -->TRect</param>
      /// <param name="State"><!-- drag-lint:auto type -->TGridDrawState</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ColorToRGB, ConvRules.MainForm.PathOfGridCell, ConvRules.Theme.ExamineRowColor, ConvRules.Usage.IsRowUsed, Integer, TColor</para>
      /// <para>Reads: FGrid, FUsedProps, FThemeMode</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.PathOfGridCell"/>
      /// <seealso cref="ConvRules.Theme.ExamineRowColor"/>
      /// <seealso cref="ConvRules.Usage.IsRowUsed"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
      { Builds the main menu (View > Theme). Called first from BuildUI so the menu bar
      is in place before the panels claim the client area. }
      /// <summary><!-- drag-lint:auto sum -->Builds the main menu (View &gt; Theme). Called
      /// first from BuildUI so the menu bar is in place before the panels claim the client
      /// area.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.BuildUI (ConvRules.MainForm.pas)</para>
      /// <para>Reads: FMnuTheme</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildMenu;
      { View > Theme item handler; the item's Tag is Ord(TThemePref). }
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto -->View &gt; Theme item handler; the item's Tag is Ord(TThemePref).
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.SetThemePref, TThemePref</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetThemePref"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ThemeMenuClick(Sender: TObject);
      { Builds FTypePopup and hangs it on both the grid and the pool. Called from
      BuildUI after both controls exist. }
      /// <summary><!-- drag-lint:auto sum -->Builds FTypePopup and hangs it on both the
      /// grid and the pool. Called from BuildUI after both controls exist.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.BuildUI (ConvRules.MainForm.pas)</para>
      /// <para>Reads: FMnuGotoDef, FTypePopup, FGrid, FPool   Writes: FTypePopup, FMnuGotoDef</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildTypePopup;
      { The type token of the grid or pool cell at client position APos, via
      TypeOfCell. '' when that position shows no type -- the header row, the cast
      column, blank space past the last row. ASender selects which control. }
      /// <summary><!-- drag-lint:auto sum -->The type token of the grid or pool cell at
      /// client position APos, via TypeOfCell. '' when that position shows no type -- the
      /// header row, the cast column, blank space past the last row. ASender selects which
      /// control.</summary>
      /// <param name="ASender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="APos"><!-- drag-lint:auto type -->const TPoint</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: '';
      /// TypeOfCell(FPool.Items[Idx]); TypeOfCell(FGrid.Cells[C, R]).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.GridPoolContextPopup (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TypeOfCell</para>
      /// <para>Reads: FPool, FGrid</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TypeOfCell"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function TypeAtPos(ASender: TObject; const APos: TPoint): string;
      { FGrid/FPool.OnContextPopup -- caches the type under the cursor and re-titles
      the item. Sets Handled (suppressing the menu ENTIRELY, rather than popping an
      empty frame with one hidden item) when the cell shows no type. }
      /// <summary><!-- drag-lint:auto sum -->FGrid/FPool.OnContextPopup -- caches the type
      /// under the cursor and re-titles the item. Sets Handled (suppressing the menu
      /// ENTIRELY, rather than popping an empty frame with one hidden item) when the cell
      /// shows no type.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="MousePos"><!-- drag-lint:auto type -->TPoint</param>
      /// <param name="Handled"><!-- drag-lint:auto type -->var Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.TypeAtPos</para>
      /// <para>Reads: FCtxType, FMnuGotoDef   Writes: FCtxType</para>
      /// <para>Mutates: Handled (var)</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.TypeAtPos"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure GridPoolContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
      { FMnuGotoDef.OnClick -- resolves FCtxType and asks the running IDE to open it.
      Degrades to file:line in the status bar + on the clipboard when no IDE is
      listening; appends the member list when the type is an enum. }
      /// <summary><!-- drag-lint:auto sum -->FMnuGotoDef.OnClick -- resolves FCtxType and
      /// asks the running IDE to open it. Degrades to file:line in the status bar + on the
      /// clipboard when no IDE is listening; appends the member list when the type is an
      /// enum.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ChangeFileExt, ConvRules.Engine.TEngineAdapter.EnumMembersOf/3, ConvRules.Engine.TEngineAdapter.ResolveTypeLocation/5, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.OpenSourceClient.SendOpenSource, ExtractFileName, Format</para>
      /// <para>Reads: FCtxType, FEngine</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.EnumMembersOf"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveTypeLocation"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.OpenSourceClient.SendOpenSource"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoGoToDefinition(Sender: TObject);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoOnlyType (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoUnassign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LoadGridForBlock (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.PoolFilter (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Mappings.MappedTargetPaths, ConvRules.Model.PropCellText, LowerCase, Pos, SameText, Trim</para>
      /// <para>Reads: FBook, FPoolFind, FPool, FToTree, FPoolTypeFilter</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Mappings.MappedTargetPaths"/>
      /// <seealso cref="ConvRules.Model.PropCellText"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshPool;
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Casts.ResolveUnknownTypes, ConvRules.MainForm.PathOfGridCell, ConvRules.MainForm.TConvRulesForm.AssignLink, ConvRules.MainForm.TConvRulesForm.CanCast, ConvRules.MainForm.TConvRulesForm.FindLinkForFrom, ConvRules.MainForm.TConvRulesForm.LeafType, ConvRules.MainForm.TConvRulesForm.LeafWritable, ConvRules.MainForm.TConvRulesForm.RefreshPool, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetError (+7 more)</para>
      /// <para>Reads: FActiveHdr, FPool, FGrid, FFromTree, FToTree</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Casts.ResolveUnknownTypes"/>
      /// <seealso cref="ConvRules.MainForm.PathOfGridCell"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.CanCast"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.FindLinkForFrom"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoAssign(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.PathOfGridCell, ConvRules.MainForm.TConvRulesForm.FindLinkForFrom, ConvRules.MainForm.TConvRulesForm.RefreshPool, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled</para>
      /// <para>Reads: FActiveHdr, FGrid, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.PathOfGridCell"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.FindLinkForFrom"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshPool"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoUnassign(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshPool</para>
      /// <para>Reads: FActiveHdr</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshPool"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PoolFilter(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Align the highlighted To leaf to the From
      /// side: select the From-grid row whose property has the SAME last-segment name
      /// (case-insensitive), so the two sides can be assigned by name. Reports when no From
      /// property carries that name.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.LeafNameOf, ConvRules.MainForm.PathOfGridCell, ConvRules.MainForm.TConvRulesForm.SetStatus, Format, SameText</para>
      /// <para>Reads: FActiveHdr, FPool, FGrid</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.LeafNameOf"/>
      /// <seealso cref="ConvRules.MainForm.PathOfGridCell"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoFindInFrom(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Toggle a pool type-narrowing: first press
      /// restricts the pool to leaves whose TYPE matches the highlighted leaf (e.g. only
      /// Boolean targets); a second press clears it. Cleared automatically when a different
      /// rule is loaded.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshPool, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TypeOfCell, Format</para>
      /// <para>Reads: FActiveHdr, FPoolTypeFilter, FTbOnlyType, FPool   Writes: FPoolTypeFilter</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshPool"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TypeOfCell"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoOnlyType(Sender: TObject);
      /// <summary>Opens the conditional #mapping editor for one named mapping, splices the
      /// result back into the book and makes sure the active block #applies it.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// Needs an active block: the live validation is done against that block's
      /// To tree and To class, and a mapping only reaches a block through an #apply.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.MappingForm.TMappingForm.EditMapping, ConvRules.Mappings.MappingNames, ConvRules.Model.TRuleBook.MappingNodesNamed, ConvRules.Model.TRuleBook.NodesInBlock, ConvRules.Model.TRuleBook.ReplaceMapping, Format, IfThen, InputQuery, SameText, Trim</para>
      /// <para>Complexity: 13 (cyclomatic, outer body), 66 lines (full implementation)</para>
      /// <para>Reads: FActiveHdr, FBook, FEngine, FToTree   Writes: FActiveHdr</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadGridForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <seealso cref="ConvRules.MappingForm.TMappingForm.EditMapping"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoMappings(Sender: TObject);
      { The mapping names the ACTIVE block #applies; [] when no block is selected. }
      /// <summary><!-- drag-lint:auto sum -->The mapping names the ACTIVE block #applies;
      /// [] when no block is selected.</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed:
      /// AppliedMappingNames(FBook.NodesInBlock(FActiveHdr)).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Mappings.AppliedMappingNames, ConvRules.Model.TRuleBook.NodesInBlock</para>
      /// <para>Reads: FActiveHdr, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Mappings.AppliedMappingNames"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.NodesInBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ActiveAppliedNames: TArray<string>;
      { The From paths those applied mappings decide conditionally, with a case count each.
      Recomputed per caller rather than cached: a mapping edit, a block switch and a raw
      tab edit would each have to invalidate a cache, and the node list is short. }
      /// <summary><!-- drag-lint:auto sum -->The From paths those applied mappings decide
      /// conditionally, with a case count each. Recomputed per caller rather than cached: a
      /// mapping edit, a block switch and a raw tab edit would each have to invalidate a
      /// cache, and the node list is short.</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TConditionalFrom&gt; -- Observed:
      /// ConditionalFromPaths(FBook.Nodes.ToArray, ActiveAppliedNames).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Mappings.ConditionalFromPaths</para>
      /// <para>Reads: FActiveHdr, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Mappings.ConditionalFromPaths"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ActiveConditionals: TArray<TConditionalFrom>;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAddSwap (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUnuse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas) (+7 more)</para>
      /// <para>Calls: ConvRules.Model.TRuleBook.SaveToString</para>
      /// <para>Reads: FRaw, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Model.TRuleBook.SaveToString"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SyncRawFromModel;
      /// <summary><!-- drag-lint:auto sum -->The list shows the rule book's unit directives
      /// first, then -- underneath them -- the units Examine harvested that STILL have no
      /// rule of their own (Item.Data = nil marks a candidate). Candidates are re-filtered
      /// on every refresh rather than pruned once, so authoring a #use/#unuse/#useswap for
      /// one silently retires its candidate row, and one source unit can fan out to several
      /// replacements through the existing #useswap.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddSwap (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUnuse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoCheckUnits (ConvRules.MainForm.pas) (+6 more)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshUnitList.HasRuleFor, ConvRules.MainForm.TConvRulesForm.RefreshUnitList.InConflict, ConvRules.Model.TRuleBook.UnitNodes, ConvRules.Units.NormalizeUnitSets, IfThen, Pointer, SameText</para>
      /// <para>Reads: FUnitList, FBook, FUnitCandidates</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList.HasRuleFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList.InConflict"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.UnitNodes"/>
      /// <seealso cref="ConvRules.Units.NormalizeUnitSets"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      /// <summary>Fill the Unit Rules tab's candidate rows from the `uses` clauses of
      /// APasTexts, each marked with the clause it was written in.</summary>
      /// <param name="APasTexts">One entry per .pas file. Scanned PER TEXT and merged:
      /// the interface/implementation latch is per-unit, so scanning a concatenation
      /// would mislabel every clause after the first file's `implementation`.</param>
      /// <remarks>Writes FUsedUnitRefs and FUnitCandidates from ONE scan so the two
      /// cannot disagree, and calls RefreshUnitList. Purely additive -- it never
      /// touches FBook, so both callers stay read-only with respect to the rule book.
      /// First occurrence wins across texts, as it does within one.</remarks>
      procedure HarvestUsedUnits(const APasTexts: TArray<string>);
      /// <summary>Fill the class list for the picked unit: the .dfm component
      /// classes already in FFormTypeRows, UNIONED with the classes the unit
      /// declares.</summary>
      /// <param name="AUnitText">The unit's .pas text -- feeds ScanClassesDeclared,
      /// the fallback used only when the engine cannot list the unit's
      /// classes.</param>
      /// <param name="APasPath">Full path to the .pas, passed to
      /// TEngineAdapter.OutlineClasses for the declared-class half.</param>
      /// <returns>'' when there is nothing to say; otherwise a status-line
      /// suffix -- either noting a one-time scratch index build, or that the
      /// engine could not answer and a text-scan fallback (blind to
      /// conditionals and comments) was used instead.</returns>
      /// <remarks>MERGES into FFormTypeRows, never overwrites it. Before
      /// 2026-09-20 this rebuilt FFormTypeRows from the text scan alone, so
      /// picking a unit replaced its form's already-harvested component
      /// classes with the two or three classes the .pas happens to
      /// declare.</remarks>
      function HarvestUnitClasses(const AUnitText, APasPath: string): string;
      /// <summary>STUB for Task 9: stamps loaded skip marks onto FFormTypeRows.
      /// Currently a no-op placeholder so HarvestUnitClasses (and its Task 6/7
      /// siblings) can call it unconditionally; Task 9 replaces this body with
      /// the real one that reads FSkipList.</summary>
      /// <remarks>Deliberately an empty-bodied stub kept in the source, not a
      /// commented-out call site -- a commented-out call would sit in the tree
      /// for four tasks and trip this repo's own commented-out-code lint
      /// rule.</remarks>
      procedure ApplySkipMarks;
      /// <summary>STUB for Task 9: persists FFormTypeRows' Skipped marks so they
      /// survive a restart. Currently a no-op placeholder so ToggleFormTypeSkip can
      /// call it unconditionally; Task 9 replaces this body with the real
      /// ConvRules.SkipList write.</summary>
      /// <remarks>Deliberately an empty-bodied stub kept in the source, not a
      /// commented-out call site -- a commented-out call would sit in the tree
      /// for three tasks and trip this repo's own commented-out-code lint
      /// rule.</remarks>
      procedure SaveSkipList;
      /// <summary>Fill the Unit Rules tab and the left class list from the TEXT of
      /// AUnitName's .pas -- the file, never the index, so a browsed or orphan unit
      /// (VARINSP) answers. This is the "unit selected" half of Fill From-classes:
      /// every path that PICKS a unit (Browse..., the From Unit drop-down, the button)
      /// goes through here, so picking is what fills the tab.</summary>
      /// <param name="AUnitName">A bare project unit name (resolved through the
      /// engine) or a full path to a .pas/.dfm (its .pas sibling is read).</param>
      /// <returns>'' on success; otherwise a status-line suffix saying WHY the tab is
      /// empty (' Unit list unavailable: ...'). Never raises: the list is a
      /// convenience and must not stop the caller.</returns>
      function HarvestUnitFile(const AUnitName: string): string;
      /// <summary>From Unit drop-down pick: harvest the chosen unit into the Unit Rules
      /// tab at once, without waiting for Fill From-classes.</summary>
      procedure CbUnitSelected(Sender: TObject);
      procedure RefreshUnitList;
      /// <summary><!-- drag-lint:auto sum -->---- Unit Rules tab ----</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->TRuleNode</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAddSwap (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUnuse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddUse (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoDeriveUnits (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Model.TRuleBook.Add, ConvRules.Model.TRuleBook.ConvertHeaders</para>
      /// <para>Reads: FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Model.TRuleBook.Add"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.ConvertHeaders"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure InsertUnitNode(ANode: TRuleNode);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.InsertUnitNode, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, Format, InputQuery, Trim</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.InsertUnitNode"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoAddSwap(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.InsertUnitNode, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, InputQuery, Trim</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.InsertUnitNode"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoAddUse(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.InsertUnitNode, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, InputQuery, Trim</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.InsertUnitNode"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoAddUnuse(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled, SameText, TRuleNode</para>
      /// <para>Reads: FUnitList, FUnitCandidates, FBook   Writes: FUnitCandidates</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoDeleteUnit(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DeclaringUnitOf, ConvRules.MainForm.TConvRulesForm.DoDeriveUnits.HasUnuse, ConvRules.MainForm.TConvRulesForm.DoDeriveUnits.HasUse, ConvRules.MainForm.TConvRulesForm.InsertUnitNode, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.Model.TRuleBook.ConvertHeaders, ConvRules.Model.TRuleBook.UnitNodes, ConvRules.Units.DeriveUnits, Format, SameText</para>
      /// <para>Reads: FBook, FEngine</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DeclaringUnitOf"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoDeriveUnits.HasUnuse"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.DoDeriveUnits.HasUse"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.InsertUnitNode"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoDeriveUnits(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Units.NormalizeUnitSets, Format</para>
      /// <para>Reads: FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.Units.NormalizeUnitSets"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoCheckUnits(Sender: TObject);
      /// <summary>TNotifyEvent shim so the class search box can re-run RefreshFormTypes.</summary>
      /// <param name="Sender">The class search TEdit (FRulesFilter); unused.</param>
      /// <remarks>
      /// Search only narrows FVisibleRows via RefreshFormTypes/VisibleRowIndexes; it
      /// never changes a check state, so the progress line stays truthful.
      /// </remarks>
      procedure ClassSearchChange(Sender: TObject);
      /// <param name="S"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.CbLoadClasses (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.CbLoadUnits (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAddSwap (ConvRules.MainForm.pas) (+30 more)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshStatusColor</para>
      /// <para>Reads: FLblStatus, FStatusBar   Writes: FStatusIsError</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshStatusColor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetStatus(const S: string);
      /// <summary><!-- drag-lint:auto sum -->Show a message in RED bold -- for blocked
      /// assignments and errors.</summary>
      /// <param name="S"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ApplyTheme (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.CbLoadUnits (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.ChooseTargetForNewRule (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas) (+8 more)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshStatusColor</para>
      /// <para>Reads: FLblStatus, FStatusBar   Writes: FStatusIsError</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshStatusColor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetError(const S: string);
      { Re-applies FLblStatus's font for the kind of message currently shown. }
      /// <summary><!-- drag-lint:auto sum -->Re-applies FLblStatus's font for the kind of
      /// message currently shown.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ApplyTheme (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SetError (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SetStatus (ConvRules.MainForm.pas)</para>
      /// <para>Reads: FLblStatus, FStatusIsError</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshStatusColor;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.CbLoadClasses (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.PlatformChanged (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListDescendantsOf/4</para>
      /// <para>Reads: FFromClasses, FToClasses, FEngine, FCbFrom, FCbTo   Writes: FFromClasses, FToClasses</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListDescendantsOf"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadAllClasses;
      /// <summary><!-- drag-lint:auto sum -->Falls back to a tiny built-in set if either
      /// query yields nothing so the New Conversion flow always works. Each side's DB set =
      /// its platform's library index + the shared project DB (additive, so
      /// project-declared component types still resolve).</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed:
      /// LibDbsFor(FFromPlatform, GEditorLibDir) + [GEditorProjectDb].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Platform.LibDbsFor</para>
      /// <para>Reads: FFromPlatform</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Platform.LibDbsFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FromDbSet: TArray<string>;
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed:
      /// LibDbsFor(FToPlatform, GEditorLibDir) + [GEditorProjectDb].</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Platform.LibDbsFor</para>
      /// <para>Reads: FToPlatform</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Platform.LibDbsFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ToDbSet: TArray<string>;
      /// <summary><!-- drag-lint:auto sum -->The engine's default DB set
      /// (proptree/scaffold/validate/qname-resolve) must resolve BOTH sides' types +
      /// project units -- the deduped union of both sides.</summary>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: LowerCase</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EngineDbSet: TArray<string>;
      /// <summary><!-- drag-lint:auto sum -->A platform dropdown changed: recompute both
      /// sides' platforms from the combos, update the engine's default DB set, clear the
      /// class caches, and reload the pickers so they now list the newly-selected
      /// platforms' types.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.SetDbs, ConvRules.MainForm.TConvRulesForm.LoadAllClasses, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Platform.PlatformToStr, Format, TConvPlatform</para>
      /// <para>Reads: FCbFromPlat, FCbToPlat, FEngine, FCbFrom, FCbTo, FFromPlatform, FToPlatform, FFromClasses (+1 more)   Writes: FFromPlatform, FToPlatform, FFromClasses, FToClasses</para>
      /// <para>UI thread only -- touches Screen</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.SetDbs"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadAllClasses"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.Platform.PlatformToStr"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure PlatformChanged(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Target surface changed (DFM published
      /// &lt;-&gt; PAS public+fields): remember the new --min-visibility and re-fetch the
      /// active rule's From/To trees at that surface.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadGridForBlock, ConvRules.MainForm.TConvRulesForm.SetStatus</para>
      /// <para>Reads: FCbSurface, FActiveHdr, FSurfaceMinVis   Writes: FSurfaceMinVis</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadGridForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SurfaceChanged(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Lazy-load the class list the first time a
      /// picker is dropped down (enumerating every indexed class is slow, so we defer it
      /// until actually needed).</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.LoadAllClasses, ConvRules.MainForm.TConvRulesForm.SetStatus, Format</para>
      /// <para>Reads: FFromClasses, FToClasses</para>
      /// <para>UI thread only -- touches Screen, Application</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadAllClasses"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CbLoadClasses(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Lazy-load the project unit list the first time
      /// the From-Unit picker drops.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListProjectUnits, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, Format</para>
      /// <para>Reads: FUnitsLoaded, FEngine, FCbUnit   Writes: FUnitsLoaded</para>
      /// <para>UI thread only -- touches Screen, Application</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListProjectUnits"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CbLoadUnits(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->"Fill From-classes": read the chosen unit's
      /// .dfm components and add one FROM-ONLY conversion row per distinct component CLASS
      /// to the rules library (To unassigned). These are CLASSES, not properties, so they
      /// go in the rules list -- NOT the grid's property column. Selecting a From-only row
      /// shows that class's flattened property list; assigning a To class then
      /// auto-matches. A row with no To (and no links) is scratch: SaveComplete drops it,
      /// so nothing is written until the user picks a To. Existing From classes are skipped
      /// (no duplicates). Best-effort: a non-form unit (no .dfm) adds nothing.</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListControlTypesInUnit, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.Model.TRuleBook.Add, ConvRules.Model.TRuleBook.ConvertHeaders, Format, Integer, Trim</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 82 lines (full implementation)</para>
      /// <para>Reads: FCbUnit, FEngine, FBook, FRules</para>
      /// <para>UI thread only -- touches Screen, Application</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListControlTypesInUnit"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SyncRawFromModel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoLoadUnit(Sender: TObject);
      /// <summary><!-- drag-lint:auto sum -->Create or update the #link mapping ToPath
      /// &lt;- FromPath in the active block, choosing a default cast from the leaf types
      /// (identity when same type). Shared by the manual Assign and the Auto-Match pass.
      /// Does NOT touch the grid/UI -- callers refresh. Assumes CanCast(AFromType, AToType)
      /// was already checked.</summary>
      /// <param name="AFromPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AToPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Casts.CastFnName, ConvRules.Casts.SameFamily, ConvRules.Casts.ValidCasts, ConvRules.MainForm.TConvRulesForm.ClassCastName, ConvRules.MainForm.TConvRulesForm.FindLinkForFrom, SameText</para>
      /// <para>Reads: FActiveHdr, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Casts.CastFnName"/>
      /// <seealso cref="ConvRules.Casts.SameFamily"/>
      /// <seealso cref="ConvRules.Casts.ValidCasts"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ClassCastName"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.FindLinkForFrom"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AssignLink(const AFromPath, AToPath, AFromType, AToType: string);
      /// <param name="AHdrIdx"><!-- drag-lint:auto type -->Integer</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: 0; Round(done * 100 / total).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.RefreshRulesList (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Model.TRuleBook.BlockMapsSomething, ConvRules.Model.TRuleBook.NodesInBlock</para>
      /// <para>Reads: FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Model.TRuleBook.BlockMapsSomething"/>
      /// <seealso cref="ConvRules.Model.TRuleBook.NodesInBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function BlockPercent(AHdrIdx: Integer): Integer;
      /// <returns><!-- drag-lint:auto -->TArray&lt;TRuleNode&gt; -- Observed:
      /// FBook.LinksForBlock(FActiveHdr).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Model.TRuleBook.LinksForBlock</para>
      /// <para>Reads: FActiveHdr, FBook</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Model.TRuleBook.LinksForBlock"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ActiveLinks: TArray<TRuleNode>;
      /// <param name="AFromPath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TRuleNode -- Observed: nil.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoUnassign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RefreshGrid (ConvRules.MainForm.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FindLinkForFrom(const AFromPath: string): TRuleNode;
      /// <summary><!-- drag-lint:auto sum -->Resolve a leaf's declared type from a proptree
      /// ('' if not found).</summary>
      /// <param name="ATree"><!-- drag-lint:auto type -->const TProptree</param>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RefreshGrid.ToCellFor (ConvRules.MainForm.pas) ?</para>
      /// <para>Calls: SameText</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LeafType(const ATree: TProptree; const APath: string): string;
      /// <summary><!-- drag-lint:auto sum -->Whether a leaf is a writable assignment
      /// target. Defaults True when the leaf is not found or the engine is proptree/1
      /// (IsWritable defaults True) -- never block on missing data.</summary>
      /// <param name="ATree"><!-- drag-lint:auto type -->const TProptree</param>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function LeafWritable(const ATree: TProptree; const APath: string): Boolean;
      /// <summary><!-- drag-lint:auto sum -->The library class-cast name bridging AFromType
      /// -&gt; AToType, or '' if none.</summary>
      /// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ClassCastFor(FCastDefs,
      /// AFromType, AToType).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.AssignLink (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.CanCast (ConvRules.MainForm.pas)</para>
      /// <para>Calls: DRagLint.Convert.CastLib.ClassCastFor</para>
      /// <para>Reads: FCastDefs</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Convert.CastLib.ClassCastFor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ClassCastName(const AFromType, AToType: string): string;
      /// <summary><!-- drag-lint:auto sum -->Castable when the scalar classifier allows it
      /// OR a library class cast bridges it.</summary>
      /// <param name="AFromType"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AToType"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: IsCastable(AFromType,
      /// AToType) or (ClassCastName(AFromType, AToType) &lt;&gt; '').</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoAssign (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoAutoMatch (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Casts.IsCastable, ConvRules.MainForm.TConvRulesForm.ClassCastName</para>
      /// <para>Pure</para>
      /// <seealso cref="ConvRules.Casts.IsCastable"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ClassCastName"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function CanCast(const AFromType, AToType: string): Boolean;
    public
      { Application.CreateForm calls this standard Create(AOwner); we route it to
      CreateNew (no .dfm) and build the UI in code. Being created via CreateForm
      makes this the Application.MainForm, which is what keeps Application.Run's
      message loop alive -- a manually-shown CreateNew form does not, and Run
      returns immediately. Engine/db config is read from the globals below. }
      /// <summary><!-- drag-lint:auto sum -->Application.CreateForm calls this standard
      /// Create(AOwner); we route it to CreateNew (no .dfm) and build the UI in code. Being
      /// created via CreateForm makes this the Application.MainForm, which is what keeps
      /// Application.Run's message loop alive -- a manually-shown CreateNew form does not,
      /// and Run returns immediately. Engine/db config is read from the globals below.</summary>
      /// <param name="AOwner"><!-- drag-lint:auto type -->TComponent</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.Create, ConvRules.MainForm.TConvRulesForm.ApplyTheme, ConvRules.MainForm.TConvRulesForm.BuildUI, ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings, ConvRules.MainForm.TConvRulesForm.LoadFormFiles, ConvRules.MainForm.TConvRulesForm.SetError, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Model.TRuleBook.Create, ConvRules.Theme.ResolveThemeMode, CreateNew, DRagLint.Convert.CastLib.LoadCastLib, ExtractFileDir, Format</para>
      /// <para>constructor</para>
      /// <para>Writes: FBook, FFromPlatform, FToPlatform, FEngine, FActiveHdr, FSurfaceMinVis, FCastDefs, FLastFormDir</para>
      /// <para>Touches: file system</para>
      /// <para>Directives: override</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.Create"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.BuildUI"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ExpandUnitSiblings"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.LoadFormFiles"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(AOwner: TComponent); override;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FEngine, FBook, FVisualSet, FComponentSet, FPersistentSet, FDeclUnits</para>
      /// <para>Pure</para>
      /// <para>Directives: override</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.AssignLink"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoCurate (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DoLoad (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.OpenOwningRule (ConvRules.MainForm.pas), declaration (ConvRulesEditor.dpr) ?</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshFormTypes, ConvRules.MainForm.TConvRulesForm.RefreshRulesList, ConvRules.MainForm.TConvRulesForm.RefreshUnitList, ConvRules.MainForm.TConvRulesForm.RescanRulesFolder, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.MainForm.TConvRulesForm.SyncRawFromModel, ConvRules.MainForm.TConvRulesForm.UpdateToolbarEnabled, ConvRules.Model.TRuleBook.ConvertHeaders, ConvRules.Model.TRuleBook.LoadFromString, Format</para>
      /// <para>Reads: FBook, FLblFile, FGrid, FPool, FRules, FFormTypeRows, FCatalog   Writes: FFilePath, FActiveHdr</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshFormTypes"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshRulesList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshUnitList"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RescanRulesFolder"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadFile(const APath: string);

      /// <summary>Switches the application to the light or dark VCL style and
      /// repaints the owner-drawn grid in that mode.</summary>
      /// <param name="AMode">The mode to apply.</param>
      /// <param name="AInteractive">True when the user asked for this from the menu.
      /// Only then is a fallback reported; start-up stays silent, because a modal or
      /// an error banner before the window is even up helps nobody.</param>
      /// <remarks>
      /// Falls back to the built-in system style when the requested style is
      /// not linked into the executable (TStyleManager.TrySetStyle returns False) --
      /// the window then stays usable rather than half-themed. Records AMode either
      /// way, so GridDrawCell keeps tinting the Examine marking for the mode the user
      /// asked for. Does not persist anything; see SetThemePref.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SetThemePref (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.RefreshStatusColor, ConvRules.MainForm.TConvRulesForm.SetError</para>
      /// <para>Reads: FGrid   Writes: FThemeMode</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.RefreshStatusColor"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetError"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveConditionals"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveLinks"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ApplyTheme(AMode: TThemeMode; AInteractive: Boolean = False);

      /// <summary>Records the user's theme preference, persists it under
      /// EDITOR_REG_KEY, and applies the mode it resolves to.</summary>
      /// <param name="APref">The new preference; tpFollowIde re-reads GEditorIdeTheme.</param>
      /// <remarks>
      /// A failed registry write is swallowed: the preference still takes
      /// effect for this session, it simply will not survive a restart. Also syncs the
      /// View &gt; Theme radio items, so it is safe to call from outside the menu.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.ThemeMenuClick (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.MainForm.TConvRulesForm.ApplyTheme, ConvRules.MainForm.TConvRulesForm.SetStatus, ConvRules.Theme.ResolveThemeMode, ConvRules.Theme.ThemePrefToStr</para>
      /// <para>Reads: FMnuTheme</para>
      /// <para>Touches: registry</para>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ApplyTheme"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.SetStatus"/>
      /// <seealso cref="ConvRules.Theme.ResolveThemeMode"/>
      /// <seealso cref="ConvRules.Theme.ThemePrefToStr"/>
      /// <seealso cref="ConvRules.MainForm.TConvRulesForm.ActiveAppliedNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetThemePref(APref: TThemePref);
  end;

var
  GEditorExe: string = '';
  { Library index directory + shared project DB. Each side's picker DB set is
    LibDbsFor(<side platform>, GEditorLibDir) + GEditorProjectDb -- the platform
    selects the library, the project DB is always-on and additive. }
  GEditorLibDir   : string = '';
  GEditorProjectDb: string = '';
  { Path to the shipped class-cast library (.castlib); '' = class casts unavailable
    (scalar-only, today's behavior). Resolved + set by the .dpr before CreateForm. }
  GEditorCastLib: string = '';
  { A form (.dfm or .pas) to load at start-up, from --form on the command line.
    Exists so a debug run lands straight on the unit under study instead of
    browsing to it every time. Its FOLDER also seeds the Open dialog, so a browse
    from a --form session starts beside the unit that was passed. }
  GEditorFormPath: string = '';
  { Defaults come from ConvRules.Platform so the .dpr and this unit cannot drift
    apart; the .dpr overwrites both from --from-platform / --to-platform, which
    still accept win32|win64|both. FROM was cpBoth until 2026-07-29 -- see
    DEFAULT_FROM_PLATFORM for the measurements behind the change. }
  GEditorFromPlatform: TConvPlatform = DEFAULT_FROM_PLATFORM;
  GEditorToPlatform  : TConvPlatform = DEFAULT_TO_PLATFORM  ;
  { Theme. Both are read from the registry and set by the .dpr before CreateForm;
    the constructor applies ResolveThemeMode(GEditorThemePref, GEditorIdeTheme).
    GEditorIdeTheme is the IDE's raw theme name -- kept (not pre-resolved) because
    switching back to "Follow IDE" at runtime has to re-resolve against it. }
  GEditorThemePref: TThemePref = tpFollowIde;
  GEditorIdeTheme : string     = ''             ;

implementation

uses
  System.StrUtils
  , System.Math
  , System.Win.Registry
  , Vcl.Clipbrd
  , ConvRules.Units
  , ConvRules.WorkingSet
  , ConvRules.CurationForm
  ; // ConvRules.Usage moved UP to the interface uses -- TUsedUnitRef types a field

const { VCL style names as they are recorded INSIDE the .vsf files linked by
    ConvRulesEditorStyles.rc -- not the file names. Verified with
    TStyleManager.IsValidStyle; if the .rc ever swaps a style, these must follow. }
  STYLE_LIGHT = 'Windows11 Modern Light';
  STYLE_DARK  = 'Windows11 Modern Dark';

  { ---- helpers ---- }

  { The folder the Open-form dialog should start in, remembered from a previous
  session. '' when never set or unreadable -- TOpenDialog then uses its own
  default, which is the correct fallback rather than an error. }
function ReadLastFormDir: string;
var
  Reg: TRegistry;
begin
  Result:= '';
  Reg:= TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(EDITOR_REG_KEY    ) then
      if Reg.ValueExists    (EDITOR_REG_FORMDIR) then
          Result:= Reg.ReadString(EDITOR_REG_FORMDIR);
    except
      on E: ERegistryException do Result:= '';
    end;
  finally
    Reg.Free;
  end; // try
end; // function

type { Scoped hourglass. Sets Screen.Cursor on create; restores the previous cursor
    when its last reference is released. Hold it in a local IInterface for the
    duration of a slow handler: `var LGuard: IInterface := HourGlass;`. }
  TCursorGuard = class(TInterfacedObject)
    private
      FPrev: TCursor;
    public
      constructor Create(ACursor: TCursor);
      destructor Destroy; override;
  end;

constructor TCursorGuard.Create(ACursor: TCursor);
begin
  inherited Create;
  FPrev:= Screen.Cursor;
  Screen.Cursor:= ACursor;
end;

destructor TCursorGuard.Destroy;
begin
  Screen.Cursor:= FPrev;
  inherited;
end;

function HourGlass: IInterface;
begin
  Result:= TCursorGuard.Create(crHourGlass);
end;

{ Forward-declared so RefreshGrid (below, well before the grid-cell helpers it
  shares this section with) can call it; implemented alongside PathOfGridCell /
  TypeOfCell / LeafNameOf. }
function GridRowMatchesFilter(const AFromCell, AToCell, AFromFilter, AToFilter: string): Boolean; forward;

{ TConvRulesForm }

constructor TConvRulesForm.Create(AOwner: TComponent);
begin
  // Route the standard constructor to CreateNew (no DFM); GlobalNameSpace-free.
  inherited CreateNew(AOwner);
  FBook:= TRuleBook.Create;
  FFromPlatform:= GEditorFromPlatform;
  FToPlatform  := GEditorToPlatform;
  FEngine:= TEngineAdapter.Create(GEditorExe, EngineDbSet);
  FActiveHdr:= -1;
  FSurfaceMinVis:= 'published'; // default target surface = DFM-streamable
  { ParseCastLib, not LoadCastLib: the latter returns only the casts and drops the
    enum blocks from the same file, which the conversion catalog needs. Both halves
    are [] when no .castlib is found, so the previous behaviour is unchanged. }
  var LLib: TCastLib := ParseCastLib(GEditorCastLib);
  FCastDefs:= LLib.Casts;
  FEnumDefs:= LLib.Enums;
  BuildUI;
  // After BuildUI: ApplyTheme repaints FGrid, which BuildUI creates.
  ApplyTheme(ResolveThemeMode(GEditorThemePref, GEditorIdeTheme));
  OnClose:= FormCloseHandler;
  Visible:= True; // ensure the CreateNew form is shown by Run

  // Where the Open-form dialog resumes. --form's own folder wins over the stored
  // one, so a debug run pointed at a different tree browses THERE, not wherever
  // the last interactive session happened to be.
  FLastFormDir:= ReadLastFormDir;
  if GEditorFormPath <> '' then
    FLastFormDir:= ExtractFileDir(GEditorFormPath);

  if GEditorFormPath <> '' then
  begin
    if TFile.Exists(GEditorFormPath) then
      LoadFormFiles(ExpandUnitSiblings([GEditorFormPath]))
    else
      SetError(Format('--form "%s" does not exist.', [GEditorFormPath]));
  end
  else
    SetStatus('Ready. Open a .rules file, or pick From/To classes and press ' + '"+ New Conversion".');
end; // constructor

procedure TConvRulesForm.FormCloseHandler(Sender: TObject; var Action: TCloseAction);
begin
  Action:= caFree;
  Application.Terminate;
end;

destructor TConvRulesForm.Destroy;
begin
  FEngine.Free;
  FBook.Free;
  // Both are lazily created (FVisualSet only if the engine answered, FDeclUnits on
  // the first lookup), so both can legitimately still be nil here.
  FVisualSet.Free;
  FComponentSet.Free;
  FPersistentSet.Free;
  FDeclUnits.Free;
  inherited;
end; // destructor

procedure TConvRulesForm.BuildMenu;
const { Indexed by TThemePref -- keep in step with ConvRules.Theme's declaration order. }
  CAPTIONS: array[TThemePref] of string = ('Follow &IDE', '&Light', '&Dark');
var
  LMenu : TMainMenu ;
  LView : TMenuItem ;
  LTheme: TMenuItem ;
  P     : TThemePref;
begin
  LMenu:= TMainMenu.Create(Self);

  LView:= TMenuItem.Create(Self);
  LView.Caption:= '&View';
  LMenu.Items.Add(LView);

  LTheme:= TMenuItem.Create(Self);
  LTheme.Caption:= '&Theme';
  LView.Add(LTheme);

  for P:= Low(TThemePref) to High(TThemePref) do
  begin
    FMnuTheme[P]:= TMenuItem.Create(Self);
    FMnuTheme[P].Caption:= CAPTIONS[P];
    FMnuTheme[P].RadioItem:= True;
    FMnuTheme[P].Tag:= Ord(P);
    FMnuTheme[P].Checked:= (P = GEditorThemePref);
    FMnuTheme[P].OnClick:= ThemeMenuClick;
    LTheme.Add(FMnuTheme[P]);
  end;

  Menu:= LMenu;
end; // procedure

procedure TConvRulesForm.ThemeMenuClick(Sender: TObject);
begin
  SetThemePref(TThemePref((Sender as TMenuItem).Tag));
end;

procedure TConvRulesForm.SetThemePref(APref: TThemePref);
var
  Reg: TRegistry ;
  P  : TThemePref;
begin
  GEditorThemePref:= APref;
  for P:= Low(TThemePref) to High(TThemePref) do
    if FMnuTheme[P] <> nil then
      FMnuTheme[P].Checked:= (P = APref);

  // Persist. A locked/denied HKCU is not worth an error dialog mid-session: the
  // preference still applies now, it just will not survive a restart.
  Reg:= TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKey(EDITOR_REG_KEY, True) then
        Reg.WriteString(EDITOR_REG_THEME, ThemePrefToStr(APref));
    except
      on E: ERegistryException do
        SetStatus('Theme applied for this session, but could not be saved: ' + E.Message);
    end;
  finally
    Reg.Free;
  end; // try

  ApplyTheme(ResolveThemeMode(APref, GEditorIdeTheme), True); // user-driven: report a fallback
end; // procedure

procedure TConvRulesForm.ApplyTheme(AMode: TThemeMode; AInteractive: Boolean = False);
var
  LStyle : string ;
  LFailed: Boolean;
begin
  FThemeMode:= AMode;
  if AMode = tmDark then
    LStyle:= STYLE_DARK
  else
    LStyle:= STYLE_LIGHT;
  // ShowErrorDialog=False: a missing style resource must not pop a modal at start-up.
  LFailed:= not TStyleManager.TrySetStyle(LStyle, False);
  if LFailed then
    TStyleManager.TrySetStyle(TStyleManager.SystemStyleName, False);
  RefreshStatusColor; // seFont is off there, so the style will not do it for us
  if FGrid <> nil then
    FGrid.Invalidate;
  // The user picked a mode and the window barely changed: say why, or the only clue
  // that STYLE_LIGHT/STYLE_DARK have drifted from ConvRulesEditorStyles.rc is that
  // nothing happens. Start-up keeps its silence.
  if LFailed and AInteractive then
    SetError('Theme style "' + LStyle + '" is not linked into this build -- ' + 'fell back to the system style.');
end; // procedure

{ ONE grouped toolbar for every action in this window, in the order a session
  actually runs: file/working-set | mapping | examine | unit rules, each group
  closed by a tbsSeparator. It replaces 19 loose TButtons that were spread over
  four different parents (top panel, pool panel, grid filter bar, Unit Rules tab),
  where the same action's discoverability depended on which tab happened to be up.

  Every OnClick points at the handler the button it replaced already used -- no
  handler body was copied, so there is exactly one implementation of each action.

  Two buttons deliberately did NOT move: the grid filter bar's two "Clear"
  buttons. They are affordances of the TEdit they sit beside, not free-standing
  actions -- they belong to none of the four groups, and two toolbar buttons both
  captioned "Clear" would be unreadable.

  Layout notes that are easy to get wrong on a code-built TToolBar:
   * there is no Add method -- insertion order is decided by the button's Left/Top
     AT THE MOMENT Parent is assigned (TToolBar.ButtonIndex picks the row nearest
     Top, then the slot at Left). Both are therefore parked out past the strip so
     each new button appends to the end of the last row; the real bounds are
     overwritten by the toolbar immediately afterwards.
   * per-button AutoSize is REQUIRED: without it a text-only button keeps the
     toolbar's 23px ButtonWidth and the caption is clipped.
   * Wrapable + the toolbar's own AutoSize let a narrow window wrap to a second
     row and grow, rather than hiding the tail of the strip. }
procedure TConvRulesForm.BuildToolbar;
const
  PARK = 30000; // past the right/bottom edge of any real strip -- see above

  function AddBtn(const ACaption, AHint: string; AHandler: TNotifyEvent): TToolButton;
  begin
    Result:= TToolButton.Create(Self);
    Result.Caption:= ACaption;
    Result.OnClick:= AHandler;
    if AHint <> '' then
    begin
      Result.Hint    := AHint;
      Result.ShowHint:= True;
    end;
    Result.Left:= PARK; Result.Top:= PARK;
    Result.Parent  := FToolbar;
    Result.AutoSize:= True;
  end; // function

  procedure AddSep;
  var
    LSep: TToolButton;
  begin
    LSep:= TToolButton.Create(Self);
    LSep.Style:= tbsSeparator;
    LSep.Width:= 10;
    LSep.Left:= PARK; LSep.Top:= PARK;
    LSep.Parent:= FToolbar;
  end;

begin
  FToolbar:= TToolBar.Create(Self);
  FToolbar.Parent      := Self;
  FToolbar.Top         := 0; // sorts above FPanelTop in the alTop band
  FToolbar.Align       := alTop;
  FToolbar.ShowCaptions:= True;
  FToolbar.Wrapable    := True;
  FToolbar.AutoSize    := True;
  FToolbar.Flat        := True;
  FToolbar.ShowHint    := True;

  // --- file / working set ---
  AddBtn('Open...' , 'Open a conversion .rules file'                            , DoLoad     );
  AddBtn('Save'    , 'Write the canonical DSL back (.bak backup, then validate)', DoSaveClick);
  AddBtn('Validate', 'Run convert-validate over the current model'              , DoValidate );
  AddBtn('Curate...', 'Split / copy / delete / merge blocks across several rule-books, ' + 'or compose them into one file for the engine', DoCurate);
  AddSep;

  // --- mapping: acts on the top pickers, the selected grid row and the pool ---
  AddBtn('+ New Conversion', 'Create a #convert block from the From/To pickers above', DoNewConversion);
  AddBtn(
    'Fill From-classes', 'Add a From-only conversion per component class on the picked unit''s form ' + '(optional -- pick the unit in the "From Unit" box above first)', DoLoadUnit
  );
  AddBtn('Auto-Match', 'Assign every unambiguous, castable property pair', DoAutoMatch);
  FTbAssign  := AddBtn('<- Assign'  , 'Assign the highlighted To leaf (pool, right) to the selected From row', DoAssign  );
  FTbUnassign:= AddBtn('Unassign ->', 'Drop the selected From row''s assignment'                             , DoUnassign);
  FTbFindInFrom:= AddBtn('Find in From', 'Select the From-grid row whose property has the SAME name as the highlighted ' + 'To leaf', DoFindInFrom);
  FTbOnlyType:= AddBtn('Only this type', 'Show only pool leaves whose TYPE matches the highlighted leaf (toggle)', DoOnlyType);
  FTbMappings:= AddBtn('Mappings...', 'Author a conditional #mapping -- one enum VALUE sets several target properties -- ' + 'and #apply it to this conversion', DoMappings);
  AddSep;

  // --- examine ---
  FTbExamine     := AddBtn('Examine...' , 'Pick .dfm/.pas files and mark the From properties they actually use (green)', DoExamine     );
  FTbClearExamine:= AddBtn('Clear marks', 'Drop the current examination and unmark all rows'                           , DoClearExamine);
  AddSep;

  // --- unit rules: the Unit Rules TAB keeps its list; only its buttons moved ---
  AddBtn('+ Swap'       , 'Add #useswap Old -> New1[, New2 ...]'                      , DoAddSwap );
  AddBtn('+ Add unit'   , 'Add #use <unit> -- a unit to ADD to the uses clause'       , DoAddUse  );
  AddBtn('+ Remove unit', 'Add #unuse <unit> -- a unit to REMOVE from the uses clause', DoAddUnuse);
  AddBtn('Delete unit rule', 'Delete the unit rule selected on the Unit Rules tab ' + '(or dismiss the Examine candidate selected there)', DoDeleteUnit);
  AddBtn('Derive units', 'Add #use/#unuse from every #convert To/From type (deduped)', DoDeriveUnits);
  AddBtn('Check units' , 'Report #use/#unuse conflicts (ADD wins)'                   , DoCheckUnits );
end; // begin

{ Enables only what the current selection supports. Several actions were previously always
  enabled and reported an error only when pressed; that is a worse experience than a
  disabled button, and it hid which state each action actually requires. }
procedure TConvRulesForm.UpdateToolbarEnabled;
begin
  FTbAssign.Enabled:= (FActiveHdr >= 0) and (FGrid.Row > 0) and (FPool.ItemIndex >= 0);
  FTbUnassign.Enabled:= (FActiveHdr >= 0) and (FGrid.Row > 0);
  FTbFindInFrom.Enabled:= (FActiveHdr >= 0) and (FPool.ItemIndex >= 0);
  FTbExamine.Enabled:= (FActiveHdr >= 0);
  FTbClearExamine.Enabled:= (Length(FUsedProps) > 0) or (Length(FUnitCandidates) > 0);
  FTbMappings.Enabled:= (FActiveHdr >= 0);
end;

{ FGrid.OnSelectCell -- the grid row is half of the Assign/Unassign gate, so the
  toolbar has to be re-evaluated whenever it moves. CanSelect is left untouched:
  this hook only observes. }
procedure TConvRulesForm.GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
begin
  UpdateToolbarEnabled;
  { ARow, not FGrid.Row: OnSelectCell fires BEFORE the grid commits the move, so
    FGrid.Row is still the OLD row here and the catalog would trail one selection
    behind -- visibly wrong, and wrong in the direction that looks like it works. }
  RefreshConvOptions(ARow);
end;

{ FPool.OnClick -- the pool highlight is the other half of the Assign gate (and
  all of the Find-in-From gate). }
procedure TConvRulesForm.PoolSelectionChanged(Sender: TObject);
begin
  UpdateToolbarEnabled;
end;

procedure TConvRulesForm.BuildUI;
var
  Split1        : TSplitter;
  Split2        : TSplitter;
  SplitForms    : TSplitter;
  LeftPanel     : TPanel   ;
  GridPanel     : TPanel   ;
  PoolPanel     : TPanel   ;
  FormTypesPanel: TPanel   ;
  LblFormHdr    : TLabel   ;
  LblFilter     : TLabel   ;
  BtnRescan     : TButton  ;
  BtnReenable   : TButton  ;
  BtnOpenForm   : TButton  ;
  TabRules      : TTabSheet;
  TabRaw        : TTabSheet;
  TabUnits      : TTabSheet;
begin
  Caption:= 'ConvRulesEditor -- conversion rule-book editor';
  Width:= 1600; Height:= 720;
  Position:= poScreenCenter;

  // Menu bar first: it takes its strip off the top of the client area before the
  // aligned panels below are laid out.
  BuildMenu;

  // --- bottom status bar (created first so it reserves the bottom edge; the top
  //     status label stays too, but this makes the current message visible even
  //     when the window is short and the top toolbar scrolls off) ---
  FStatusBar:= TStatusBar.Create(Self);
  FStatusBar.Parent     := Self;
  FStatusBar.SimplePanel:= True;
  FStatusBar.SimpleText := 'Ready.';

  // --- the one action toolbar (all four groups); claims its strip before the
  //     picker panel below it ---
  BuildToolbar;

  // --- top panel: status line / class builder / project-unit helper / path.
  //     Its four file-action buttons moved to the toolbar, so row 0 is now the
  //     status line alone and gets the full width. ---
  FPanelTop:= TPanel.Create(Self);
  FPanelTop.Top:= 200; // sorts BELOW FToolbar in the alTop band
  FPanelTop.Parent:= Self; FPanelTop.Align:= alTop; FPanelTop.Height:= 122;
  FPanelTop.BevelOuter:= bvNone;

  FLblStatus:= TLabel.Create(Self);
  FLblStatus.Parent:= FPanelTop; FLblStatus.SetBounds(8, 11, 1072, 15);
  // seFont off: with it on, the active style overrides Font.Color and SetError's
  // red would never show. SetStatus resolves its own colour via StyleServices.
  FLblStatus.StyleElements:= FLblStatus.StyleElements - [seFont];

  // --- row 1: From Unit [v]  [Fill From-classes] -- pick a unit first, then its
  //     component classes drop into the rules library as From-only conversions ---
  var LblUnit: TLabel:= TLabel.Create(Self);
  LblUnit.Parent:= FPanelTop; LblUnit.SetBounds(8, 42, 58, 15); LblUnit.Caption:= 'From Unit:';
  FCbUnit:= TComboBox.Create(Self);
  FCbUnit.Parent:= FPanelTop; FCbUnit.SetBounds(68, 39, 276, 23);
  FCbUnit.AutoComplete:= True; FCbUnit.DropDownCount:= 24;
  FCbUnit.Hint:= 'Pick a project unit to add a From-only conversion per component class on its form (optional)';
  FCbUnit.Hint:= 'Pick a project unit -- or Browse... for one outside the project -- '
    + 'to add a From-only conversion per component class on its form (optional)';
  FCbUnit.ShowHint:= True; FCbUnit.OnDropDown:= CbLoadUnits;
  // Picking a unit fills the Unit Rules tab (and the class list) right away; the
  // button is only needed for the engine's component scan. Measured 2026-09-17:
  // with only OnDropDown wired, Browse... + a pick left the tab empty and the
  // operator read that as "6cfaa158 does not work".
  FCbUnit.OnSelect:= CbUnitSelected;
  // Its "Fill From-classes" trigger is the toolbar button of that name.

  // A unit worth converting is often NOT a project member yet -- that is the
  // normal state of legacy code being migrated INTO a project. The combo lists
  // project units only, so without this button there is no way to aim
  // "Fill From-classes" at a loose .pas/.dfm pair.
  var BtnBrowseUnit: TButton:= TButton.Create(Self);
  BtnBrowseUnit.Parent:= FPanelTop; BtnBrowseUnit.SetBounds(350, 39, 90, 23);
  BtnBrowseUnit.Caption:= 'Browse...';
  BtnBrowseUnit.Hint:= 'Pick a .pas/.dfm that is NOT in the project; its full path '
    + 'goes into the From Unit box, then use "Fill From-classes"';
  BtnBrowseUnit.ShowHint:= True;
  BtnBrowseUnit.OnClick := DoBrowseFromUnit;

  // Target surface: DFM = published props only; PAS = public props + public fields.
  // Selects proptree --min-visibility for the From/To trees (engine schema v17).
  var LblSurf: TLabel:= TLabel.Create(Self);
  LblSurf.Parent:= FPanelTop; LblSurf.SetBounds(520, 42, 58, 15); LblSurf.Caption:= 'Surface:';
  FCbSurface:= TComboBox.Create(Self);
  FCbSurface.Parent:= FPanelTop; FCbSurface.SetBounds(580, 39, 190, 23);
  FCbSurface.Style:= csDropDownList;
  FCbSurface.Items.Add('DFM (published props)'      );
  FCbSurface.Items.Add('PAS (public props + fields)');
  FCbSurface.ItemIndex:= 0;
  FCbSurface.Hint:= 'Target surface: DFM = published (DFM-streamable) only; '
    + 'PAS = public props + public fields. Read-only leaves are always hidden.';
  FCbSurface.ShowHint:= True;
  FCbSurface.OnChange:= SurfaceChanged;

  // --- row 2: From [v]  ->  To [v]  [New Conversion] ---
  // FROM holds all source components (TComponent desc, Win32+Win64 union); TO holds
  // target controls (TControl desc, target platform). See LoadAllClasses.
  var LblFrom: TLabel:= TLabel.Create(Self);
  LblFrom.Parent:= FPanelTop; LblFrom.SetBounds(8, 74, 34, 15); LblFrom.Caption:= 'From:';
  FCbFrom:= TComboBox.Create(Self);
  FCbFrom.Parent:= FPanelTop; FCbFrom.SetBounds(44, 71, 300, 23);
  FCbFrom.AutoComplete:= True; FCbFrom.DropDownCount:= 24;
  FCbFrom.Hint:= 'Source components (Win32+Win64) -- type to filter (TEdit, TOvcTable, TTable, ...)';
  FCbFrom.ShowHint:= True; FCbFrom.OnDropDown:= CbLoadClasses;

  var LblArrow: TLabel:= TLabel.Create(Self);
  LblArrow.Parent:= FPanelTop; LblArrow.SetBounds(350, 74, 20, 15); LblArrow.Caption:= '->';
  var LblTo: TLabel:= TLabel.Create(Self);
  LblTo.Parent:= FPanelTop; LblTo.SetBounds(374, 74, 22, 15); LblTo.Caption:= 'To:';
  FCbTo:= TComboBox.Create(Self);
  FCbTo.Parent:= FPanelTop; FCbTo.SetBounds(398, 71, 300, 23);
  FCbTo.AutoComplete:= True; FCbTo.DropDownCount:= 24;
  FCbTo.Hint:= 'Target controls (Win64) -- type to filter (TcxTextEdit, TcxGrid, ...)';
  FCbTo.ShowHint:= True; FCbTo.OnDropDown:= CbLoadClasses;
  // The pair's trigger is the toolbar's "+ New Conversion" button.

  // --- platform selectors: FROM platform / TO platform (re-scope the pickers) ---
  // Combo item order (Win32,Win64,Both) matches TConvPlatform (cpWin32,cpWin64,
  // cpBoth) by ordinal, so ItemIndex <-> Ord(platform) round-trips.
  var LblFromPlat: TLabel:= TLabel.Create(Self);
  LblFromPlat.Parent:= FPanelTop; LblFromPlat.SetBounds(844, 74, 34, 15); LblFromPlat.Caption:= 'FROM';
  FCbFromPlat:= TComboBox.Create(Self);
  FCbFromPlat.Parent:= FPanelTop; FCbFromPlat.SetBounds(882, 71, 80, 23);
  FCbFromPlat.Style:= csDropDownList;
  FCbFromPlat.Items.Add('Win32'); FCbFromPlat.Items.Add('Win64'); FCbFromPlat.Items.Add('Both');
  FCbFromPlat.ItemIndex:= Ord(FFromPlatform);
  FCbFromPlat.Hint:= 'Library platform the FROM types come from'; FCbFromPlat.ShowHint:= True;
  FCbFromPlat.OnChange:= PlatformChanged;

  var LblToPlat: TLabel:= TLabel.Create(Self);
  LblToPlat.Parent:= FPanelTop; LblToPlat.SetBounds(968, 74, 22, 15); LblToPlat.Caption:= 'TO';
  FCbToPlat:= TComboBox.Create(Self);
  FCbToPlat.Parent:= FPanelTop; FCbToPlat.SetBounds(994, 71, 80, 23);
  FCbToPlat.Style:= csDropDownList;
  FCbToPlat.Items.Add('Win32'); FCbToPlat.Items.Add('Win64'); FCbToPlat.Items.Add('Both');
  FCbToPlat.ItemIndex:= Ord(FToPlatform);
  FCbToPlat.Hint:= 'Library platform the TO types come from'; FCbToPlat.ShowHint:= True;
  FCbToPlat.OnChange:= PlatformChanged;

  FLblFile:= TLabel.Create(Self);
  FLblFile.Parent:= FPanelTop; FLblFile.SetBounds(8, 101, 1080, 15);
  FLblFile.Caption:= '(no file)';

  // --- leftmost: the types ON the examined form ---
  // Created BEFORE LeftPanel so it wins the leftmost alLeft slot: VCL orders same-
  // aligned siblings by creation, so swapping these two swaps the columns.
  FormTypesPanel:= TPanel.Create(Self);
  FormTypesPanel.Parent:= Self; FormTypesPanel.Align:= alLeft; FormTypesPanel.Width:= 300;
  FormTypesPanel.BevelOuter:= bvNone;

  LblFormHdr:= TLabel.Create(Self);
  LblFormHdr.Parent:= FormTypesPanel; LblFormHdr.SetBounds(6, 8, 288, 15);
  LblFormHdr.Caption:= 'Types on form (Examine to fill)';

  BtnOpenForm:= TButton.Create(Self);
  BtnOpenForm.Parent:= FormTypesPanel; BtnOpenForm.SetBounds(6, 26, 90, 23);
  BtnOpenForm.Caption := 'Open form...';
  BtnOpenForm.Hint    := 'Browse for a .dfm/.pas; its sibling is loaded too';
  BtnOpenForm.ShowHint:= True;
  BtnOpenForm.OnClick := DoOpenForm;

  BtnRescan:= TButton.Create(Self);
  BtnRescan.Parent:= FormTypesPanel; BtnRescan.SetBounds(102, 26, 92, 23);
  BtnRescan.Caption := 'Rescan rules';
  BtnRescan.Hint    := 'Re-read the rules folder and rebuild the coverage index';
  BtnRescan.ShowHint:= True;
  BtnRescan.OnClick := RescanRulesFolder;

  BtnReenable:= TButton.Create(Self);
  BtnReenable.Parent:= FormTypesPanel; BtnReenable.SetBounds(200, 26, 94, 23);
  BtnReenable.Caption := 'Re-enable';
  BtnReenable.Hint    := 'Ignore the filter for the selected type (toggles)';
  BtnReenable.ShowHint:= True;
  BtnReenable.OnClick := ToggleFormTypeSkip;

  FChkStdCtrls:= TCheckBox.Create(Self);
  FChkStdCtrls.Parent:= FormTypesPanel; FChkStdCtrls.SetBounds(6, 54, 288, 17);
  FChkStdCtrls.Caption:= 'Exclude standard VCL / FMX controls';
  FChkStdCtrls.OnClick:= FilterChanged;

  LblFilter:= TLabel.Create(Self);
  LblFilter.Parent:= FormTypesPanel; LblFilter.SetBounds(6, 76, 288, 15);
  LblFilter.Caption:= 'Exclude (one regex per line, any match):';

  FFilterMemo:= TMemo.Create(Self);
  FFilterMemo.Parent:= FormTypesPanel; FFilterMemo.SetBounds(6, 94, 288, 60);
  FFilterMemo.ScrollBars:= ssVertical;
  FFilterMemo.OnChange  := FilterChanged;

  { Was the retired rules-library "filter by To type" box. It is now the class
    SEARCH: a partial, case-insensitive match that changes only which rows are
    visible. It must never change a check state -- a search that silently
    unmarked work would make the progress line a lie. }
  FRulesFilter:= TEdit.Create(Self);
  FRulesFilter.Parent:= FormTypesPanel;
  FRulesFilter.SetBounds(6, 154, 288, 21);  // dl:ok magic-literal@19cc, large-magic-number@19cc -- Task 8; same unnamed SetBounds coordinate idiom used by every control in BuildUI
  FRulesFilter.TextHint:= 'find a class...';
  FRulesFilter.OnChange:= ClassSearchChange;

  FLblFormTypes:= TLabel.Create(Self);
  FLblFormTypes.Parent:= FormTypesPanel; FLblFormTypes.SetBounds(6, 179, 288, 15);  // dl:ok multiple-statements-per-line@dda5, magic-literal@dda5, large-magic-number@dda5 -- Task 8; shifted down to sit under the new class-search box, same unnamed-coordinate idiom as its siblings
  FLblFormTypes.Caption:= '';

  { Form types list: reduced height to make room for the rules list below it.
    A checklist, not a plain listbox -- the box IS the skip/re-enable control;
    ToggleFormTypeSkip's button remains as the keyboard/no-mouse path to the
    same decision. }
  FFormTypeList:= TCheckListBox.Create(Self);
  FFormTypeList.Parent:= FormTypesPanel;
  FFormTypeList.SetBounds(6, 197, 288, 170);  // dl:ok magic-literal@264f, large-magic-number@264f -- Task 8; shifted down to clear the class-search box + progress label, same unnamed-coordinate idiom as its siblings
  FFormTypeList.Anchors:= [akLeft, akTop, akRight];
  FFormTypeList.Style     := lbOwnerDrawFixed;
  FFormTypeList.ItemHeight:= 18;
  FFormTypeList.OnDrawItem  := FormTypeDrawItem;
  FFormTypeList.OnClick     := FormTypeClick;
  FFormTypeList.OnDblClick  := FormTypeDblClick;
  FFormTypeList.OnClickCheck:= FormTypeCheckClick;

  { Rules list: relocated from TabRules into FormTypesPanel below the form types list.
    This consolidates the two redundant left lists into one form-types-driven view. }
  var LblRulesForType: TLabel:= TLabel.Create(Self);
  LblRulesForType.Parent:= FormTypesPanel; LblRulesForType.SetBounds(6, 375, 288, 15);  // dl:ok multiple-statements-per-line@35e5, magic-literal@35e5, large-magic-number@35e5 -- Task 8; shifted down since the search box that used to sit here moved above the form-types list
  LblRulesForType.Caption:= 'Rules for selected type:';

  FRules:= TListView.Create(Self);
  FRules.Parent   := FormTypesPanel; FRules.SetBounds(6, 398, 288, 244);
  FRules.Anchors  := [akLeft, akTop, akRight, akBottom];
  FRules.ViewStyle:= vsReport; FRules.ReadOnly     := True;
  FRules.RowSelect:= True    ; FRules.HideSelection:= False;
  FRules.Columns.Add.Caption:= 'To'  ; FRules.Columns[0].Width:= 140;
  FRules.Columns.Add.Caption:= '%'   ; FRules.Columns[1].Width:= 40;
  FRules.OnSelectItem:= RulesSelectItem;

  SplitForms:= TSplitter.Create(Self);
  SplitForms.Parent:= Self; SplitForms.Align:= alLeft; SplitForms.Width:= 4;

  // --- left: rules library + tabs ---
  LeftPanel:= TPanel.Create(Self);
  LeftPanel.Parent:= Self; LeftPanel.Align:= alLeft; LeftPanel.Width:= 380;
  LeftPanel.BevelOuter:= bvNone;

  FTabs:= TPageControl.Create(Self);
  FTabs.Parent:= LeftPanel; FTabs.Align:= alClient;

  { FRules tab superseded 2026-09-16: FRules and FRulesFilter were moved into
    FormTypesPanel below FFormTypeList, consolidating the two redundant left lists.
    This tab now serves as a placeholder and is hidden. }
  TabRules:= TTabSheet.Create(FTabs); TabRules.PageControl:= FTabs;
  TabRules.Caption:= 'Rules Library (retired)';
  TabRules.Visible:= False;

  TabRaw:= TTabSheet.Create(FTabs); TabRaw.PageControl:= FTabs;
  TabRaw.Caption:= 'Raw DSL (all directives)';
  FRaw:= TMemo.Create(Self);
  FRaw.Parent    := TabRaw; FRaw.Align   := alClient;
  FRaw.ScrollBars:= ssBoth; FRaw.WordWrap:= False;
  FRaw.Font.Name:= 'Consolas'; FRaw.Font.Size:= 9;

  // --- Unit Rules tab: #use / #unuse / #useswap authoring + derive/check ---
  TabUnits:= TTabSheet.Create(FTabs); TabUnits.PageControl:= FTabs;
  TabUnits.Caption:= 'Unit Rules';
  // The six authoring buttons that used to sit on a 64px panel here are now the
  // toolbar's "unit rules" group; the tab keeps the list they act on.
  FUnitList:= TListView.Create(Self);
  FUnitList.Parent   := TabUnits; FUnitList.Align        := alClient;
  FUnitList.ViewStyle:= vsReport; FUnitList.ReadOnly     := True;
  FUnitList.RowSelect:= True    ; FUnitList.HideSelection:= False;
  FUnitList.Columns.Add.Caption:= 'Kind'  ; FUnitList.Columns[0].Width:= 70;
  FUnitList.Columns.Add.Caption:= 'Old'   ; FUnitList.Columns[1].Width:= 110;
  FUnitList.Columns.Add.Caption:= 'New(s)'; FUnitList.Columns[2].Width:= 150;
  FUnitList.Columns.Add.Caption:= 'Flag'  ; FUnitList.Columns[3].Width:= 90;

  Split1:= TSplitter.Create(Self);
  Split1.Parent:= Self; Split1.Align:= alLeft; Split1.Left:= LeftPanel.Width + 1;
  Split1.Width:= 4;

  // --- right: 3-column grid (From | To-assigned | cast) + pool ---
  PoolPanel:= TPanel.Create(Self);
  PoolPanel.Parent:= Self; PoolPanel.Align:= alRight; PoolPanel.Width:= 400;
  PoolPanel.BevelOuter:= bvNone;

  // Auto-Match / Find in From / Only this type / Assign / Unassign all moved to
  // the toolbar's "mapping" group; the pool keeps only its search box and list,
  // which is what the freed 140px of height goes to.
  var LblPool: TLabel:= TLabel.Create(Self);
  LblPool.Parent:= PoolPanel; LblPool.SetBounds(6, 8, 388, 15);
  LblPool.Caption:= 'To (unassigned pool) -- search:';

  FPoolFind:= TEdit.Create(Self);
  FPoolFind.Parent:= PoolPanel; FPoolFind.SetBounds(6, 26, 388, 23);
  FPoolFind.Anchors:= [akLeft, akTop, akRight];
  FPoolFind.OnChange:= PoolFilter;

  { The pool loses 148px at the bottom to the conversion catalog below it. Both
    are anchored to akBottom, so the GAP between them is what resizing preserves:
    the pool grows, the catalog keeps its height and stays pinned to the bottom.
    (An alBottom panel would NOT work here -- the pool is positioned by bounds +
    anchors, not Align, so it would slide underneath rather than make room.) }
  FPool:= TListBox.Create(Self);
  FPool.Parent:= PoolPanel; FPool.SetBounds(6, 56, 388, 438);
  FPool.Anchors:= [akLeft, akTop, akRight, akBottom];
  FPool.OnClick:= PoolSelectionChanged;
  // Double-click a To leaf = press "<- Assign". The three-part gesture (grid row +
  // pool leaf + toolbar button) is not discoverable: clicking the obvious thing did
  // nothing at all, because the grid carries no OnDblClick and the pool carried only
  // OnClick. DoAssign is a TNotifyEvent and already reports every precondition it
  // needs via SetStatus, so wiring it directly adds a shortcut without a second copy
  // of the rules -- and without changing what the toolbar button does.
  FPool.OnDblClick:= DoAssign;

  { --- conversion catalog: "what can the selected From property become?" ---
    Read-only and deliberately SMALL. Every other cast API answers the pair
    question (is From->To allowed) because its caller already knew both ends; a
    user picking a From row knows only one. Without this the answer is only
    discoverable by trying targets until one is not refused. }
  FLblConv:= TLabel.Create(Self);
  FLblConv.Parent:= PoolPanel; FLblConv.SetBounds(6, 502, 388, 15);
  FLblConv.Anchors:= [akLeft, akRight, akBottom];
  FLblConv.Caption:= 'Can convert to: (select a From row)';

  FConvList:= TListBox.Create(Self);
  FConvList.Parent:= PoolPanel; FConvList.SetBounds(6, 520, 388, 122);
  FConvList.Anchors:= [akLeft, akRight, akBottom];
  FConvList.Hint:= 'Conversions available FROM the selected row''s type. '
    + 'Identity, scalar casts, and .castlib class/enum casts. Read-only -- '
    + 'pick the actual target in the pool above.';
  FConvList.ShowHint:= True;

  Split2:= TSplitter.Create(Self);
  Split2.Parent:= Self; Split2.Align:= alRight; Split2.Width:= 4;

  GridPanel:= TPanel.Create(Self);
  GridPanel.Parent:= Self; GridPanel.Align:= alClient; GridPanel.BevelOuter:= bvNone;

  // --- grid filter bar: narrow the mapping grid to rows matching a From and/or a
  //     To substring (AND when both are set). Sits above the grid, which stays
  //     alClient beneath it. See RefreshGrid / GridRowMatchesFilter. ---
  var GridFilterPanel: TPanel:= TPanel.Create(Self);
  GridFilterPanel.Parent:= GridPanel; GridFilterPanel.Align     := alTop;
  GridFilterPanel.Height:= 36       ; GridFilterPanel.BevelOuter:= bvNone;

  var LblGridFrom: TLabel:= TLabel.Create(Self);
  LblGridFrom.Parent:= GridFilterPanel; LblGridFrom.SetBounds(6, 9, 66, 15);
  LblGridFrom.Caption:= 'Find in From:';

  FGridFindFrom:= TEdit.Create(Self);
  FGridFindFrom.Parent:= GridFilterPanel; FGridFindFrom.SetBounds(76, 6, 180, 23);
  FGridFindFrom.TextHint:= 'filter From column...';
  FGridFindFrom.Hint    := 'Show only grid rows whose From property contains this text (case-insensitive)';
  FGridFindFrom.ShowHint:= True;
  FGridFindFrom.OnChange:= GridFilterChange;

  var BtnClearGridFrom: TButton:= TButton.Create(Self);
  BtnClearGridFrom.Parent:= GridFilterPanel; BtnClearGridFrom.SetBounds(260, 5, 50, 25);
  BtnClearGridFrom.Caption:= 'Clear'; BtnClearGridFrom.OnClick:= DoClearGridFindFrom;

  var LblGridTo: TLabel:= TLabel.Create(Self);
  LblGridTo.Parent:= GridFilterPanel; LblGridTo.SetBounds(324, 9, 54, 15);
  LblGridTo.Caption:= 'Find in To:';

  FGridFindTo:= TEdit.Create(Self);
  FGridFindTo.Parent:= GridFilterPanel; FGridFindTo.SetBounds(382, 6, 180, 23);
  FGridFindTo.TextHint:= 'filter To column...';
  FGridFindTo.Hint    := 'Show only grid rows whose assigned To property contains this text (case-insensitive)';
  FGridFindTo.ShowHint:= True;
  FGridFindTo.OnChange:= GridFilterChange;

  var BtnClearGridTo: TButton:= TButton.Create(Self);
  BtnClearGridTo.Parent:= GridFilterPanel; BtnClearGridTo.SetBounds(566, 5, 50, 25);
  BtnClearGridTo.Caption:= 'Clear'; BtnClearGridTo.OnClick:= DoClearGridFindTo;

  FLblGridMatch:= TLabel.Create(Self);
  FLblGridMatch.Parent:= GridFilterPanel; FLblGridMatch.SetBounds(626, 9, 160, 15);
  FLblGridMatch.Caption:= '';

  // Examine / Clear marks moved to the toolbar's "examine" group; the second row
  // of this filter bar went with them.

  FGrid:= TStringGrid.Create(Self);
  FGrid.Parent:= GridPanel; FGrid.Align:= alClient;
  // RowCount must stay > FixedRows: start at 2 (header + one blank data row).
  FGrid.ColCount:= 3; FGrid.RowCount:= 2; FGrid.FixedRows:= 1; FGrid.FixedCols:= 0;
  // goColSizing: the user can drag column borders to widen From/To to taste.
  FGrid.Options:= FGrid.Options + [goRowSelect, goVertLine, goHorzLine, goColSizing];
  FGrid.DefaultRowHeight:= 20;
  FGrid.Cells[0, 0]:= 'From property (: type)';
  FGrid.Cells[1, 0]:= 'To (assigned)';
  FGrid.Cells[2, 0]:= 'cast';
  FGrid.ColWidths[0]:= 330; FGrid.ColWidths[1]:= 330; FGrid.ColWidths[2]:= 110;
  // Hand painting entirely to GridDrawCell (header, selection and Examine's green
  // marking all go through it) -- required for OnDrawCell to own the cell colour.
  FGrid.DefaultDrawing:= False;
  FGrid.OnDrawCell    := GridDrawCell;
  FGrid.OnSelectCell  := GridSelectCell; // re-gates the toolbar as the row moves

  // Needs both FGrid and FPool, so it goes after the grid, not next to the pool.
  BuildTypePopup;

  // TLabel is a TGraphicControl, so no style hook reaches it: with Transparent
  // False it fills its own rectangle with Color, which ParentColor resolves to the
  // panel's *property* (clBtnFace, light) no matter how darkly the style PAINTS
  // that panel -- while the caption itself is styled light. Result under the dark
  // style: white text on a white box. Transparent drops the fill, leaving styled
  // text over the styled parent. Applied in one sweep so later labels inherit it.
  for var i:= 0 to ComponentCount - 1 do
    if Components[i] is TLabel then
      TLabel(Components[i]).Transparent:= True;

  // Nothing is selected yet: start the selection-dependent actions disabled
  // rather than enabled-and-complaining.
  UpdateToolbarEnabled;
end; // procedure

{ Re-assert FLblStatus's font for the current message kind. FLblStatus opts out of
  seFont (so SetError's red survives a style), which also means the style will never
  refresh it -- hence this is called on every message AND from ApplyTheme, or a
  status set under dark would keep its pale text after a switch to light. }
procedure TConvRulesForm.RefreshStatusColor;
begin
  if FLblStatus = nil then
    Exit;
  if FStatusIsError then
  begin
    FLblStatus.Font.Color:= clRed;
    FLblStatus.Font.Style:= [fsBold];
  end
  else
  begin
    FLblStatus.Font.Color:= StyleServices.GetSystemColor(clWindowText);
    FLblStatus.Font.Style:= [];
  end;
end; // procedure

procedure TConvRulesForm.SetStatus(const S: string);
begin
  FStatusIsError:= False;
  RefreshStatusColor;
  FLblStatus.Caption:= S;
  if FStatusBar <> nil then
    FStatusBar.SimpleText:= S;
end;

{ Show a message in RED bold -- for blocked assignments and errors. }
procedure TConvRulesForm.SetError(const S: string);
begin
  FStatusIsError:= True;
  RefreshStatusColor;
  FLblStatus.Caption:= S;
  // The status bar has no per-message colour in SimplePanel mode; prefix so an
  // error still reads as one at the bottom of the form.
  if FStatusBar <> nil then
    FStatusBar.SimpleText:= '[!] ' + S;
end;

{ Resolve a leaf's declared type from a proptree ('' if not found). }
function TConvRulesForm.LeafType(const ATree: TProptree; const APath: string): string;
var
  L: TPropLeaf;
begin
  Result:= '';
  for L in ATree.Leaves do
    if SameText(L.Path, APath) then
      Exit(L.TypeName);
end;

{ Whether a leaf is a writable assignment target. Defaults True when the leaf is not
  found or the engine is proptree/1 (IsWritable defaults True) -- never block on
  missing data. }
function TConvRulesForm.LeafWritable(const ATree: TProptree; const APath: string): Boolean;
var
  L: TPropLeaf;
begin
  Result:= True;
  for L in ATree.Leaves do
    if SameText(L.Path, APath) then
      Exit(L.IsWritable);
end;

{ The library class-cast name bridging AFromType -> AToType, or '' if none. }
function TConvRulesForm.ClassCastName(const AFromType, AToType: string): string;
begin
  Result:= ClassCastFor(FCastDefs, AFromType, AToType);
end;

{ Castable when the scalar classifier allows it OR a library class cast bridges it. }
function TConvRulesForm.CanCast(const AFromType, AToType: string): Boolean;
begin
  Result:= IsCastable(AFromType, AToType) or (ClassCastName(AFromType, AToType) <> '');
end;

{ Load the FROM and TO class pickers, once. They are deliberately DIFFERENT sets:

    FROM = all TComponent descendants of the FROM platform's library (default
           Win64) -- the source app has visual controls AND non-visual components
           (BDE TTable, datasets) plus legacy Orpheus TOvc* controls. A
           TControl-only filter (the v1 behaviour) hid all three; TComponent is
           the right superset, since every convertible source component descends
           from it. The default was Win32+Win64 as a "safety net" for components
           indexed under only one platform. Measured 2026-07-29, that net is
           empty: Win64 alone yields the same 6180 names as the union (Win32
           alone yields 3, all of them already in Win64), and TOvcTable is in
           Win64. Pick 'Both' in the FROM combo if a future library split
           reintroduces platform-only components.

    TO   = TControl descendants of the TARGET platform's library only (Win64) --
           conversions target visual controls on the platform being migrated to.

  Falls back to a tiny built-in set if either query yields nothing so the New
  Conversion flow always works. }
{ Each side's DB set = its platform's library index + the shared project DB
  (additive, so project-declared component types still resolve). }
function TConvRulesForm.FromDbSet: TArray<string>;
begin
  Result:= LibDbsFor(FFromPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

function TConvRulesForm.ToDbSet: TArray<string>;
begin
  Result:= LibDbsFor(FToPlatform, GEditorLibDir) + [GEditorProjectDb];
end;

{ The engine's default DB set (proptree/scaffold/validate/qname-resolve) must
  resolve BOTH sides' types + project units -- the deduped union of both sides. }
function TConvRulesForm.EngineDbSet: TArray<string>;
var
  seen: TDictionary<string, Boolean>;
  src : string                      ;
  db  : string                      ;
  arr : TArray<string>              ;
begin
  Result:= [];
  seen:= TDictionary<string, Boolean>.Create;
  try
    for src in ['from', 'to'] do
    begin
      if src = 'from' then
        arr:= FromDbSet
      else
        arr:= ToDbSet;
      for db in arr do
        if not seen.ContainsKey(LowerCase(db)) then
        begin
          seen.Add(LowerCase(db), True);
          Result:= Result + [db];
        end;
    end; // for
  finally
    seen.Free;
  end; // try
end; // function

{ A platform dropdown changed: recompute both sides' platforms from the combos,
  update the engine's default DB set, clear the class caches, and reload the
  pickers so they now list the newly-selected platforms' types. }
procedure TConvRulesForm.PlatformChanged(Sender: TObject);
begin
  FFromPlatform:= TConvPlatform(FCbFromPlat.ItemIndex);
  FToPlatform  := TConvPlatform(FCbToPlat  .ItemIndex);
  FEngine.SetDbs(EngineDbSet);
  // Force LoadAllClasses to re-query (its guard exits when both caches are set).
  FFromClasses:= [];
  FToClasses  := [];
  FCbFrom.Items.Clear;
  FCbTo  .Items.Clear;
  Screen.Cursor:= crHourGlass;
  try
    LoadAllClasses;
    SetStatus(Format(
        'Platforms: FROM=%s TO=%s -- %d source + %d target classes.', [PlatformToStr(FFromPlatform), PlatformToStr(FToPlatform), Length(FFromClasses), Length(FToClasses)]));
  finally
    Screen.Cursor:= crDefault;
  end;
end; // procedure

procedure TConvRulesForm.LoadAllClasses;
var
  FromNames: TArray<string>;
  ToNames  : TArray<string>;
  Err      : string        ;
begin
  if (Length(FFromClasses) > 0) and (Length(FToClasses) > 0) then Exit; // already loaded

  // FROM: TComponent descendants of the FROM platform's library (+ project).
  if not FEngine.ListDescendantsOf('TComponent', FromDbSet, FromNames, Err)
     or (Length(FromNames) = 0) then
    FromNames:= ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit', 'TOvcTable', 'TTable'];
  FFromClasses:= FromNames;

  // TO: TControl descendants of the TO platform's library (+ project).
  if not FEngine.ListDescendantsOf('TControl', ToDbSet, ToNames, Err)
     or (Length(ToNames) = 0) then
    ToNames:= ['TEdit', 'TMemo', 'TButton', 'TLabel', 'TCheckBox', 'TcxTextEdit', 'TcxGrid'];
  FToClasses:= ToNames;

  FCbFrom.Items.BeginUpdate; FCbTo.Items.BeginUpdate;
  try
    FCbFrom.Items.Clear; FCbTo.Items.Clear;
    for var N in FFromClasses do
      FCbFrom.Items.Add(N);
    for var N in FToClasses do
      FCbTo.Items.Add(N);
  finally
    FCbFrom.Items.EndUpdate; FCbTo.Items.EndUpdate;
  end;
end; // procedure

{ Lazy-load the class list the first time a picker is dropped down (enumerating
  every indexed class is slow, so we defer it until actually needed). }
procedure TConvRulesForm.CbLoadClasses(Sender: TObject);
begin
  if (Length(FFromClasses) > 0) and (Length(FToClasses) > 0) then
    Exit;
  Screen.Cursor:= crHourGlass;
  SetStatus('Loading classes from the Library scan (first time only)...');
  try
    Application.ProcessMessages;
    LoadAllClasses;
    SetStatus(Format('%d source (From) + %d target (To) classes available. Type to filter.', [Length(FFromClasses), Length(FToClasses)]));
  finally
    Screen.Cursor:= crDefault;
  end;
end; // procedure

{ Lazy-load the project unit list the first time the From-Unit picker drops. }
procedure TConvRulesForm.CbLoadUnits(Sender: TObject);
var
  Units: TArray<string>;
  Err  : string        ;
begin
  if FUnitsLoaded then
    Exit;
  Screen.Cursor:= crHourGlass;
  SetStatus('Loading project units (first time only)...');
  try
    Application.ProcessMessages;
    if FEngine.ListProjectUnits(Units, Err) then
    begin
      // Browsed (non-project) paths must SURVIVE this load. The user can press
      // Browse... before ever opening the drop-down, and this runs on the first
      // drop-down -- so a plain Clear would silently discard the browsed unit and
      // leave the box showing a name "Fill From-classes" can no longer resolve.
      // A project unit is a bare unit name; a browsed one is a full path, which
      // is what tells them apart.
      var Browsed: TStringList:= TStringList.Create;
      try
        for var i:= 0 to FCbUnit.Items.Count - 1 do
          if TPath.IsPathRooted(FCbUnit.Items[i]) then
            Browsed.Add(FCbUnit.Items[i]);
        var KeepText: string:= FCbUnit.Text;
        FCbUnit.Items.BeginUpdate;
        try
          FCbUnit.Items.Clear;
          for var U in Units do
            FCbUnit.Items.Add(U);
          for var B in Browsed do
            FCbUnit.Items.Add(B);
        finally
          FCbUnit.Items.EndUpdate;
        end;
        FCbUnit.Text:= KeepText;
      finally
        Browsed.Free;
      end; // try
      FUnitsLoaded:= True;
      SetStatus(Format('%d project units available.', [Length(Units)]));
    end // if
    else
      SetError('Could not list project units: ' + Err);
  finally
    Screen.Cursor:= crDefault;
  end; // try
end; // procedure

{ Fill the class list for the picked unit: the .dfm component classes already in
  FFormTypeRows, UNIONED with the classes the unit declares.

  The declared half comes from the engine's `outline`, not from a text scan: a
  text scan cannot read comments or conditionals, and the scan this replaces
  (ScanClassesDeclared) is kept only as the fallback below. When the engine
  cannot answer we say so -- a silently short class list is exactly the failure
  this feature exists to remove.

  MERGES, never overwrites. Before 2026-09-20 this routine rebuilt FFormTypeRows
  from the text scan alone, so choosing a unit replaced its form's component
  classes with the two or three classes the .pas happens to declare.

  The status-line branching (indexed-now / already-answered / failed) is
  ConvRules.FormTypes.DescribeOutlineOutcome, a PURE function with its own
  tests -- moved there because this unit is outside the tests project's
  compile closure and the branching would otherwise have zero coverage. }
function TConvRulesForm.HarvestUnitClasses(const AUnitText, APasPath: string): string;
var
  Classes  : TArray<string>;
  Indexed  : Boolean       ;
  Err      : string        ;
  Guard    : IInterface    ;  // dl:ok write-only-local@b3f5 -- RAII cursor guard: held for its Release side effect at scope exit (HourGlass), never read, same idiom as LGuard elsewhere in this unit
  OutlineOK: Boolean       ;
begin
  Result:= '';
  Guard := HourGlass;
  SetStatus(Format('Reading the classes of %s ...', [ExtractFileName(APasPath)]));
  Application.ProcessMessages;

  OutlineOK:= FEngine.OutlineClasses(APasPath, Classes, Indexed, Err);
  if not OutlineOK then
    Classes:= ScanClassesDeclared(AUnitText);
  Result:= DescribeOutlineOutcome(OutlineOK, Indexed, ExtractFileName(APasPath), Err);

  FFormTypeRows:= MergeClassRows(FFormTypeRows, Classes);
  ApplySkipMarks;
  RefreshFormTypes;
end; // function

{ STUB for Task 9 (ConvRules.SkipList persistence): FSkipList does not exist
  yet, so this has nothing to stamp and is an intentional no-op. Declared and
  called live rather than commented out, per the 2026-09-20 controller ruling --
  a commented-out call site would sit in the tree across Tasks 5-8 and trip
  this repo's own commented-out-code lint rule. Task 9 replaces this body. }
procedure TConvRulesForm.ApplySkipMarks;
begin
  // Intentionally empty until Task 9 wires FSkipList / IsSkipped in.
end; // procedure

{ STUB for Task 9 (ConvRules.SkipList persistence): there is nothing to persist
  to yet, so this has nothing to write and is an intentional no-op. Declared and
  called live rather than commented out, per the 2026-09-20 controller ruling --
  a commented-out call site would sit in the tree across Tasks 6-8 and trip this
  repo's own commented-out-code lint rule. Task 9 replaces this body. }
procedure TConvRulesForm.SaveSkipList;
begin
  // Intentionally empty until Task 9 wires ConvRules.SkipList persistence in.
end; // procedure

{ "Fill From-classes": read the chosen unit's .dfm components and add one FROM-ONLY
  conversion row per distinct component CLASS to the rules library (To unassigned).
  These are CLASSES, not properties, so they go in the rules list -- NOT the grid's
  property column. Selecting a From-only row shows that class's flattened property
  list; assigning a To class then auto-matches. A row with no To (and no links) is
  scratch: SaveComplete drops it, so nothing is written until the user picks a To.
  Existing From classes are skipped (no duplicates). Best-effort: a non-form unit
  (no .dfm) adds nothing. }
{ Read from the FILE, never from the index. A browsed unit is in no index by
  definition, and so is any form its .dproj does not list -- which on this corpus
  includes VARINSP, the form this work targets. The engine's `uses-report` answers
  such a unit with zero rows and exit 0: an empty list that reads as "uses nothing"
  rather than as "not indexed". Measured 2026-09-16.

  A failure is NOTED in the result, not swallowed and not fatal: the unit list is a
  convenience and must not stop the caller, but a silently empty tab is the thing
  this whole feature exists to avoid. }
function TConvRulesForm.HarvestUnitFile(const AUnitName: string): string;
var
  PasPath: string;
  Txt    : string;
begin
  Result := '';
  PasPath:= AUnitName;
  if not TPath.IsPathRooted(PasPath) then
    PasPath:= FEngine.ResolveUnitFile(AUnitName);
  if SameText(ExtractFileExt(PasPath), '.dfm') then
    PasPath:= ChangeFileExt(PasPath, '.pas');
  if (PasPath = '') or not TFile.Exists(PasPath) then
    Exit(Format(' Unit list unavailable: no .pas resolved for %s.', [AUnitName]));

  Txt:= '';
  try
    Txt:= TFile.ReadAllText(PasPath);
  except
    on E: Exception do
      Result:= Format(' Unit list unavailable: %s could not be read (%s).', [ExtractFileName(PasPath), E.Message]);
  end;
  if Txt <> '' then
  begin
    HarvestUsedUnits([Txt]);
    Result:= Result + HarvestUnitClasses(Txt, PasPath);
  end;
end; // function

procedure TConvRulesForm.CbUnitSelected(Sender: TObject);
var
  UnitName: string;
  UsesNote: string;
begin
  UnitName:= Trim(FCbUnit.Text);
  if UnitName = '' then
    Exit;
  UsesNote:= HarvestUnitFile(UnitName);
  SetStatus(Format('From Unit: %s -- %d used unit(s) on the Unit Rules tab; ' + '"Fill From-classes" adds its form components.%s',
    [ExtractFileName(UnitName), Length(FUnitCandidates), UsesNote]));
end; // procedure

procedure TConvRulesForm.DoLoadUnit(Sender: TObject);
var
  UnitName: string        ;
  Types   : TArray<string>;
  Err     : string        ;
  existing: TStringList   ;
  H       : Integer       ;
  added   : Integer       ;
  firstNew: Integer       ;
  UsesNote: string        ;
begin
  UnitName:= Trim(FCbUnit.Text);
  if UnitName = '' then
  begin
    SetError('Pick a unit first -- a project unit from the drop-down, or Browse... ' + 'for one outside the project.');
    Exit;
  end;

  // The unit's own text (uses clauses -> Unit Rules tab, declared classes -> left
  // list) is harvested by HarvestUnitFile, which every unit-picking path shares.
  // Re-run here rather than trusted from the pick: the box is a free-text combo, so
  // what it holds now may not be what was last picked.
  UsesNote:= HarvestUnitFile(UnitName);

  Screen.Cursor:= crHourGlass;
  try
    Application.ProcessMessages;
    // Reads the unit's .dfm and lists the components the designer placed on the
    // form. Not filtered by the picker class set -- legacy components (Orpheus/
    // Raize/DevExpress) are listed even when their ancestry is unresolved.
    if not FEngine.ListControlTypesInUnit(UnitName, nil, Types, Err) then
    begin
      SetError('Could not read unit ' + UnitName + ': ' + Err);
      Exit;
    end;
    if Length(Types) = 0 then
    begin
      { Not a dead end any more: a non-form unit still has uses clauses, and they are
        already on the Unit Rules tab by the time this fires. }
      SetError(Format('No form components found in %s. It may be a non-form unit ' + '(no .dfm), or not indexed. Use the From/To pickers instead. ' + 'Its used units are listed on the Unit Rules tab.%s', [UnitName, UsesNote]));
      Exit;
    end;

    // Skip classes already present as a From in the rules library.
    existing:= TStringList.Create;
    try
      existing.CaseSensitive:= False;
      for H in FBook.ConvertHeaders do
        existing.Add(FBook.Nodes[H].FromType);

      added:= 0; firstNew:= -1;
      for var C in Types do
      begin
        if existing.IndexOf(C) >= 0 then
          Continue;
        if FBook.Nodes.Count > 0 then
        begin
          var Blank: TRuleNode:= TRuleNode.Create;
          Blank.Kind:= rnkBlank; Blank.Raw:= '';
          FBook.Add(Blank);
        end;
        var Hdr: TRuleNode:= TRuleNode.Create;
        Hdr.Kind    := rnkConvert;
        Hdr.FromType:= C;
        Hdr.ToType  := ''; // From-only -- user assigns a To next
        Hdr.Dirty   := True;
        FBook.Add(Hdr);
        if firstNew < 0 then
          firstNew:= FBook.Nodes.Count - 1;
        Inc(added);
        existing.Add(C);
      end; // for
    finally
      existing.Free;
    end; // try

    RefreshRulesList;
    SyncRawFromModel;
    // Select the first newly-added From-only rule so its property list loads.
    if firstNew >= 0 then
      for var k:= 0 to FRules.Items.Count - 1 do
        if Integer(FRules.Items[k].Data) = firstNew then
        begin
          FRules.ItemIndex:= k;
          FRules.Items[k].Selected:= True;
          Break;
        end;

    if added = 0 then
      SetStatus(Format('All %d component class(es) from %s are already in the rules ' + 'library. %d used unit(s) on the Unit Rules tab.%s', [Length(Types), UnitName, Length(FUnitCandidates), UsesNote]))
    else
      SetStatus(Format('Added %d From-only conversion(s) from %s. Pick a To class for ' + 'each you want to convert -- its properties auto-match. ' + '%d used unit(s) on the Unit Rules tab.%s', [added, UnitName, Length(FUnitCandidates), UsesNote]));
  finally
    Screen.Cursor:= crDefault;
  end; // try
end; // procedure

procedure TConvRulesForm.DoLoad(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg:= TOpenDialog.Create(Self);
  try
    Dlg.Filter:= 'Conversion rules (*.rules;*.txt)|*.rules;*.txt|All files (*.*)|*.*';
    if Dlg.Execute then
      LoadFile(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TConvRulesForm.LoadFile(const APath: string);
begin
  if not TFile.Exists(APath) then
  begin
    SetStatus('File not found: ' + APath);
    Exit;
  end;
  FFilePath:= APath;
  FSelectedFormType:= ''; // clear the type filter when loading a new file
  FBook.LoadFromString(TFile.ReadAllText(APath));
  FLblFile.Caption:= APath;
  RefreshRulesList;
  RefreshUnitList;
  SyncRawFromModel;
  FActiveHdr:= -1;
  FGrid.RowCount:= 2; // FixedRows(1) < RowCount; 2 = header + 1 blank
  FGrid.Cells[0, 1]:= ''; FGrid.Cells[1, 1]:= ''; FGrid.Cells[2, 1]:= '';
  FPool.Clear;
  SetStatus(Format('Loaded %d line(s), %d rule(s). Select a rule to edit its mapping.', [FBook.Nodes.Count, Length(FBook.ConvertHeaders)]));
  // Re-gate BEFORE the auto-select below, not after: a file with no #convert rules
  // skips that branch entirely, so LoadGridForBlock's re-gate never runs and the
  // toolbar would still be showing the PREVIOUS file's enabled state over an empty
  // grid. When there IS a rule the auto-select re-gates again a moment later.
  UpdateToolbarEnabled;
  // Auto-select the first rule so the grid shows content immediately (also makes
  // the tool usable if a click ever fails to register). Selecting fires
  // OnSelectItem -> LoadGridForBlock.
  if FRules.Items.Count > 0 then
  begin
    FRules.ItemIndex:= 0;
    FRules.Items[0].Selected:= True;
    FRules.Items[0].Focused := True;
  end;

  { A form supplied with --form is harvested in the CONSTRUCTOR, before any book is
    open. At that moment FRulesFolder is empty and FFilePath is empty, so the catalog
    scan RefreshFormTypes asks for silently exits ("no rules folder yet") and every
    harvested type is left looking UN-RULED.

    Observed 2026-09-09, the first time this editor was ever run: launching with a
    book AND --form listed "33 type(s), 33 active" with nothing greyed, though the
    catalog covers three of them. Pressing Rescan rules by hand fixed it -- which is
    what proved the marking itself works and only its TIMING was wrong.

    That is not cosmetic. An un-ruled type is an invitation to author a rule for it,
    so the failure mode is the user writing a SECOND rule for a type that already has
    one -- precisely the duplicate state FindDuplicates exists to report.

    Opening a book is the moment the folder becomes known, so re-mark here. Guarded on
    both conditions: nothing to do when no form was examined, and an already-built
    catalog is not rebuilt just because another book was opened. }
  if (Length(FFormTypeRows) > 0) and (Length(FCatalog) = 0) then
  begin
    RescanRulesFolder(nil); // sets its own status; the catalog count is the useful
    RefreshFormTypes; // message at this point, not the line/rule count above
  end;
end; // procedure

procedure TConvRulesForm.RefreshRulesList;
begin
  { Retired 2026-09-16: FRules tab is no longer populated. The rules library
    functionality was replaced by loading classes directly from the selected unit. }
  FRules.Items.Clear;
end; // procedure

function TConvRulesForm.BlockPercent(AHdrIdx: Integer): Integer;
var
  Nodes: TArray<TRuleNode>;
  N    : TRuleNode        ;
  total: Integer          ;
  done : Integer          ;
begin
  // % = (links with a real From + ignores) / (links + ignores + unfilled ???)
  // A pragmatic proxy for "F leaves addressed": every #link and #ignore in the
  // block is one addressed F property; a #link still on '???' is not done.
  Nodes:= FBook.NodesInBlock(AHdrIdx);
  total:= 0; done:= 0;
  for N in Nodes do
  begin
    if N.Kind = rnkLink then
    begin
      Inc(total);
      if (N.LinkFrom <> '') and (N.LinkFrom <> '???') then
        Inc(done);
    end
    else if N.Kind = rnkIgnore then
    begin
      Inc(total); Inc(done);
    end;
  end; // for
  if total = 0 then
  begin
    // Nothing countable. That is 0 % only if the block genuinely maps nothing --
    // an #apply-only block has no countable ROWS but is a finished rule, and
    // showing it as 0 % contradicted the save path, which keeps it. Both sides now
    // ask TRuleBook.BlockMapsSomething, so the list and the file cannot disagree.
    if TRuleBook.BlockMapsSomething(Nodes) then
      Exit(100);
    Exit  (0  );
  end;
  Result:= Round(done * 100 / total);
end; // function

procedure TConvRulesForm.RulesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected then
    Exit;
  if Item = nil then
    Exit;
  LoadGridForBlock(Integer(Item.Data));
end;

function TConvRulesForm.ActiveLinks: TArray<TRuleNode>;
begin
  if FActiveHdr < 0 then
    Exit(nil);
  Result:= FBook.LinksForBlock(FActiveHdr);
end;

function TConvRulesForm.FindLinkForFrom(const AFromPath: string): TRuleNode;
var
  N: TRuleNode;
begin
  Result:= nil;
  for N in ActiveLinks do
    if SameText(N.LinkFrom, AFromPath) then
      Exit(N);
end;

procedure TConvRulesForm.LoadGridForBlock(AHdrIdx: Integer);
var
  Node    : TRuleNode;
  Err     : string   ;
  FromNote: string   ;
  ToNote  : string   ;
  Notes   : string   ;
begin
  var LGuard: IInterface:= HourGlass;
  FActiveHdr:= AHdrIdx;
  // A fresh block: drop any pool type-narrowing carried over from the last selection.
  FPoolTypeFilter:= '';
  if FTbOnlyType <> nil then
    FTbOnlyType.Caption:= 'Only this type';
  Node:= FBook.Nodes[AHdrIdx];
  // Mirror the rule's From/To into the top pickers, so a From-only rule can have a
  // To assigned there (there is otherwise no way to set the To for a picked rule).
  FCbFrom.Text:= Node.FromType;
  FCbTo  .Text:= Node.ToType;
  SetStatus(Format('Loading property trees for %s -> %s ...', [Node.FromType, Node.ToType]));
  Application.ProcessMessages;

  // fetch F + T trees from the engine. The From tree always loads (a From-only
  // rule still shows its flattened property list); the To tree loads only once a
  // To class has been assigned.
  FromNote:= ''; ToNote:= '';
  if not FEngine.GetProptree(Node.FromType, FFromTree, Err, FromNote, FSurfaceMinVis) then
  begin
    SetStatus('From tree: ' + Err);
    FFromTree:= Default(TProptree);
  end;
  if Trim(Node.ToType) = '' then
    FToTree:= Default(TProptree) // From-only rule: no To tree yet
  else if not FEngine.GetProptree(Node.ToType, FToTree, Err, ToNote, FSurfaceMinVis) then
  begin
    SetStatus('To tree: ' + Err);
    FToTree:= Default(TProptree);
  end;
  // A bare class name that several units declare resolved by row order alone, so the
  // tree on screen may belong to the wrong framework. Say which one was used -- this
  // rides on the SUCCESS path, so it has to be carried down to the final SetStatus
  // rather than announced here, where the leaf-count message would erase it.
  Notes:= '';
  if FromNote <> '' then
    Notes:= Notes + '  ' + FromNote;
  if ToNote <> '' then
    Notes:= Notes + '  ' + ToNote;

  // Loading a different rule: a filter left over from the last selection would
  // silently narrow (or empty) the new grid and look like missing data, so clear
  // both grid filters the same way FPoolTypeFilter is auto-cleared above.
  FGridFindFrom.Text:= '';
  FGridFindTo  .Text:= '';
  RefreshGrid;

  RefreshPool;
  // The examined file set is session state, not rule state (Task 4 brief): a block
  // switch must NOT clear FUsedProps, and GridDrawCell re-applies the marking to
  // the freshly-loaded rows on its own (it reads FUsedProps live at paint time).
  // Only the status line needs an explicit hand here, since the plain leaf-count
  // message below would otherwise silently replace the examination summary.
  if FExamineInfo <> '' then
    SetStatus(FExamineInfo + Notes)
  else
    SetStatus(Format('%s -> %s : %d From leaves, %d To leaves.', [Node.FromType, Node.ToType, Length(FFromTree.Leaves), Length(FToTree.Leaves)]) + Notes);
  // A rule is now active: the actions that needed one become reachable. Every
  // "a rule was selected" path (RulesSelectItem, LoadFile's auto-select,
  // DoNewConversion, SurfaceChanged) lands here, so this is the single hook.
  UpdateToolbarEnabled;
end; // procedure

{ Refill the grid from FFromTree.Leaves, keeping only rows that pass the active
  From/To filter boxes (GridRowMatchesFilter; AND, case-insensitive substring,
  '' = no constraint on that side). Column 1 = the To assigned to that From leaf
  (from #link), column 2 = its cast, exactly as LoadGridForBlock used to fill
  them directly. Hiding rows only changes what is DISPLAYED -- DoAssign /
  DoUnassign / DoFindInFrom all read the SELECTED ROW'S CELL TEXT rather than
  indexing into FFromTree.Leaves by row number, so a filtered grid does not break
  them. Called once from LoadGridForBlock after the trees are (re)loaded, and
  again on every keystroke in either filter box via GridFilterChange.

  A From leaf with no #link may still be spoken for: an applied #mapping can decide it
  conditionally, and such a row shows '<conditional: N cases>' in the To column rather
  than reading as unassigned. The conditional list is built ONCE per refresh (the two
  passes below both consult it), because the alternative is rescanning every node for
  every leaf. }
procedure TConvRulesForm.RefreshGrid;
var
  i         : Integer                 ;
  r         : Integer                 ;
  matched   : Integer                 ;
  Leaf      : TPropLeaf               ;
  Link      : TRuleNode               ;
  fromCell  : string                  ;
  toCell    : string                  ;
  fromFilter: string                  ;
  toFilter  : string                  ;
  conds     : TArray<TConditionalFrom>;

  { The To cell for a From leaf: its #link target, else the conditional marker, else ''. }
  function ToCellFor(const APath: string; ALink: TRuleNode): string;
  var
    N: Integer;
  begin
    if ALink <> nil then
      Exit(PropCellText(ALink.LinkTo, LeafType(FToTree, ALink.LinkTo)));
    N:= ConditionalCasesOf(conds, APath);
    if N > 0 then
      Result:= Format('<conditional: %d cases>', [N])
    else
      Result:= '';
  end;

begin
  fromFilter:= Trim(FGridFindFrom.Text);
  toFilter  := Trim(FGridFindTo  .Text);
  conds:= ActiveConditionals;

  matched:= 0;
  for i:= 0 to High(FFromTree.Leaves) do
  begin
    Leaf:= FFromTree.Leaves[i];
    fromCell:= PropCellText(Leaf.Path, Leaf.TypeName);
    Link:= FindLinkForFrom(Leaf.Path);
    toCell:= ToCellFor(Leaf.Path, Link);
    if GridRowMatchesFilter(fromCell, toCell, fromFilter, toFilter) then
      Inc(matched);
  end;

  // RowCount must stay > FixedRows (1); a filter matching nothing still needs at
  // least one blank data row.
  FGrid.RowCount:= Max(2, matched + 1);
  for r:= 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0, r]:= ''; FGrid.Cells[1, r]:= ''; FGrid.Cells[2, r]:= '';
  end;

  r:= 1;
  for i:= 0 to High(FFromTree.Leaves) do
  begin
    Leaf:= FFromTree.Leaves[i];
    fromCell:= PropCellText(Leaf.Path, Leaf.TypeName);
    Link:= FindLinkForFrom(Leaf.Path);
    toCell:= ToCellFor(Leaf.Path, Link);
    if not GridRowMatchesFilter(fromCell, toCell, fromFilter, toFilter) then
      Continue;
    FGrid.Cells[0, r]:= fromCell;
    // 'Path : Type' for a #link, '<conditional: N cases>' for a mapped leaf, '' for
    // an unassigned one. A conditional row has no cast: the mapping sets values, it
    // does not convert one.
    FGrid.Cells[1, r]:= toCell;
    if Link <> nil then
      FGrid.Cells[2, r]:= Link.Cast
    else
      FGrid.Cells[2, r]:= '';
    Inc(r);
  end; // for

  if FLblGridMatch <> nil then
    if (fromFilter <> '') or (toFilter <> '') then
      FLblGridMatch.Caption:= Format('Showing %d of %d', [matched, Length(FFromTree.Leaves)])
    else
      FLblGridMatch.Caption:= Format('%d row(s)', [Length(FFromTree.Leaves)]);
end; // begin

{ Shared OnChange for both grid filter boxes -- narrows the grid to the current
  From/To substrings on every keystroke. Guarded like PoolFilter: no active block
  means no trees to filter yet. }
procedure TConvRulesForm.GridFilterChange(Sender: TObject);
begin
  if FActiveHdr >= 0 then
    RefreshGrid;
end;

{ Clear button for the From grid filter: empties only its own box and refreshes. }
procedure TConvRulesForm.DoClearGridFindFrom(Sender: TObject);
begin
  FGridFindFrom.Text:= '';
  if FActiveHdr >= 0 then
    RefreshGrid;
end;

{ Clear button for the To grid filter: empties only its own box and refreshes. }
procedure TConvRulesForm.DoClearGridFindTo(Sender: TObject);
begin
  FGridFindTo.Text:= '';
  if FActiveHdr >= 0 then
    RefreshGrid;
end;

procedure TConvRulesForm.RefreshPool;
var
  Assigned: TDictionary<string, Boolean>;
  Link    : TRuleNode                   ;
  Leaf    : TPropLeaf                   ;
  Filter  : string                      ;
  Target  : string                      ;
begin
  // pool = T leaves not currently assigned to any From (via #link ToPath)
  Assigned:= TDictionary<string, Boolean>.Create;
  try
    for Link in ActiveLinks do
      if Link.LinkTo <> '' then
        Assigned.AddOrSetValue(LowerCase(Link.LinkTo), True);
    // A target an applied #mapping sets IS assigned -- by the mapping rather than by a
    // #link -- so a pool that still offered it would be lying about the block.
    for Target in MappedTargetPaths(FBook.Nodes.ToArray, ActiveAppliedNames) do
      Assigned.AddOrSetValue(LowerCase(Target), True);

    Filter:= LowerCase(Trim(FPoolFind.Text));
    FPool.Items.BeginUpdate;
    try
      FPool.Items.Clear;
      for Leaf in FToTree.Leaves do
        if Leaf.IsWritable then // hide read-only (invalid) targets
          if not Assigned.ContainsKey(LowerCase(Leaf.Path)) then
            if (Filter = '') or (Pos(Filter, LowerCase(Leaf.Path)) > 0) then
              if (FPoolTypeFilter = '') or SameText(Leaf.TypeName, FPoolTypeFilter) then
              begin
                var disp: string:= PropCellText(Leaf.Path, Leaf.TypeName);
                // public members are code-only -- tag so a DFM rule sees they won't
                // stream to a .dfm (published targets carry no tag).
                if SameText(Leaf.Visibility, 'public') then
                  disp:= disp + '   (PAS-only)';
                FPool.Items.Add(disp);
              end;
    finally
      FPool.Items.EndUpdate;
    end; // try
  finally
    Assigned.Free;
  end; // try
end; // procedure

procedure TConvRulesForm.PoolFilter(Sender: TObject);
begin
  if FActiveHdr >= 0 then
    RefreshPool;
end;

function PathOfGridCell(const S: string): string;
var
  P: Integer;
begin
  P:= Pos(' : ', S);
  if P > 0 then
    Result:= Copy(S, 1, P - 1)
  else
    Result:= S;
end;

{ The type token of a 'Path : Type [tag]' grid/pool cell ('' when there is no ' : ').
  Takes only the first token after ' : ' so a trailing display tag (e.g. the
  '(PAS-only)' pool marker) does not corrupt a type comparison. }
function TypeOfCell(const S: string): string;
var
  P : Integer;
  sp: Integer;
begin
  Result:= '';
  P:= Pos(' : ', S);
  if P <= 0 then
    Exit;
  Result:= Trim(Copy(S, P + 3, MaxInt));
  sp:= Pos(' ', Result);
  if sp > 0 then
    Result:= Copy(Result, 1, sp - 1);
end;

{ The last dotted segment of a property path ('Font.Color' -> 'Color'). }
function LeafNameOf(const APath: string): string;
var
  d: Integer;
begin
  Result:= APath;
  d:= LastDelimiter('.', Result);
  if d > 0 then
    Result:= Copy(Result, d + 1, MaxInt);
end;

{ Whether one grid row passes the grid's two filter boxes. AND semantics: with
  both filters set, BOTH must match; an empty filter imposes no constraint on
  its side. Case-insensitive substring, consistent with the pool search
  (PoolFilter). The one place this comparison is defined -- RefreshGrid just
  calls it per row. }
function GridRowMatchesFilter(const AFromCell, AToCell, AFromFilter, AToFilter: string): Boolean;
begin
  Result:= ((AFromFilter = '') or (Pos(LowerCase(AFromFilter), LowerCase(AFromCell)) > 0))
        and ((AToFilter = '') or (Pos(LowerCase(AToFilter), LowerCase(AToCell)) > 0));
end;

{ ---- Go to definition -------------------------------------------------------

  A cell in the grid or the pool reads 'Path : Type'. That Type is the one piece of
  the editor a user regularly needs to look AT rather than assign: what are the
  legal values of TabcButtonStyle, what is TdxAlignment really. Right-click resolves
  it through the engine and asks the RUNNING IDE to open the declaration, so the
  answer arrives in the editor already open rather than in a second bds.exe. }

procedure TConvRulesForm.BuildTypePopup;
begin
  FTypePopup:= TPopupMenu.Create(Self);

  FMnuGotoDef:= TMenuItem.Create(Self);
  // A placeholder: GridPoolContextPopup rewrites this with the actual type before
  // the menu is ever shown, and suppresses the menu when there is no type.
  FMnuGotoDef.Caption:= 'Go to definition';
  FMnuGotoDef.OnClick:= DoGoToDefinition;
  FTypePopup.Items.Add(FMnuGotoDef);

  // ONE popup on both controls: the cells share the 'Path : Type' shape, and
  // OnContextPopup's Sender tells the handler which one was clicked.
  FGrid.PopupMenu     := FTypePopup;
  FPool.PopupMenu     := FTypePopup;
  FGrid.OnContextPopup:= GridPoolContextPopup;
  FPool.OnContextPopup:= GridPoolContextPopup;
end; // procedure

function TConvRulesForm.TypeAtPos(ASender: TObject; const APos: TPoint): string;
var
  C  : Integer;
  r  : Integer;
  Idx: Integer;
begin
  Result:= '';
  if ASender = FPool then
  begin
    // Existing=True: past the last item this returns -1 rather than the nearest row.
    Idx:= FPool.ItemAtPos(APos, True);
    if (Idx >= 0) and (Idx < FPool.Items.Count) then
      Result:= TypeOfCell(FPool.Items[Idx]);
  end
  else if ASender = FGrid then
  begin
    FGrid.MouseToCell(APos.X, APos.Y, C, r);
    // R = 0 is the header and R < 0 is off-grid; the cast column holds no ' : Type'
    // so TypeOfCell returns '' for it without a column test.
    if (C >= 0) and (r >= 1) then
      Result:= TypeOfCell(FGrid.Cells[C, r]);
  end;
end; // function

procedure TConvRulesForm.GridPoolContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  FCtxType:= TypeAtPos(Sender, MousePos);
  if FCtxType = '' then
  begin
    Handled:= True; // nothing to offer here -> show no menu at all
    Exit;
  end;
  FMnuGotoDef.Caption:= 'Go to definition of ' + FCtxType;
end;

procedure TConvRulesForm.DoGoToDefinition(Sender: TObject);
var
  LFile   : string        ;
  LErr    : string        ;
  LWhere  : string        ;
  LMsg    : string        ;
  LLine   : Integer       ;
  LAmbig  : Integer       ;
  LMembers: TArray<string>;
begin
  if FCtxType = '' then
    Exit;
  // Both engine calls run on this thread (RunCapture drains here), so the window
  // is unresponsive for their duration -- say so with the cursor.
  var LGuard: IInterface:= HourGlass;

  if not FEngine.ResolveTypeLocation(FCtxType, LFile, LLine, LErr, LAmbig) then
  begin
    SetError(LErr);
    Exit;
  end;
  LWhere:= Format('%s:%d', [LFile, LLine]);
  LMsg:= FCtxType + ' -- ' + LWhere;

  // Several equally-ranked declarations carried this name and the engine's row order
  // picked one. That happens on types the grid shows constantly -- TAlignment has
  // three, TColor two -- so it is said out loud rather than presented as the answer.
  // The unit is the file's base name, which is what makes "opened System.Classes"
  // readable at a glance next to the full path.
  if LAmbig > 1 then
    LMsg:= Format('%d declarations named %s; opened %s.  ', [LAmbig, FCtxType, ChangeFileExt(ExtractFileName(LFile), '')]) + LMsg;

  // For an enum the member list is usually the actual question ("what can Style
  // be?"), so it rides along. A failure here is NOT reported: the location is
  // still good, and most types are simply not enums.
  if FEngine.EnumMembersOf(FCtxType, LMembers, LErr) and (Length(LMembers) > 0) then
    LMsg:= LMsg + '  (' + string.Join(', ', LMembers) + ')';

  if SendOpenSource(LFile, LLine) then
    SetStatus('Opened in the IDE: ' + LMsg)
  else
    // No plugin answered the pipe (no IDE running, or its BPL is not loaded).
    // Failing silently is the one unacceptable outcome, so hand over something
    // pasteable and say why.
  try
    Clipboard.AsText:= LWhere;
    SetStatus('No IDE is listening -- copied to the clipboard: ' + LMsg);
  except
    on E: Exception do
      SetStatus('No IDE is listening, and the clipboard refused (' + E.Message + '): ' + LMsg);
  end;
end; // procedure

{ Examine: pick .dfm/.pas files and ask ConvRules.Usage.ComputeUsage which of the active
  rule's From properties they actually assign or reference, so the grid can be triaged
  down from thousands of leaves to the handful a real form touches. Read-only -- only
  TFile.ReadAllText is called on the chosen files, nothing is ever written. Requires a
  selected #convert rule (FActiveHdr >= 0); the From class comes from FBook, not the
  picker text, so it is always in sync with the grid currently on screen.

  The same .pas texts are also run through ScanUsesClauses, and the units they name
  become CANDIDATE rows on the Unit Rules tab -- a work list, not an edit. The rule
  book is not touched by any of this. }
function TConvRulesForm.DuplicateSitesFor(const ATypeName: string): Integer;
var
  Dup : TCatalogDuplicate;
  Want: string           ;
begin
  Result:= 0;
  Want:= BareTypeName(ATypeName);
  if Want = '' then
    Exit;
  for Dup in FCatalogDups do
    if SameText(BareTypeName(Dup.FromType), Want) then
      Exit(Length(Dup.Entries));
end;

function TConvRulesForm.DeclaringUnitCached(const ATypeName: string): string;
begin
  if FDeclUnits = nil then
    FDeclUnits:= TDictionary<string, string>.Create;
  if FDeclUnits.TryGetValue(UpperCase(ATypeName), Result) then
    Exit;
  Result:= FEngine.DeclaringUnitOf(ATypeName);
  FDeclUnits.AddOrSetValue(UpperCase(ATypeName), Result);
end;

procedure TConvRulesForm.HarvestFormTypes(const ADfmTexts: TArray<string>);
var
  Parts: TArray<TFormTypeRows>;
  Old  : TFormTypeRows        ;
  Txt  : string               ;
  Names: TArray<string>       ;
  Err  : string               ;
  N    : string               ;
  i    : Integer              ;
  j    : Integer              ;
begin
  Old:= FFormTypeRows;
  Parts:= nil;
  for Txt in ADfmTexts do
    Parts:= Parts + [ScanDfmTypes(Txt)];
  FFormTypeRows:= MergeFormTypes(Parts);

  // A manual re-enable is the user's decision about a TYPE, not about a scan, so it
  // survives re-Examining the same form. Without this, re-running Examine would
  // silently undo every override.
  for i:= 0 to High(FFormTypeRows) do
  for j:= 0 to High(Old          ) do
      if SameText(Old[j].TypeName, FFormTypeRows[i].TypeName) then
      begin
        FFormTypeRows[i].Skipped:= Old[j].Skipped;
        Break;
      end;

  // Three descendant sets, once per session. Non-fatal: if the engine cannot
  // answer, rows stay '?' rather than being labelled non-visual on no evidence.
  if FVisualSet = nil then
  begin
    var LGuard: IInterface:= HourGlass;
    FVisualSet    := LoadDescendantSet('TControl'   );
    FComponentSet := LoadDescendantSet('TComponent' );
    FPersistentSet:= LoadDescendantSet('TPersistent');
  end;

  if Length(FCatalog) = 0 then
    RescanRulesFolder(nil);
  RefreshFormTypes;
end; // procedure

function TConvRulesForm.LoadDescendantSet(const AAncestor: string): TStringList;
var
  Names: TArray<string>;
  Err  : string        ;
  N    : string        ;
begin
  Result:= TStringList.Create;
  Result.Sorted       := True;
  Result.Duplicates   := dupIgnore;
  Result.CaseSensitive:= False;
  if not FEngine.ListDescendantsOf(AAncestor, Names, Err) then
    Exit;
  for N in Names do
    if Trim(N) <> '' then
      Result.Add(Trim(N));
end; // function

procedure TConvRulesForm.FilterChanged(Sender: TObject);
begin
  RefreshFormTypes;
end;

function TConvRulesForm.SelectedRowIndex: Integer;
begin
  Result:= -1;
  if FFormTypeList = nil then
    Exit;
  Result:= ResolveSelectedRow(FVisibleRows, FFormTypeList.ItemIndex, Length(FFormTypeRows));
end;

function TConvRulesForm.ClassSearchText: string;
begin
  if FRulesFilter = nil then
    Exit('');
  Result:= Trim(FRulesFilter.Text);
end;

procedure TConvRulesForm.RefreshFormTypes;
var
  Pats  : TArray<string>   ;  // dl:ok write-only-local@266c -- Task 4 removed its only reader (the TypeIsExcluded call); Task 9 restores it on the Apply button
  Err   : string           ;  // dl:ok unused-local@a11c -- same removal; Task 9 restores the filter-error propagation
  DeclU : string           ;  // dl:ok write-only-local@ca0c -- same removal; still computed for the standard-controls check, consumed again once TypeIsExcluded is back
  Entry : TRuleCatalogEntry;
  i     : Integer          ;
  Cold  : Integer          ;
  VisIdx: Integer          ; // for-in var over FVisibleRows -- kept distinct from i so nothing can read a for-in loop var's undefined post-loop value
  k     : Integer          ; // indexed (not for-in) restore loop below -- Checked[] needs the list SLOT, not just the row
  Cnt   : TRowCounts       ;
begin
  if (FFormTypeList = nil) or (FFilterMemo = nil) then
    Exit;

  Pats:= FFilterMemo.Lines.ToStringArray;
  FFilterError:= '';

  // Resolving a declaring unit costs a process spawn against a multi-GB index
  // (measured 1.7 s each), so it happens ONLY when the standard-controls box is
  // ticked -- the one thing that needs it -- and the user is told what it costs
  // rather than watching a frozen window.
  if FChkStdCtrls.Checked then
  begin
    Cold:= 0;
    for i:= 0 to High(FFormTypeRows) do
      if (FDeclUnits = nil)
         or (not FDeclUnits.ContainsKey(UpperCase(FFormTypeRows[i].TypeName))) then
        Inc(Cold);
    if Cold > 0 then
    begin
      SetStatus(Format('Resolving declaring units for %d type(s) (~%d s) ...', [Cold, Round(Cold * 1.7)]));
      Application.ProcessMessages;
    end;
  end; // if

  for i:= 0 to High(FFormTypeRows) do
  begin
    // Only the standard-controls test needs the unit. Everything else works off
    // the three cached descendant sets.
    if FChkStdCtrls.Checked then
      DeclU:= DeclaringUnitCached(FFormTypeRows[i].TypeName)
    else
      DeclU:= '';

    // '?' is NOT a synonym for non-visual. A type is only tvkNonVisual when the
    // index PLACES it (it descends from TComponent or TPersistent) and it is not a
    // TControl. TField and its kin come through TPersistent, not TComponent, which
    // is why both sets are consulted.
    if (FVisualSet <> nil) and (FVisualSet.IndexOf(FFormTypeRows[i].TypeName) >= 0) then
      FFormTypeRows[i].Visual:= tvkVisual
    else if ((FComponentSet <> nil) and (FComponentSet.IndexOf(FFormTypeRows[i].TypeName) >= 0))
         or ((FPersistentSet <> nil) and (FPersistentSet.IndexOf(FFormTypeRows[i].TypeName) >= 0)) then
      FFormTypeRows[i].Visual:= tvkNonVisual
    else
      FFormTypeRows[i].Visual:= tvkUnknown;

    if FindRuleForType(FCatalog, FFormTypeRows[i].TypeName, Entry) then
    begin
      FFormTypeRows[i].Ruled:= True;
      FFormTypeRows[i].RuledBy:= ExtractFileName(Entry.FilePath);
      // Say it on the ROW, not only in the status line. The status line is gone by
      // the time the user is looking at this type, and picking the wrong one of two
      // rules is a silent mistake.
      if DuplicateSitesFor(FFormTypeRows[i].TypeName) > 1 then
        FFormTypeRows[i].RuledBy:= Format('%s +%d DUPLICATE', [FFormTypeRows[i].RuledBy, DuplicateSitesFor(FFormTypeRows[i].TypeName) - 1]);
    end
    else
    begin
      FFormTypeRows[i].Ruled  := False;
      FFormTypeRows[i].RuledBy:= '';
    end;
  end; // for

  FVisibleRows:= VisibleRowIndexes(FFormTypeRows, ClassSearchText);
  FFormTypeList.Items.BeginUpdate;
  try
    FFormTypeList.Items.Clear;
    for VisIdx in FVisibleRows do
      FFormTypeList.Items.Add(FFormTypeRows[VisIdx].TypeName);
    // Restore the ticked state: FFormTypeList.Items was just rebuilt from
    // scratch, so every checkbox starts unticked until this puts Skipped back.
    for k:= 0 to High(FVisibleRows) do
      FFormTypeList.Checked[k]:= FFormTypeRows[FVisibleRows[k]].Skipped;
  finally
    FFormTypeList.Items.EndUpdate;
  end;

  Cnt:= CountRows(FFormTypeRows);
  FLblFormTypes.Caption:= FormTypesProgressCaption(Cnt, Length(FVisibleRows), FFilterError);
end; // procedure

procedure TConvRulesForm.RescanRulesFolder(Sender: TObject);
var
  Errs  : TArray<string>;
  Folder: string        ;
begin
  Folder:= Trim(FRulesFolder);
  if Folder = '' then
    Folder:= ExtractFilePath(FFilePath);
  if Folder = '' then
  begin
    SetStatus('No rules folder yet -- open a rule book first, then Rescan rules.');
    Exit;
  end;

  FCatalog:= ScanRulesFolder(Folder, Errs);
  FCatalogDups:= FindDuplicates(FCatalog);
  FRulesFolder:= Folder;

  // The index is a CACHE of what the folder says; failing to write it must not
  // invalidate the catalog we just built in memory.
  try
    TFile.WriteAllText(TPath.Combine(Folder, CATALOG_INDEX_FILE), CatalogToIndexText(FCatalog));
  except
    on E: Exception do
      SetStatus('Catalog built, but its index could not be written: ' + E.Message);
  end;

  if Sender <> nil then
  begin
    RefreshFormTypes;

    // A duplicate is louder than an unreadable file: an unreadable file is
    // obviously missing, whereas a duplicate looks like a working corpus right up
    // until two copies of one rule drift apart.
    if Length(FCatalogDups) > 0 then
      SetError(Format(
          '%d conversion(s) from %s -- BUT %d type(s) are claimed by '
            + 'more than one rule, starting with %s in %s and %s. A rule must live in '
            + 'exactly one file; move or delete one.',
          [
            Length(FCatalog), Folder, Length(FCatalogDups), FCatalogDups[0].FromType, ExtractFileName(FCatalogDups[0].Entries[0].FilePath),
            ExtractFileName(FCatalogDups[0].Entries[1].FilePath)]))
    else if Length(Errs) > 0 then
      SetStatus(Format('%d conversion(s) catalogued from %s; %d file(s) unreadable: %s', [Length(FCatalog), Folder, Length(Errs), string.Join('; ', Errs)]))
    else
      SetStatus(Format('%d conversion(s) catalogued from %s.', [Length(FCatalog), Folder]));
  end; // if
end; // procedure

procedure TConvRulesForm.FormTypeClick(Sender: TObject);
var
  i   : Integer;
  Hdr : Integer;
  Entry: TRuleCatalogEntry;
begin
  i:= SelectedRowIndex;
  if i < 0 then
    Exit;

  FCbFrom.Text:= FFormTypeRows[i].TypeName;

  { Set the selected type filter and refresh the rules list to show only rules for this type. }
  FSelectedFormType:= FFormTypeRows[i].TypeName;
  RefreshRulesList;

  // If the type is ruled, load its rule into the grid immediately
  if FFormTypeRows[i].Ruled and FindRuleForType(FCatalog, FFormTypeRows[i].TypeName, Entry) then
  begin
    Hdr:= HeaderIndexFor(FBook, Entry);
    if Hdr >= 0 then
    begin
      LoadGridForBlock(Hdr);
      SetStatus(Format('Loaded rule for %s from %s.', [FFormTypeRows[i].TypeName, ExtractFileName(Entry.FilePath)]));
      Exit;
    end;
  end;

  // Not ruled, or rule lookup failed: set From and wait for user to pick a To class
  if FFormTypeRows[i].Ruled then
    SetStatus(Format('From set to %s -- already converted by %s. Pick a To class, ' + 'then New conversion.', [FFormTypeRows[i].TypeName, FFormTypeRows[i].RuledBy]))
  else
    SetStatus(Format('From set to %s. Pick a To class, then New conversion.', [FFormTypeRows[i].TypeName]));
end; // procedure

procedure TConvRulesForm.FormTypeDblClick(Sender: TObject);
var
  i: Integer;
begin
  i:= SelectedRowIndex;
  if i < 0 then
    Exit;
  if not FFormTypeRows[i].Ruled then
  begin
    SetStatus(Format('%s has no rule yet -- pick a To class and press "+ New ' + 'Conversion".', [FFormTypeRows[i].TypeName]));
    Exit;
  end;
  OpenOwningRule(FFormTypeRows[i].TypeName);
end; // procedure

function TConvRulesForm.OpenOwningRule(const ATypeName: string): Boolean;
var
  Hdr     : Integer          ;
  Sites   : Integer          ;
  Sel     : Integer          ;
  k       : Integer          ;
  Entry   : TRuleCatalogEntry;
  TypeName: string           ;
  Extra   : string           ;
begin
  Result  := False;
  TypeName:= ATypeName;

  // Ask the catalog again rather than trusting the painted row: the row carries a
  // display name, and the catalog may have been rescanned since it was drawn.
  if not FindRuleForType(FCatalog, TypeName, Entry) then
  begin
    SetError(Format('%s is marked as ruled but the catalog no longer has it. ' + 'Press "Rescan rules".', [TypeName]));
    Exit;
  end;

  if not SameText(Entry.FilePath, FFilePath) then
  begin
    if (FFilePath <> '') and (FBook.Nodes.Count > 0) then
    case MessageDlg(
        Format('Open %s to edit the %s rule?' + sLineBreak + sLineBreak + 'Yes = save %s first.' + sLineBreak + 'No  = DISCARD any unsaved edits in it and open the other book.', [ExtractFileName(Entry.FilePath), TypeName, ExtractFileName(FFilePath)]),
        mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrCancel: Exit;
      mrYes   :
        // Same reasoning as DoCurate: if the save failed, opening the other book
        // would throw the edits away. DoSave has already said why -- do not
        // overwrite its message.
        if not DoSave(nil) then
        begin
          SetError('Not opened: the save failed, so your edits are still only in ' + 'this editor and nothing on disk changed.');
          Exit;
        end;
    end; // case
    LoadFile(Entry.FilePath);
  end; // if

  Hdr:= HeaderIndexFor(FBook, Entry);
  if Hdr < 0 then
  begin
    SetError(Format('%s is catalogued in %s but no #convert for it was found there. ' + 'The index is stale -- press "Rescan rules".', [TypeName, ExtractFileName(Entry.FilePath)]));
    Exit;
  end;

  Sel:= -1;
  for k:= 0 to FRules.Items.Count - 1 do
    if Integer(FRules.Items[k].Data) = Hdr then begin Sel:= k; Break; end;
  if Sel >= 0 then
  begin
    FRules.ItemIndex:= Sel;
    FRules.Items[Sel].Selected:= True;
    FRules.Items[Sel].Focused := True;
    FRules.SetFocus;
  end
  else
    // The rule exists in the model but the list is filtered, so no row shows it.
    // Load the grid directly rather than leaving the user staring at the old block.
    LoadGridForBlock(Hdr);

  Sites:= DuplicateSitesFor(TypeName);
  if Sites > 1 then
    Extra:= Format(' -- NOTE %d rules claim %s; this is the first. Move or delete ' + 'the others.', [Sites, TypeName])
  else
    Extra:= '';
  SetStatus(Format('Opened the rule for %s -- %s, line %d.', [TypeName, ExtractFileName(Entry.FilePath), Entry.LineNo]) + Extra);
  Result:= True;
end; // function

procedure TConvRulesForm.ToggleFormTypeSkip(Sender: TObject);
var
  i: Integer;
  k: Integer;
begin
  i:= SelectedRowIndex;
  if i < 0 then
    Exit;
  FFormTypeRows[i].Skipped:= not FFormTypeRows[i].Skipped;
  SaveSkipList;
  RefreshFormTypes;
  // Re-selecting by ROW, not by the old list slot: the refresh may have moved the
  // row (a re-sort, or the search box hiding/revealing others), so k must come
  // from ListIndexForRow rather than reusing the pre-refresh list index.
  k:= ListIndexForRow(FVisibleRows, i);
  if k >= 0 then
    FFormTypeList.ItemIndex:= k;
end;

{ The user ticked or cleared a row's box. Checked means "we are not converting
  this class" -- the decision is the user's, so it is saved immediately rather
  than at some later Save the user may never reach. }
procedure TConvRulesForm.FormTypeCheckClick(Sender: TObject);
var
  i: Integer;
begin
  i:= SelectedRowIndex;
  if i < 0 then
    Exit;
  FFormTypeRows[i].Skipped:= FFormTypeList.Checked[FFormTypeList.ItemIndex];
  SaveSkipList;
  RefreshFormTypes;
end; // procedure

procedure TConvRulesForm.FormTypeDrawItem(AControl: TWinControl; AIndex: Integer; ARect: TRect; AState: TOwnerDrawState);
var
  LB    : TCheckListBox;
  Row   : TFormTypeRow ;
  S     : string       ;
  RowIdx: Integer       ;
begin
  LB:= TCheckListBox(AControl);
  LB.Canvas.FillRect(ARect);
  RowIdx:= ResolveSelectedRow(FVisibleRows, AIndex, Length(FFormTypeRows));
  if RowIdx < 0 then
    Exit;
  Row:= FFormTypeRows[RowIdx];

  // The text itself (origin/mark/name/count/ruled-by) is DescribeFormTypeRow
  // (ConvRules.FormTypes.pas) -- a pure function with its own tests, since this
  // unit is outside the tests project's compile closure. Colour and the
  // skipped strikethrough are VCL painting and stay here.
  S:= DescribeFormTypeRow(Row);

  // Three states, three renderings. Before 2026-09-20 "already ruled" and
  // "filtered out" were the same grey, so the list could not answer the one
  // question it is for: what is still to do.
  if not (odSelected in AState) then
  case RowState(Row) of
    rsSkipped: LB.Canvas.Font.Color:= clGrayText;
    rsRuled  : LB.Canvas.Font.Color:= clGreen   ;
  else
    LB.Canvas.Font.Color:= LB.Font.Color;
  end;

  LB.Canvas.TextOut(ARect.Left + 4, ARect.Top + 1, S);  // dl:ok magic-literal@0acd -- Task 7; a 4px/1px text inset, same unnamed convention as every other TextOut in this owner-draw file
  if RowState(Row) = rsSkipped then
  begin
    // Struck out, so "we decided against this" reads differently from "dimmed
    // because it is selected elsewhere".
    var Y: Integer:= ARect.Top + (ARect.Height div 2);
    LB.Canvas.Pen.Color:= clGrayText;
    LB.Canvas.MoveTo(ARect.Left + 4, Y);  // dl:ok magic-literal@5998 -- Task 7; same 4px inset as the TextOut two lines up, so the strikethrough starts under the text
    LB.Canvas.LineTo(ARect.Left + 4 + LB.Canvas.TextWidth(S), Y);  // dl:ok magic-literal@81a4 -- Task 7; same 4px inset, ends at the text's measured width
  end;
end; // procedure

function TConvRulesForm.ExpandUnitSiblings(const APaths: TArray<string>): TArray<string>;
var
  seen: TStringList;
  P   : string     ;
  Sib : string     ;
  Ext : string     ;

  procedure Take(const APath: string);
  begin
    if (Trim(APath) = '') or (not TFile.Exists(APath)) then
      Exit;
    if seen.IndexOf(APath) >= 0 then
      Exit;
    seen.Add(APath);
    Result:= Result + [APath];
  end;

begin
  Result:= nil;
  seen:= TStringList.Create;
  try
    seen.CaseSensitive:= False;
    for P in APaths do
    begin
      Take(P);
      Ext:= LowerCase(ExtractFileExt(P));
      if Ext = '.pas' then
        Sib:= ChangeFileExt(P, '.dfm')
      else if Ext = '.dfm' then
        Sib:= ChangeFileExt(P, '.pas')
      else
        Sib:= '';
      Take(Sib);
    end; // for
  finally
    seen.Free;
  end; // try
end; // begin

procedure TConvRulesForm.SetLastFormDir(const ADir: string);
var
  Reg: TRegistry;
begin
  if Trim(ADir) = '' then
    Exit;
  FLastFormDir:= ADir;
  // Same policy as the theme: a locked HKCU costs the NEXT session's convenience,
  // never this session's work, so it is not worth an error dialog.
  Reg:= TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKey(EDITOR_REG_KEY, True) then
        Reg.WriteString(EDITOR_REG_FORMDIR, ADir);
    except
      // Same precedent as SetThemePref: say it once, do not raise. Callers set the
      // dir BEFORE loading a form, so the load's own status supersedes this line --
      // which is why it is safe to report here at all.
      on E: ERegistryException do
        SetStatus('Folder remembered for this session only, not saved: ' + E.Message);
    end; // try
  finally
    Reg.Free;
  end; // try
end; // procedure

function TConvRulesForm.PickFormFiles(out AFiles: TArray<string>): Boolean;
var
  Dlg: TOpenDialog;
begin
  Result:= False;
  AFiles:= nil;
  Dlg:= TOpenDialog.Create(Self);
  try
    Dlg.Filter:= 'Delphi form and source (*.dfm;*.pas)|*.dfm;*.pas|'
      + 'Form files (*.dfm)|*.dfm|Source (*.pas)|*.pas|All files (*.*)|*.*';
    Dlg.Options:= Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    // Resume where the user was: --form's folder on the first browse of a debug
    // run, otherwise wherever they browsed last. A folder that no longer exists is
    // ignored by TOpenDialog rather than being an error.
    if (FLastFormDir <> '') and TDirectory.Exists(FLastFormDir) then
      Dlg.InitialDir:= FLastFormDir;
    if not Dlg.Execute then
      Exit;
    AFiles:= ExpandUnitSiblings(Dlg.Files.ToStringArray);
    if Length(AFiles) > 0 then
      SetLastFormDir(ExtractFileDir(AFiles[0]));
    Result:= Length(AFiles) > 0;
  finally
    Dlg.Free;
  end; // try
end; // function

{ Put a NON-PROJECT unit into the From Unit box.

  PickFormFiles already runs the dialog, expands the .pas/.dfm sibling pair and
  remembers the folder, so this only has to choose which half to show and select
  it. It picks the .pas: the engine derives the .dfm from whatever it is given,
  and the .pas is the name a user recognises as "the unit".

  The path is ADDED to the combo's item list rather than just assigned to its
  Text, because CbLoadUnits rebuilds that list on the first drop-down and a
  free-typed Text would be discarded there -- leaving the box looking populated
  while "Fill From-classes" no longer had a path to resolve. }
procedure TConvRulesForm.DoBrowseFromUnit(Sender: TObject);
var
  Files: TArray<string>;
  Pick : string        ;
  Idx  : Integer       ;
begin
  if not PickFormFiles(Files) then
    Exit;
  if Length(Files) = 0 then
    Exit;

  Pick:= '';
  for var F in Files do
    if SameText(ExtractFileExt(F), '.pas') then
    begin
      Pick:= F;
      Break;
    end;
  if Pick = '' then Pick:= Files[0]; // a .dfm with no .pas sibling is still usable

  Idx:= FCbUnit.Items.IndexOf(Pick);
  if Idx < 0 then
    Idx:= FCbUnit.Items.Add(Pick);
  FCbUnit.ItemIndex:= Idx;
  // Setting ItemIndex in code does not fire OnSelect (VCL only raises it for a user
  // pick), so the harvest is called by hand: browsing IS picking a unit.
  var UsesNote: string:= HarvestUnitFile(Pick);
  SetStatus(Format('From Unit: %s (outside the project) -- %d used unit(s) on the Unit Rules tab; ' + '"Fill From-classes" adds its form components.%s',
    [ExtractFileName(Pick), Length(FUnitCandidates), UsesNote]));
end; // procedure

procedure TConvRulesForm.DoOpenForm(Sender: TObject);
var
  Files: TArray<string>;
begin
  if PickFormFiles(Files) then
    LoadFormFiles(Files);
end;

procedure TConvRulesForm.DoExamine(Sender: TObject);
var
  Files: TArray<string>;
begin
  if PickFormFiles(Files) then
    LoadFormFiles(Files);
end;

procedure TConvRulesForm.LoadFormFiles(const AFiles: TArray<string>);
var
  Dfms     : TArray<string>        ;
  Pass     : TArray<string>        ;
  Bad      : TArray<string>        ;
  Paths    : TArray<string>        ;
  U        : TUsageSet             ;
  L        : TPropLeaf             ;
  F        : string                ;
  T        : string                ;
  UnitParts: TArray<TArray<string>>;
  FromBare : string                ;
  DotPos   : Integer               ;
begin
  // NO "select a conversion first" gate. The form-types panel exists to CHOOSE a
  // From class, so loading a form has to work before any rule is selected. Only
  // the property-usage half below needs an active rule; the type harvest does not.
  if Length(AFiles) = 0 then
    Exit;
  FUsedFiles:= AFiles;

  // LGuard is scoped to this nested block only, so the wait cursor comes back down
  // before ShowUsageReport's modal report below -- that dialog waits on the user,
  // which is not what an hourglass should be shown over.
  begin
    var LGuard: IInterface:= HourGlass;
    Dfms:= nil; Pass:= nil; Bad:= nil;
    for F in FUsedFiles do
    try
      if SameText(ExtractFileExt(F), '.dfm') then
        Dfms:= Dfms + [TFile.ReadAllText(F)]
      else
        Pass:= Pass + [TFile.ReadAllText(F)];
    except
      on E: Exception do Bad:= Bad + [ExtractFileName(F)];
    end;

    HarvestFormTypes(Dfms);
  end; // if

  { The same .pas texts answer "which units does this form pull in" -- harvest them
    into the Unit Rules tab as CANDIDATES, each marked with the clause it was written
    in.

    Harvested HERE, ABOVE the no-active-rule exit below, because the Unit Rules tab is
    about the UNIT and not about the selected conversion. It used to sit after that
    exit, so examining a form without a rule selected left the tab empty and gave no
    reason why.

    Scanned PER FILE and merged, never over the concatenated text: the section latch
    is per-unit, so one file's `implementation` would otherwise mislabel the next
    file's interface clause. First occurrence wins across files, as it does within
    one. Deliberately additive -- nothing here touches FBook, so Examine stays the
    read-only action it says it is, and RefreshUnitList does the "already ruled"
    filtering. }
  HarvestUsedUnits(Pass);

  if FActiveHdr < 0 then
  begin
    FExamineInfo:= Format(
      'Examined %d file(s): %d type(s) listed on the left. ' + 'Select a conversion to also mark its used From properties.', [Length(FUsedFiles), Length(FFormTypeRows)]);
    if Length(Bad) > 0 then
      FExamineInfo:= FExamineInfo + ' Unreadable: ' + string.Join(', ', Bad);
    SetStatus(FExamineInfo);
    Exit;
  end;

  Paths:= nil;
  for L in FFromTree.Leaves do
    Paths:= Paths + [L.Path];

  // A DFM always writes the BARE class name ('object X: TabcToggleBtn'), never a
  // unit-qualified one, but FBook's FromType may be qualified -- strip any prefix
  // up to and including the last '.' before handing it to ComputeUsage.
  FromBare:= FBook.Nodes[FActiveHdr].FromType;
  DotPos:= LastDelimiter('.', FromBare);
  if DotPos > 0 then
    FromBare:= Copy(FromBare, DotPos + 1, MaxInt);

  begin
    var LUsageGuard: IInterface:= HourGlass;
    U:= ComputeUsage(Dfms, Pass, FromBare, Paths);
  end;

  FUsedProps:= U.Names;

  // (the unit harvest now runs ABOVE the no-active-rule exit -- see the note there)

  FExamineInfo:= Format(
    'Examined %d file(s): %d of %d From properties used; ' + '%d unit(s) offered on the Unit Rules tab.',
    [U.DfmCount + U.PasCount, Length(U.Names), Length(Paths), Length(FUnitCandidates)]);
  // Held back by the receiver filter -- say so in the status bar, not only in the modal
  // report, so the count is visible after the dialog has been dismissed.
  if Length(U.Loose) > 0 then
    FExamineInfo:= FExamineInfo + Format(' %d name(s) held back (unknown receiver).', [Length(U.Loose)]);
  if Length(Bad) > 0 then
    FExamineInfo:= FExamineInfo + ' Unreadable: ' + string.Join(', ', Bad);
  SetStatus(FExamineInfo);
  FGrid.Invalidate;
  RefreshUnitList; // draws the harvested units as candidate rows
  UpdateToolbarEnabled; // "Clear marks" is gated on there BEING an examination

  if (Length(U.Missing) > 0) or (Length(U.Loose) > 0) then
    ShowUsageReport(U.Missing, U.Loose);
end; // procedure

{ Drop the current examination -- the session-state fields only (green marks AND the
  harvested unit candidates); the rule model itself is untouched. }
procedure TConvRulesForm.DoClearExamine(Sender: TObject);
begin
  FUsedProps     := nil;
  FUsedFiles     := nil;
  FUnitCandidates:= nil;
  FUsedUnitRefs  := nil; // cleared WITH the candidates: a section for a unit that is
                         // no longer listed is state nothing can reach or refresh.
  FExamineInfo:= '';
  FSelectedFormType:= ''; // clear the type filter on the rules list
  FGrid.Invalidate;
  RefreshUnitList; // takes the candidate rows back off the Unit Rules tab
  RefreshRulesList; // refresh to show all rules again (no type filter)
  UpdateToolbarEnabled; // nothing left to clear -> "Clear marks" goes back down
  SetStatus('Examination cleared.');
end;

{ Small read-only report window, two sections, either of which may be empty.

  MISSING: used names the examined files reference that match no leaf of the active From
  tree -- expected to be rare, and worth surfacing since it usually means the indexer's
  proptree is missing something real.

  LOOSE: names seen in a .pas as '.Name' on a receiver that is NOT one of this form's
  instances of the From class. They are NOT marked used, and this report is the only place
  they appear -- which is the point. The receiver filter exists to stop another class's
  '.Popup' painting a row green, but a filter that silently discarded what it rejected
  would trade visible false positives for INVISIBLE false negatives, and a property this
  conversion really does touch through a local alias or a loop variable would simply stop
  being mentioned. Listing them keeps that judgement with the user. }
procedure TConvRulesForm.ShowUsageReport(const AMissing, ALoose: TArray<string>);
var
  F   : TForm  ;
  Memo: TMemo  ;
  Btn : TButton;
  N   : string ;
begin
  F:= TForm.CreateNew(Self);
  try
    F.Caption    := 'Examine -- names not accounted for';
    F.Width      := 520;
    F.Height     := 420;
    F.Position   := poOwnerFormCenter;
    F.BorderStyle:= bsSizeable;

    Btn:= TButton.Create(F);
    Btn.Parent := F      ; Btn.Align      := alBottom;
    Btn.Caption:= 'Close'; Btn.ModalResult:= mrOk;

    Memo:= TMemo.Create(F);
    Memo.Parent    := F;
    Memo.Align     := alClient;
    Memo.ReadOnly  := True;
    Memo.ScrollBars:= ssBoth;
    Memo.WordWrap  := False;
    Memo.Font.Name:= 'Consolas';
    Memo.Font.Size:= 9;
    if Length(AMissing) > 0 then
    begin
      Memo.Lines.Add(Format('%d name(s) used in the examined files have no row in this grid:', [Length(AMissing)]));
      Memo.Lines.Add('');
      for N in AMissing do
        Memo.Lines.Add('  ' + N);
    end;

    if Length(ALoose) > 0 then
    begin
      if Length(AMissing) > 0 then
        Memo.Lines.Add('');
      Memo.Lines.Add(Format('%d name(s) appear in the .pas on a receiver that is NOT one of', [Length(ALoose)]));
      Memo.Lines.Add('this form''s instances of the From class. They are NOT marked used.');
      Memo.Lines.Add('Usually another component''s property of the same name -- but check,');
      Memo.Lines.Add('since a local alias or a loop variable also lands here:');
      Memo.Lines.Add('');
      for N in ALoose do
        Memo.Lines.Add('  ' + N);
    end;

    F.ShowModal;
  finally
    F.Free;
  end; // try
end; // procedure

{ FGrid.OnDrawCell -- owns ALL cell painting once FGrid.DefaultDrawing is False.
  A data row (ARow > 0) whose From path is in FUsedProps paints green, EXCEPT when
  it is the selected cell/row: selection must stay visible on a marked row, so
  gdSelected always wins and paints the normal highlight colour instead.

  Every colour goes through StyleServices.GetSystemColor rather than the raw cl*
  constant. DefaultDrawing = False keeps the style engine out of this canvas, so
  without that indirection the grid would keep painting the system light palette
  under a dark style. The marking itself is derived from the ACTIVE window colour
  (ConvRules.Theme.ExamineRowColor) so it stays a visible tint on either ground
  instead of a fixed pale green that vanishes on dark. }
procedure TConvRulesForm.GridDrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
var
  Cv : TCanvas;
  Win: TColor ;
begin
  Cv:= FGrid.Canvas;
  Win:= StyleServices.GetSystemColor(clWindow);
  if (ARow > 0) and (gdSelected not in State)
     and (Length(FUsedProps) > 0)
     and IsRowUsed(PathOfGridCell(FGrid.Cells[0, ARow]), FUsedProps) then
    // ColorToRGB: under the system style GetSystemColor hands back the clWindow
    // CONSTANT ($FF0000xx), whose bytes are an index, not channels -- tinting that
    // would produce nonsense. Real styles already return RGB, where it is a no-op.
    Cv.Brush.Color:= TColor(ExamineRowColor(Integer(ColorToRGB(Win)), FThemeMode))
  else if gdSelected in State then
    Cv.Brush.Color:= StyleServices.GetSystemColor(clHighlight)
  else if gdFixed in State then
    Cv.Brush.Color:= StyleServices.GetSystemColor(clBtnFace)
  else
    Cv.Brush.Color:= Win;

  if gdSelected in State then
    Cv.Font.Color:= StyleServices.GetSystemColor(clHighlightText)
  else
    Cv.Font.Color:= StyleServices.GetSystemColor(clWindowText);

  Cv.FillRect(Rect);
  Cv.TextRect(Rect, Rect.Left + 2, Rect.Top + 2, FGrid.Cells[ACol, ARow]);
end; // procedure

{ Align the highlighted To leaf to the From side: select the From-grid row whose
  property has the SAME last-segment name (case-insensitive), so the two sides can
  be assigned by name. Reports when no From property carries that name. }
procedure TConvRulesForm.DoFindInFrom(Sender: TObject);
var
  toName: string ;
  r     : Integer;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPool.ItemIndex < 0 then
  begin SetStatus('Highlight a To leaf in the pool (right) first.'); Exit; end;
  toName:= LeafNameOf(PathOfGridCell(FPool.Items[FPool.ItemIndex]));
  for r:= 1 to FGrid.RowCount - 1 do
    if SameText(LeafNameOf(PathOfGridCell(FGrid.Cells[0, r])), toName) then
    begin
      FGrid.Row:= r; // the Row setter scrolls the cell into view
      SetStatus(Format('From row matching "%s": %s', [toName, FGrid.Cells[0, r]]));
      Exit;
    end;
  SetStatus(Format('No From property named "%s" in this rule.', [toName]));
end; // procedure

{ Toggle a pool type-narrowing: first press restricts the pool to leaves whose
  TYPE matches the highlighted leaf (e.g. only Boolean targets); a second press
  clears it. Cleared automatically when a different rule is loaded. }
procedure TConvRulesForm.DoOnlyType(Sender: TObject);
var
  T: string;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPoolTypeFilter <> '' then
  begin
    FPoolTypeFilter:= '';
    FTbOnlyType.Caption:= 'Only this type';
    RefreshPool;
    SetStatus('Pool type filter cleared.');
    Exit;
  end;
  if FPool.ItemIndex < 0 then
  begin SetStatus('Highlight a To leaf whose type to filter by.'); Exit; end;
  T:= TypeOfCell(FPool.Items[FPool.ItemIndex]);
  if T = '' then begin SetStatus('That leaf has no resolved type to filter by.'); Exit; end;
  FPoolTypeFilter:= T;
  FTbOnlyType.Caption:= 'Show all types';
  RefreshPool;
  SetStatus(Format('Pool narrowed to type "%s".', [T]));
end; // procedure

{ ---- conditional #mapping rules ---------------------------------------------

  A #mapping is FILE-scope and reaches a block only through an #apply, so both
  helpers below read the WHOLE book for the clauses but only the ACTIVE BLOCK for
  which mappings are in force. The folding itself lives in ConvRules.Mappings; this
  window just asks. }

function TConvRulesForm.ActiveAppliedNames: TArray<string>;
begin
  if FActiveHdr < 0 then
    Exit(nil);
  Result:= AppliedMappingNames(FBook.NodesInBlock(FActiveHdr));
end;

function TConvRulesForm.ActiveConditionals: TArray<TConditionalFrom>;
begin
  if FActiveHdr < 0 then
    Exit(nil);
  Result:= ConditionalFromPaths(FBook.Nodes.ToArray, ActiveAppliedNames);
end;

{ "Mappings..." -- open the conditional-mapping editor for ONE named #mapping and
  splice the result back into the book.

  The name is asked for with InputQuery rather than a second picker window: the
  file's existing names are listed in the prompt, so an unrecognised name reads as
  "create this one" instead of silently editing the wrong mapping.

  Three things happen on the way back in, and each of them is why this is not just
  a ShowModal call:
   * the mapping's OLD lines are replaced by the new ones, because the editor
     rewrites the whole mapping as one unit. The splice itself lives in
     TRuleBook.ReplaceMapping, which is where its rules (where a brand-new mapping
     lands, why the deletes run descending) are written down and tested.
   * FActiveHdr is re-derived from the header NODE, since inserting above it moves
     its index.
   * the #apply is added when it is missing. Without it the mapping is authored,
     validated and completely inert, and the grid would show nothing at all. }
procedure TConvRulesForm.DoMappings(Sender: TObject);
var
  Names  : TArray<string>   ;
  Name   : string           ;
  Prompt : string           ;
  Own    : TArray<TRuleNode>;
  Hdr    : TRuleNode        ;
  N      : TRuleNode        ;
  Applied: Boolean          ;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;

  Names:= MappingNames(FBook.Nodes.ToArray);

  // Default to the mapping this block already applies, else the first one in the file.
  Name:= '';
  for N in FBook.NodesInBlock(FActiveHdr) do
    if (N.Kind = rnkApply) and (N.ApplyName <> '') then begin Name:= N.ApplyName; Break; end;
  if (Name = '') and (Length(Names) > 0) then
    Name:= Names[0];

  Prompt:= 'Mapping name -- an existing one, or a new name to create:';
  if Length(Names) > 0 then
    Prompt:= Prompt + sLineBreak + 'In this file: ' + string.Join(', ', Names);
  if not InputQuery('Mappings', Prompt, Name) then
    Exit;
  Name:= Trim(Name);
  if Name = '' then begin SetStatus('No mapping name given.'); Exit; end;

  // The mapping's lines as they stand -- borrowed, the book still owns them; they are
  // the editor's seed.
  Own:= FBook.MappingNodesNamed(Name);

  Hdr:= FBook.Nodes[FActiveHdr];
  if not TMappingForm.EditMapping(Self, Name, Own, FEngine, FToTree, Hdr.ToType) then
  begin
    SetStatus(Format('Mapping "%s" unchanged.', [Name]));
    Exit;
  end;
  // Own now holds FRESH nodes owned by this method until ReplaceMapping takes them.

  // The splice itself is the BOOK's job, not the window's: the index arithmetic (delete
  // descending, insert at the first freed slot, file scope for a brand-new mapping) is
  // model surgery, and the two data-loss bugs this feature shipped with were both in
  // exactly that seam.
  FBook.ReplaceMapping(Name, Own);

  // Inserting above the header moved it, so the index must be re-derived from the NODE.
  FActiveHdr:= FBook.Nodes.IndexOf(Hdr);

  Applied:= False;
  for N in FBook.NodesInBlock(FActiveHdr) do
    if (N.Kind = rnkApply) and SameText(N.ApplyName, Name) then
    begin Applied:= True; Break; end;
  if not Applied then
  begin
    N:= TRuleNode.Create;
    N.Kind     := rnkApply;
    N.ApplyName:= Name;
    N.Dirty    := True;
    FBook.Nodes.Insert(FActiveHdr + 1, N);
  end;

  LoadGridForBlock(FActiveHdr);
  SyncRawFromModel;
  RefreshRulesList;
  SetStatus(Format('Mapping "%s": %d line(s) written%s.', [Name, Length(Own), IfThen(Applied, '', ' and #apply added to this conversion')]));
end; // procedure

{ Target surface changed (DFM published <-> PAS public+fields): remember the new
  --min-visibility and re-fetch the active rule's From/To trees at that surface. }
procedure TConvRulesForm.SurfaceChanged(Sender: TObject);
begin
  if FCbSurface.ItemIndex = 1 then
    FSurfaceMinVis:= 'public'
  else
    FSurfaceMinVis:= 'published';
  if FActiveHdr >= 0 then
    LoadGridForBlock(FActiveHdr);
  if FSurfaceMinVis = 'public' then
    SetStatus('Surface: PAS -- public props + public fields (public targets tagged PAS-only).')
  else
    SetStatus('Surface: DFM -- published (DFM-streamable) props only.');
end; // procedure

{ Create or update the #link mapping ToPath <- FromPath in the active block,
  choosing a default cast from the leaf types (identity when same type). Shared by
  the manual Assign and the Auto-Match pass. Does NOT touch the grid/UI -- callers
  refresh. Assumes CanCast(AFromType, AToType) was already checked. }
procedure TConvRulesForm.AssignLink(const AFromPath, AToPath, AFromType, AToType: string);
var
  Link    : TRuleNode ;
  i       : Integer   ;
  insertAt: Integer   ;
  Casts   : TCastFnSet;
  C       : TCastFn   ;
begin
  Link:= FindLinkForFrom(AFromPath);
  if Link = nil then
  begin
    Link:= TRuleNode.Create;
    Link.Kind    := rnkLink;
    Link.LinkFrom:= AFromPath;
    Link.Dirty   := True;
    insertAt:= FActiveHdr + 1;
    for i:= FActiveHdr + 1 to FBook.Nodes.Count - 1 do
    begin
      if FBook.Nodes[i].Kind = rnkConvert then
        Break;
      insertAt:= i + 1;
    end;
    FBook.Nodes.Insert(insertAt, Link);
  end; // if
  Link.LinkTo:= AToPath;
  Link.Dirty := True;

  // identity (same family or same type) -> no cast; else the first valid cast
  if SameFamily(AFromType, AToType) or SameText(AFromType, AToType) then
    Link.Cast:= ''
  else
  begin
    Casts:= ValidCasts(AFromType, AToType);
    Link.Cast:= '';
    for C:= Low(TCastFn) to High(TCastFn) do
      if C in Casts then begin Link.Cast:= CastFnName(C); Break; end;
    if Link.Cast = '' then
      Link.Cast:= ClassCastName(AFromType, AToType); // library class cast (e.g. AssignGraphic)
  end;
end; // procedure

{ Fill the conversion catalog for the From property on ARow.

  Answers "what can this become?", which no other call in this editor can: every
  cast API takes BOTH types because its caller already had them. Read-only -- the
  actual target is still chosen in the pool, because only the pool knows which
  leaves are still UNASSIGNED, and a target already linked must not be offered
  twice.

  Lives HERE, below PathOfGridCell, because that is an implementation-section
  function: called from above its definition it is simply undeclared. }
procedure TConvRulesForm.RefreshConvOptions(ARow: Integer);
var
  FromPath: string;
  FromType: string;
  Opts    : TArray<TConvOption>;
  O       : TConvOption;
begin
  if FConvList = nil then
    Exit;
  FConvList.Items.BeginUpdate;
  try
    FConvList.Items.Clear;
    if (ARow < 1) or (ARow >= FGrid.RowCount) then
    begin
      FLblConv.Caption:= 'Can convert to: (select a From row)';
      Exit;
    end;
    FromPath:= PathOfGridCell(FGrid.Cells[0, ARow]);
    FromType:= LeafType(FFromTree, FromPath);
    if IsUnknownType(FromType) then
    begin
      // Say WHICH of the two it is. "no conversions" over an unresolved type
      // reads as "this property converts to nothing", which is a different and
      // much more discouraging claim than "I could not resolve its type".
      FLblConv.Caption:= Format('Can convert to: %s -- type unresolved', [FromPath]);
      Exit;
    end;
    Opts:= ConversionsFor(FromType, FCastDefs, FEnumDefs);
    for O in Opts do
      FConvList.Items.Add(ConvOptionText(O));
    FLblConv.Caption:= Format('Can convert to: %s (%s) -- %d option(s)',
      [FromPath, FromType, Length(Opts)]);
  finally
    FConvList.Items.EndUpdate;
  end;
end;

procedure TConvRulesForm.DoAssign(Sender: TObject);
var
  FromPath: string ;
  ToPath  : string ;
  Row     : Integer;
  LCases  : Integer;
  FromType: string ;
  ToType  : string ;
begin
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  if FPool.ItemIndex < 0 then begin SetStatus('Pick a To property from the pool (right) first.'); Exit; end;
  Row:= FGrid.Row;
  if Row < 1 then begin SetStatus('Pick a From row in the grid (left) first.'); Exit; end;

  FromPath:= PathOfGridCell(FGrid.Cells[0, Row]);
  ToPath:= PathOfGridCell(FPool.Items[FPool.ItemIndex]);
  if (FromPath = '') or (ToPath = '') then
    Exit;

  // Exactly the rule DoAutoMatch applies to the same rows: a From leaf an applied
  // #mapping already decides conditionally is spoken for, even though it has no #link.
  // Writing an unconditional #link beside it leaves TWO rules claiming one source
  // property, and nothing downstream catches that -- RefreshPool withholds its targets
  // and RefreshGrid labels it '<conditional: N cases>', but ValidateMappings is never
  // run over the whole book, so the clash would ship silently.
  LCases:= ConditionalCasesOf(ActiveConditionals, FromPath);
  if LCases > 0 then
  begin
    SetError(Format(
        'Blocked: %s is already decided by an applied #mapping (%d case(s)). '
          + 'Edit that mapping instead -- a #link here would claim the same source property '
          + 'a second time, unconditionally.',
        [FromPath, LCases]));
    Exit;
  end;

  FromType:= LeafType(FFromTree, FromPath);
  ToType  := LeafType(FToTree  , ToPath  );
  // If one side's type is unknown (inherited from an unresolved parent), infer it
  // from the other side -- a same-named property is the same inherited member.
  ResolveUnknownTypes(FromType, ToType);

  if not LeafWritable(FToTree, ToPath) then
  begin
    SetError(Format('Blocked: %s is read-only -- not a valid assignment target.', [ToPath]));
    Exit;
  end;

  if not CanCast(FromType, ToType) then
  begin
    SetError(Format('Blocked: cannot map %s (%s) to %s (%s) -- no known cast.', [FromPath, FromType, ToPath, ToType]));
    Exit;
  end;

  AssignLink(FromPath, ToPath, FromType, ToType);
  { toType is the RESOLVED type (ResolveUnknownTypes may have inferred it from the
    From side), so this cell can show a type where a bare FToTree lookup would not. }
  FGrid.Cells[1, Row]:= PropCellText(ToPath, ToType);
  FGrid.Cells[2, Row]:= FindLinkForFrom(FromPath).Cast;
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
  // RefreshPool consumed the highlighted leaf, so FPool.ItemIndex is now -1 -- but
  // rebuilding the list does NOT fire FPool.OnClick, so nothing else re-gates and
  // "<- Assign" would stay enabled over a selection that no longer exists.
  UpdateToolbarEnabled;
  SetStatus(Format('Assigned %s <- %s%s', [ToPath, FromPath, IfThen(FindLinkForFrom(FromPath).Cast <> '', ' : ' + FindLinkForFrom(FromPath).Cast, '')]));
end; // procedure

{ Auto-Match: for every UNassigned From leaf, if exactly ONE unassigned To leaf
  matches by leaf-name (case-insensitive) AND is castable, create the #link. Skips
  ambiguous names (more than one candidate) so the user resolves those by hand. }
procedure TConvRulesForm.DoAutoMatch(Sender: TObject);
var
  fromLeaf   : TPropLeaf                   ;
  toLeaf     : TPropLeaf                   ;
  fromName   : string                      ;
  toName     : string                      ;
  candidate  : TPropLeaf                   ;
  nCand      : Integer                     ;
  nMatched   : Integer                     ;
  assignedTo : TDictionary<string, Boolean>;
  toNameCount: TDictionary<string, Integer>;
  cnt        : Integer                     ;
  L          : TRuleNode                   ;
  matchType  : string                      ;
  conds      : TArray<TConditionalFrom>    ;

  function LeafName(const APath: string): string;
  begin
    Result:= APath;
    if LastDelimiter('.', Result) > 0 then
      Result:= Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;

begin
  var LGuard: IInterface:= HourGlass;
  if FActiveHdr < 0 then begin SetStatus('Select or create a rule first.'); Exit; end;
  nMatched:= 0;
  conds   := ActiveConditionals;
  assignedTo := TDictionary<string, Boolean>.Create;
  toNameCount:= TDictionary<string, Integer>.Create;
  try
    for L in ActiveLinks do
      if L.LinkTo <> '' then
        assignedTo.AddOrSetValue(LowerCase(L.LinkTo), True);
    // Count each To leaf's LAST-SEGMENT name across the WHOLE tree (global
    // uniqueness). A last-segment auto-match is only safe when the name is unique;
    // otherwise the greedy assigned-pool depletion below pairs infrastructure-noise
    // leaves (dozens of '.Components', '.Owner', ...) arbitrarily.
    for toLeaf in FToTree.Leaves do
    begin
      if not toLeaf.IsWritable then Continue; // read-only leaves are never targets
      toName:= LowerCase(LeafName(toLeaf.Path));
      if toNameCount.TryGetValue(toName, cnt) then
        toNameCount[toName]:= cnt + 1
      else
        toNameCount.Add(toName, 1);
    end;

    for fromLeaf in FFromTree.Leaves do
    begin
      // skip From leaves already mapped
      if FindLinkForFrom(fromLeaf.Path) <> nil then
        Continue;
      // A leaf an applied #mapping decides conditionally is mapped too, just not by a
      // #link. Auto-matching one on top would add a second, UNCONDITIONAL answer for
      // the same source property -- the two rules would then both claim it.
      if ConditionalCasesOf(conds, fromLeaf.Path) > 0 then
        Continue;
      fromName:= LowerCase(LeafName(fromLeaf.Path));

      // PASS 1 -- an EXACT full-path match (From.path == To.path) is unambiguous
      // even when the leaf NAME repeats in nested sub-objects. This is what makes
      // top-level AllowAllUp/Down/ShowHint auto-pick: TcxButton has 14 leaves whose
      // last segment is "AllowAllUp" (Colors.Button.AllowAllUp, ...), but only ONE
      // whose full path is exactly "AllowAllUp".
      nCand:= 0; candidate:= Default(TPropLeaf); matchType:= '';
      for toLeaf in FToTree.Leaves do
      begin
        if not toLeaf.IsWritable then
          Continue;
        if assignedTo.ContainsKey(LowerCase(toLeaf.Path)) then
          Continue;
        if not SameText(toLeaf.Path, fromLeaf.Path) then
          Continue;
        var fT: string:= fromLeaf.TypeName;
        var tT: string:= toLeaf  .TypeName;
        ResolveUnknownTypes(fT, tT);
        if CanCast(fT, tT) then
        begin
          Inc(nCand);
          candidate:= toLeaf;
        end;
      end; // for

      // PASS 2 -- only when no exact-path match exists, fall back to matching by the
      // LAST path segment, still requiring a UNIQUE castable candidate.
      // PASS 2 fires ONLY when the From name is GLOBALLY UNIQUE among To
      // last-segments -- an ambiguous name (noise) is never auto-paired.
      if (nCand = 0) and toNameCount.TryGetValue(fromName, cnt) and (cnt = 1) then
        for toLeaf in FToTree.Leaves do
        begin
          if not toLeaf.IsWritable then
            Continue;
          if assignedTo.ContainsKey(LowerCase(toLeaf.Path)) then
            Continue;
          toName:= LowerCase(LeafName(toLeaf.Path));
          if fromName <> toName then
            Continue;
          var fT: string:= fromLeaf.TypeName;
          var tT: string:= toLeaf  .TypeName;
          ResolveUnknownTypes(fT, tT);
          if CanCast(fT, tT) then
          begin
            Inc(nCand);
            candidate:= toLeaf;
          end;
        end; // for

      if nCand = 1 then
      begin
        var fT: string:= fromLeaf .TypeName;
        var tT: string:= candidate.TypeName;
        ResolveUnknownTypes(fT, tT);
        AssignLink(fromLeaf.Path, candidate.Path, fT, tT);
        assignedTo.AddOrSetValue(LowerCase(candidate.Path), True);
        Inc(nMatched);
      end;
    end; // for
  finally
    assignedTo.Free;
    toNameCount.Free;
  end; // try

  // reload the grid to reflect the new assignments
  LoadGridForBlock(FActiveHdr);
  SyncRawFromModel;
  RefreshRulesList;
  SetStatus(Format('Auto-Match: %d unambiguous assignment(s) created.', [nMatched]));
end; // begin

{ New Conversion: read From/To from the pickers, verify both resolve to indexed
  classes, append a fresh #convert block, load it (populates the grid + To pool),
  then run Auto-Match so the obvious mappings are pre-filled. }
function TConvRulesForm.ChooseTargetForNewRule(const AFrom, ATo: string; ACompletingStub: Boolean): Boolean;
var
  RuledEntry  : TRuleCatalogEntry;
  Folder      : string           ;
  RuleFileName: string           ;
  NewPath     : string           ;
  OpenBook    : string           ;
begin
  Result:= False;

  { The catalog is normally built when a form is examined. Nothing guarantees that
    happened: opening a book and pressing New Conversion straight away is an ordinary
    way to use this editor, and the catalog would then be EMPTY -- so FindRuleForType
    would answer "not ruled" for every type and this guard would never fire.

    Observed 2026-09-09 driving the real UI: TTable, which IS ruled, sailed past the
    duplicate prompt because no form had been examined. Build it on demand instead;
    the scan is a folder read, not an engine call. }
  if Length(FCatalog) = 0 then
    RescanRulesFolder(nil);

  { A rule for this type may already exist elsewhere in the folder, and authoring a
    second one produces exactly the duplicate FindDuplicates reports. Offer the
    existing rule FIRST.

    Deliberately not a hard refusal. The user may be replacing a rule on purpose, and
    a tool that simply says no gets worked around in ways nobody can see. The DEFAULT
    is the safe act and the cost of the other one is stated. }
  if (not ACompletingStub) and FindRuleForType(FCatalog, AFrom, RuledEntry) then
  case MessageDlg(
      Format('%s is already converted by %s (line %d).' + sLineBreak + sLineBreak + 'Yes = open THAT rule and edit it.' + sLineBreak + 'No  = write a SECOND rule anyway; the catalog will report a duplicate.', [AFrom, ExtractFileName(RuledEntry.FilePath), RuledEntry.LineNo]),
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrCancel: Exit;
    mrYes   :
    begin
      FCbFrom.Text:= AFrom;
      OpenOwningRule(AFrom); // one implementation, shared with the double-click
      Exit;
    end;
  end; // case

  { A rule may live in an existing book or in a file of its own; selective
    Compose picks the rules a job needs out of multi-rule books, so neither is
    "the" shape any more. Atomization was retired 2026-09-09 -- the default is
    now to append to the book that is open, with a new file still one click
    away. RULE_FILE_NAME_FMT still names that new file: owner ruling 1c is open. }
  Folder:= Trim(FRulesFolder);
  if Folder = '' then
    Folder:= ExtractFilePath(FFilePath);
  RuleFileName:= RuleFileNameFor(AFrom, ATo);
  if FFilePath = '' then
    OpenBook:= '(none yet)'
  else
    OpenBook:= ExtractFileName(FFilePath);

  if (not ACompletingStub) and (Folder <> '') and (RuleFileName <> '') then
  case MessageDlg(
      Format('Where should the %s -> %s rule go?' + sLineBreak + sLineBreak + 'Yes = append to the open book, %s' + sLineBreak + 'No  = start a NEW file, %s', [AFrom, ATo, OpenBook, RuleFileName]),
      mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrCancel: Exit;
    { mrYes is unhandled ON PURPOSE: it falls through to the append below,
        which is now the default. mrNo starts a new file. }
    mrNo :
    begin
      // FFilePath is about to point somewhere else and the open book may hold
      // unsaved edits. Ask BEFORE touching FBook: clearing first and prompting
      // afterwards would destroy the very edits the prompt is about.
      if (FFilePath <> '') and (FBook.Nodes.Count > 0) then
      case MessageDlg(
          Format('Start %s?' + sLineBreak + sLineBreak + 'Yes = save %s first.' + sLineBreak + 'No  = DISCARD any unsaved edits in it.', [RuleFileName, ExtractFileName(FFilePath)]),
          mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
        mrCancel: Exit;
        mrYes   :
          if not DoSave(nil) then
          begin
            SetError('New file not started: the save failed, so your edits are ' + 'still only in this editor and nothing on disk changed.');
            Exit;
          end;
      end; // case

      // UniqueRulePath never returns an existing path: DoSave OVERWRITES, so a
      // colliding name would silently replace a sibling rule file.
      NewPath:= UniqueRulePath(Folder, RuleFileName);
      FBook.Clear;
      FFilePath:= NewPath;
      FLblFile.Caption:= NewPath;
      FActiveHdr:= -1;
      RefreshRulesList;
      RefreshUnitList;
      // The file is created by the UNCHANGED save routine, never here. If no link
      // is ever assigned, DoSave refuses and no empty file appears.
      SetStatus(Format('New file: %s. It is not on disk until you Save.', [ExtractFileName(NewPath)]));
    end; // case
  end; // case

  Result:= True;
end; // function

procedure TConvRulesForm.DoNewConversion(Sender: TObject);
var
  fromT         : string   ;
  toT           : string   ;
  tree          : TProptree;
  Err           : string   ;
  FromNote      : string   ;
  ToNote        : string   ;
  Notes         : string   ;
  Hdr           : TRuleNode;
  newHdrIdx     : Integer  ;
  CompletingStub: Boolean  ;
begin
  var LGuard: IInterface:= HourGlass;
  fromT:= Trim(FCbFrom.Text);
  toT  := Trim(FCbTo  .Text);
  if (fromT = '') or (toT = '') then
  begin
    SetError('Pick (or type) both a From and a To class in the top pickers.');
    Exit;
  end;

  SetStatus(Format('Resolving %s and %s ...', [fromT, toT]));
  Application.ProcessMessages;
  tree:= Default(TProptree);
  if not FEngine.GetProptree(fromT, tree, Err, FromNote) or (Length(tree.Leaves) = 0) then
  begin
    SetError(Format('From class "%s" is not indexed (no properties found). %s', [fromT, Err]));
    Exit;
  end;
  if not FEngine.GetProptree(toT, tree, Err, ToNote) or (Length(tree.Leaves) = 0) then
  begin
    SetError(Format('To class "%s" is not indexed (no properties found). %s', [toT, Err]));
    Exit;
  end;

  // Completing a From-only stub is NOT authoring a second rule -- it finishes the
  // one already here -- so neither guard below applies to it.
  CompletingStub:= (FActiveHdr >= 0) and (FActiveHdr < FBook.Nodes.Count)
     and (FBook.Nodes[FActiveHdr].Kind = rnkConvert)
     and (Trim(FBook.Nodes[FActiveHdr].ToType) = '')
     and SameText(Trim(FBook.Nodes[FActiveHdr].FromType), fromT);

  if not ChooseTargetForNewRule(fromT, toT, CompletingStub) then
    Exit;

  // If the SELECTED rule is a From-only stub whose From matches the picker, SET
  // ITS To in place (the "assign a To to a Fill From-classes row" flow) instead of
  // creating a duplicate. Otherwise append a fresh #convert block.
  if CompletingStub then
  begin
    FBook.Nodes[FActiveHdr].ToType:= toT;
    FBook.Nodes[FActiveHdr].Dirty := True;
    newHdrIdx:= FActiveHdr;
  end
  else
  begin
    // append a blank line + a new #convert header at the end of the model
    if FBook.Nodes.Count > 0 then
    begin
      var Blank: TRuleNode:= TRuleNode.Create; Blank.Kind:= rnkBlank; Blank.Raw:= '';
      FBook.Add(Blank);
    end;
    Hdr:= TRuleNode.Create;
    Hdr.Kind    := rnkConvert;
    Hdr.FromType:= fromT;
    Hdr.ToType  := toT;
    Hdr.Dirty   := True;
    FBook.Add(Hdr);
    newHdrIdx:= FBook.Nodes.Count - 1;
  end; // else

  RefreshRulesList;
  // select the target rule (also fires LoadGridForBlock)
  var Sel: Integer:= -1;
  for var k:= 0 to FRules.Items.Count - 1 do
    if Integer(FRules.Items[k].Data) = newHdrIdx then begin Sel:= k; Break; end;
  if Sel >= 0 then
  begin
    FRules.ItemIndex:= Sel;
    FRules.Items[Sel].Selected:= True;
  end
  else
    LoadGridForBlock(newHdrIdx);

  // pre-fill the obvious matches
  DoAutoMatch(nil);
  SyncRawFromModel;
  // This is where a bare class name typed into a picker is first resolved, so it is
  // also where an FMX-vs-VCL tie has to be said out loud -- the tree behind every
  // auto-match just made may belong to the other framework.
  Notes:= '';
  if FromNote <> '' then
    Notes:= Notes + '  ' + FromNote;
  if ToNote <> '' then
    Notes:= Notes + '  ' + ToNote;
  SetStatus(Format('Conversion %s -> %s set and auto-matched. Review, then Save.', [fromT, toT]) + Notes);
end; // procedure

procedure TConvRulesForm.DoUnassign(Sender: TObject);
var
  Row     : Integer  ;
  FromPath: string   ;
  Link    : TRuleNode;
begin
  if FActiveHdr < 0 then
    Exit;
  Row:= FGrid.Row;
  if Row < 1 then
    Exit;
  FromPath:= PathOfGridCell(FGrid.Cells[0, Row]);
  Link:= FindLinkForFrom(FromPath);
  if Link = nil then begin SetStatus('That From row has no assignment.'); Exit; end;
  // remove the link node from the model
  FBook.Nodes.Remove(Link);
  FGrid.Cells[1, Row]:= '';
  FGrid.Cells[2, Row]:= '';
  RefreshPool;
  SyncRawFromModel;
  RefreshRulesList;
  UpdateToolbarEnabled; // same reason as DoAssign: the pool list was rebuilt
  SetStatus('Unassigned ' + FromPath);
end; // procedure

procedure TConvRulesForm.SyncRawFromModel;
begin
  FRaw.Lines.Text:= FBook.SaveToString;
end;

procedure TConvRulesForm.DoValidate(Sender: TObject);
var
  res  : TValidateResult;
  Node : TRuleNode      ;
  fromT: string         ;
  toT  : string         ;
begin
  var LGuard: IInterface:= HourGlass;
  if FFilePath = '' then begin SetStatus('Load a file first.'); Exit; end;
  fromT:= ''; toT:= '';
  if FActiveHdr >= 0 then
  begin
    Node:= FBook.Nodes[FActiveHdr];
    fromT:= Node.FromType; toT:= Node.ToType;
  end;
  res:= FEngine.ValidateText(FBook.SaveToString, fromT, toT);
  if res.OK then
    SetStatus('Validate: OK')
  else
    SetStatus('Validate: ' + res.FirstError);
end; // procedure

{ Open the curation window on the file currently loaded here. Curation moves
  VERBATIM block text and deliberately does NOT go through this form's canonical
  re-emitter, so a block that was merely moved stays byte-identical. It works on
  the file ON DISK, so unsaved edits here are invisible to it: Yes = save first,
  No = curate the on-disk version anyway, Cancel = out. }
procedure TConvRulesForm.DoCurate(Sender: TObject);
var
  Reload   : string        ;
  FormTypes: TArray<string>;
  TypeRow  : TFormTypeRow  ;
begin
  if (FFilePath <> '') and (FBook.Nodes.Count > 0) then
  case MessageDlg('Curation works on the file on disk. Save your edits first?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrCancel: Exit;
    mrYes   :
      // The user asked to save FIRST. If that failed, opening curation anyway
      // would curate the STALE disk file and the reload afterwards would throw
      // the unsaved edits away -- so stop here instead. DoSave has already put
      // the reason on the status bar; do not overwrite it.
      if not DoSave(nil) then
      begin
        SetError('Curation not opened: the save failed, so your edits are still ' + 'only in this editor and nothing on disk changed.');
        Exit;
      end;
  end; // case

  { Hand the curation window the types actually on the examined form, so its
    "Select by form types" can check exactly the rules this job needs. Skipped
    rows are excluded (the user's own mark); Ruled is deliberately NOT consulted
    -- an unruled type simply matches no block. }
  FormTypes:= nil;
  for TypeRow in FFormTypeRows do
    if not TypeRow.Skipped then
      FormTypes:= FormTypes + [TypeRow.TypeName];

  Reload:= TCurationForm.Execute(Self, FFilePath, FormTypes);
  if Reload <> '' then
  begin
    LoadFile(Reload);
    SetStatus('Reloaded ' + ExtractFileName(Reload) + ' after curation.');
  end;
end; // procedure

procedure TConvRulesForm.DoSaveClick(Sender: TObject);
begin
  DoSave(Sender);
end;

function TConvRulesForm.DoSave(Sender: TObject): Boolean;
var
  bak  : string         ;
  res  : TValidateResult;
  Node : TRuleNode      ;
  fromT: string         ;
  toT  : string         ;
begin
  Result:= False; // every early Exit below means nothing reached disk
  var LGuard: IInterface:= HourGlass;
  if FFilePath = '' then
  begin
    var Dlg: TSaveDialog:= TSaveDialog.Create(Self);
    try
      Dlg.Filter    := 'Conversion rules (*.rules)|*.rules';
      Dlg.DefaultExt:= 'rules';
      if not Dlg.Execute then
        Exit;
      FFilePath:= Dlg.FileName;
      FLblFile.Caption:= FFilePath;
    finally Dlg.Free; end;
  end; // if

  // 1) backup existing
  if TFile.Exists(FFilePath) then
  begin
    bak:= BackupPath(FFilePath);
    try TFile.Copy(FFilePath, bak); except on E: Exception do
      begin SetStatus('Backup failed: ' + E.Message); Exit; end; end;
  end;

  // 2) write canonical DSL (ASCII/CRLF) -- only COMPLETE rules (a #convert block
  //    with at least one #link). A From/To pair with nothing mapped yet is scratch
  //    and is not persisted.
  var dropped: Integer                                     ;
  var outText: string:= FBook.SaveCompleteToString(dropped);

  { A BRAND-NEW rule file with nothing complete would be created EMPTY.
    SaveCompleteToString drops a #convert that has no #link yet, so "new file AND
    everything dropped" writes a 0-byte .rules -- a file the folder scan picks up,
    the catalog cannot explain, and no backup exists to undo (step 1 only backs up
    a file that already existed).

    Refused NARROWLY, on both conditions. Saving an EXISTING book down to empty is a
    different act -- deliberate deletion -- and it keeps its .bak. }
  if (Trim(outText) = '') and (dropped > 0) and (not TFile.Exists(FFilePath)) then
  begin
    SetError(Format(
        'Nothing saved and %s was NOT created: it has no completed rule ' + 'yet. A #convert needs at least one #link -- assign a property, then Save.',
        [ExtractFileName(FFilePath)]));
    Exit;
  end;

  TFile.WriteAllText(FFilePath, outText, TEncoding.ASCII);

  // 3) validate the saved file
  fromT:= ''; toT:= '';
  if FActiveHdr >= 0 then
  begin
    Node:= FBook.Nodes[FActiveHdr];
    fromT:= Node.FromType; toT:= Node.ToType;
  end;
  res:= FEngine.ValidateText(outText, fromT, toT);
  var droppedMsg: string:= '';
  if dropped > 0 then
    droppedMsg:= Format(' (%d empty rule(s) not saved)', [dropped]);
  if res.OK then
    SetStatus(Format('Saved %s (backup %s)%s. Validate: OK', [ExtractFileName(FFilePath), ExtractFileName(bak), droppedMsg]))
  else
    SetStatus(Format('Saved %s (backup %s)%s. Validate: %s', [ExtractFileName(FFilePath), ExtractFileName(bak), droppedMsg, res.FirstError]));

  // Surface unit-rule conflicts (ADD wins) after every save, non-blocking.
  RefreshUnitList;
  var us: TUnitSets:= NormalizeUnitSets(FBook);
  if Length(us.Conflicts) > 0 then
    SetError(Format('Note: unit conflicts (ADD wins): %s', [string.Join(', ', us.Conflicts)]));

  { The folder just changed on disk, so the catalog is now one save out of date. Any
    type this save has newly ruled would keep painting as UN-RULED -- inviting a
    second rule for it -- until something else happened to rescan.

    Only when a form has been examined: with no type list there is nothing to re-mark
    and this would be an engine call for no reason. RescanRulesFolder writes its own
    status, so preserve the save message the user is actually waiting for. }
  if Length(FFormTypeRows) > 0 then
  begin
    var SaveMsg: string:= FLblStatus.Caption;
    RescanRulesFolder(nil);
    RefreshFormTypes;
    SetStatus(SaveMsg);
  end;

  Result:= True; // the file IS on disk; a failed validation is a report, not a failure
end; // function

{ ---- Unit Rules tab ---- }

procedure TConvRulesForm.InsertUnitNode(ANode: TRuleNode);
var
  Heads: TArray<Integer>;
begin
  // Unit directives live in the top file-level section (before the first #convert)
  // so SaveCompleteToString always preserves them -- a trailing incomplete #convert
  // block would otherwise swallow nodes appended at EOF.
  Heads:= FBook.ConvertHeaders;
  if Length(Heads) = 0 then
    FBook.Add(ANode)
  else
    FBook.Nodes.Insert(Heads[0], ANode);
end;

{ The list shows the rule book's unit directives first, then -- underneath them -- the
  units Examine harvested that STILL have no rule of their own (Item.Data = nil marks a
  candidate). Candidates are re-filtered on every refresh rather than pruned once, so
  authoring a #use/#unuse/#useswap for one silently retires its candidate row, and one
  source unit can fan out to several replacements through the existing #useswap. }
procedure TConvRulesForm.HarvestUsedUnits(const APasTexts: TArray<string>);
var
  UnitParts: TArray<TArray<string>>;
  T        : string                ;
begin
  FUsedUnitRefs:= nil;
  UnitParts    := nil;
  for T in APasTexts do
  begin
    UnitParts:= UnitParts + [ScanUsesClauses(T)];
    for var R: TUsedUnitRef in ScanUsesClausesSectioned(T) do
    begin
      { First occurrence wins ACROSS texts too, matching the within-text rule, so a
        unit pulled in by two of the examined files is offered once. }
      var Dup: Boolean:= False;
      for var X: TUsedUnitRef in FUsedUnitRefs do
        if SameText(X.UnitName, R.UnitName) then
        begin
          Dup:= True;
          Break;
        end;
      if not Dup then
        FUsedUnitRefs:= FUsedUnitRefs + [R];
    end;
  end;
  FUnitCandidates:= MergeUsage(UnitParts);
  RefreshUnitList;
end; // procedure

procedure TConvRulesForm.RefreshUnitList;
var
  N   : TRuleNode;
  Item: TListItem;
  S   : TUnitSets;
  Cand: string   ;

  function InConflict(const AUnit: string): Boolean;
  var
    C: string;
  begin
    Result:= False;
    if AUnit = '' then
      Exit;
    for C in S.Conflicts do
      if SameText(C, AUnit) then
        Exit(True);
  end;

{ Which `uses` clause the scan found AUnit in. Falls back to the old wording rather
    than to '' or to 'interface': a blank cell would read as "no section", and
    defaulting to a real clause would assert something the scan never established. }
  function SectionOf(const AUnit: string): string;
  var
    R: TUsedUnitRef;
  begin
    for R in FUsedUnitRefs do
      if SameText(R.UnitName, AUnit) then
        Exit(R.Section);
    Result:= 'from Examine';
  end;

{ Does a unit directive already speak about AUnit? SwapOld, not SwapNew: a #useswap's
    new units are replacements the legacy form would not itself have used. }
  function HasRuleFor(const AUnit: string): Boolean;
  var
    N: TRuleNode;
  begin
    Result:= True;
    for N in FBook.UnitNodes do
    case N.Kind of
      rnkUse    : if SameText(N.UseUnit, AUnit) then Exit  ;
      rnkUnuse  : if SameText(N.UnuseUnit, AUnit) then Exit;
      rnkUseSwap: if SameText(N.SwapOld, AUnit) then Exit  ;
    end;
    Result:= False;
  end;

begin
  if FUnitList = nil then
    Exit;
  S:= NormalizeUnitSets(FBook);
  FUnitList.Items.BeginUpdate;
  try
    FUnitList.Items.Clear;
    for N in FBook.UnitNodes do
    begin
      Item:= FUnitList.Items.Add;
      case N.Kind of
        rnkUse:
        begin
          Item.Caption:= '#use';
          Item.SubItems.Add('');
          Item.SubItems.Add(N.UseUnit);
          Item.SubItems.Add(IfThen(InConflict(N.UseUnit), '(!) ADD wins', ''));
        end;
        rnkUnuse:
        begin
          Item.Caption:= '#unuse';
          Item.SubItems.Add(N.UnuseUnit);
          Item.SubItems.Add('');
          Item.SubItems.Add(IfThen(InConflict(N.UnuseUnit), '(!) also added', ''));
        end;
        rnkUseSwap:
        begin
          Item.Caption:= '#useswap';
          Item.SubItems.Add(N.SwapOld);
          Item.SubItems.Add(string.Join(', ', N.SwapNew));
          Item.SubItems.Add(IfThen(InConflict(N.SwapOld), '(!) also added', ''));
        end;
      end; // case
      Item.Data:= Pointer(N);
    end; // for

    for Cand in FUnitCandidates do
      if not HasRuleFor(Cand) then
      begin
        Item:= FUnitList.Items.Add;
        Item.Caption:= '(candidate)';
        Item.SubItems.Add(Cand            );
        Item.SubItems.Add(''              );
        Item.SubItems.Add(SectionOf(Cand) );
        Item.Data:= nil; // NOT a rule -- see DoDeleteUnit
      end;
  finally
    FUnitList.Items.EndUpdate;
  end; // try
end; // begin

procedure TConvRulesForm.DoAddSwap(Sender: TObject);
var
  oldU : string        ;
  newU : string        ;
  N    : TRuleNode     ;
  Parts: TArray<string>;
  tmp  : TList<string> ;
  P    : string        ;
begin
  oldU:= '';
  if not InputQuery('Add unit swap', 'Old unit to replace:', oldU) then
    Exit;
  oldU:= Trim(oldU);
  if oldU = '' then
    Exit;
  newU:= '';
  if not InputQuery('Add unit swap', 'New unit(s), comma-separated:', newU) then
    Exit;
  N:= TRuleNode.Create;
  N.Kind   := rnkUseSwap;
  N.SwapOld:= oldU;
  N.Dirty  := True;
  Parts:= newU.Split([',']);
  tmp:= TList<string>.Create;
  try
    for P in Parts do
      if Trim(P) <> '' then
        tmp.Add(Trim(P));
    N.SwapNew:= tmp.ToArray;
  finally
    tmp.Free;
  end;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus(Format('Added #useswap %s -> %s', [oldU, string.Join(', ', N.SwapNew)]));
end; // procedure

procedure TConvRulesForm.DoAddUse(Sender: TObject);
var
  U: string   ;
  N: TRuleNode;
begin
  U:= '';
  if not InputQuery('Add unit', 'Unit to ADD to the uses clause:', U) then
    Exit;
  U:= Trim(U);
  if U = '' then
    Exit;
  N:= TRuleNode.Create; N.Kind:= rnkUse; N.UseUnit:= U; N.Dirty:= True;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Added #use ' + U);
end; // procedure

procedure TConvRulesForm.DoAddUnuse(Sender: TObject);
var
  U: string   ;
  N: TRuleNode;
begin
  U:= '';
  if not InputQuery('Remove unit', 'Unit to REMOVE from the uses clause:', U) then
    Exit;
  U:= Trim(U);
  if U = '' then
    Exit;
  N:= TRuleNode.Create; N.Kind:= rnkUnuse; N.UnuseUnit:= U; N.Dirty:= True;
  InsertUnitNode(N);
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Added #unuse ' + U);
end; // procedure

procedure TConvRulesForm.DoDeleteUnit(Sender: TObject);
var
  N   : TRuleNode     ;
  Cand: string        ;
  Kept: TArray<string>;
  U   : string        ;
begin
  if FUnitList.Selected = nil then
  begin
    SetStatus('Select a unit rule to delete.');
    Exit;
  end;
  N:= TRuleNode(FUnitList.Selected.Data);

  // Data = nil is an Examine CANDIDATE, not a rule: dismissing it drops it from the
  // harvested set only. The rule book is untouched, so no SyncRawFromModel either.
  if N = nil then
  begin
    Cand:= FUnitList.Selected.SubItems[0];
    Kept:= nil;
    for U in FUnitCandidates do
      if not SameText(U, Cand) then
        Kept:= Kept + [U];
    FUnitCandidates:= Kept;
    RefreshUnitList;
    UpdateToolbarEnabled;
    SetStatus('Dismissed candidate unit ' + Cand + '.');
    Exit;
  end; // if

  FBook.Nodes.Remove(N); // TObjectList owns its items -> frees N
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus('Deleted unit rule.');
end; // procedure

procedure TConvRulesForm.DoDeriveUnits(Sender: TObject);
var
  Pairs   : TArray<TConvPair>;
  Heads   : TArray<Integer>  ;
  S       : TUnitSets        ;
  existing: TArray<TRuleNode>;
  addUse  : Integer          ;
  addUnuse: Integer          ;
  i       : Integer          ;
  U       : string           ;
  N       : TRuleNode        ;

  function HasUse(const uu: string): Boolean;
  var
    N: TRuleNode;
  begin
    Result:= False;
    for N in existing do
      if (N.Kind = rnkUse) and SameText(N.UseUnit, uu) then
        Exit(True);
  end;

  function HasUnuse(const uu: string): Boolean;
  var
    N: TRuleNode;
  begin
    Result:= False;
    for N in existing do
      if (N.Kind = rnkUnuse) and SameText(N.UnuseUnit, uu) then
        Exit(True);
  end;

begin
  var LGuard: IInterface:= HourGlass;
  Heads:= FBook.ConvertHeaders;
  if Length(Heads) = 0 then
  begin
    SetStatus('No #convert rules to derive units from.');
    Exit;
  end;
  SetLength(Pairs, Length(Heads));
  for i:= 0 to High(Heads) do
  begin
    Pairs[i].FromType:= FBook.Nodes[Heads[i]].FromType;
    Pairs[i].ToType  := FBook.Nodes[Heads[i]].ToType;
  end;
  SetStatus('Deriving units (resolving declaring units)...');
  S:= DeriveUnits(Pairs, function(const T: string): string begin Result:= FEngine.DeclaringUnitOf(T); end);
  existing:= FBook.UnitNodes;
  addUse:= 0; addUnuse:= 0;
  for U in S.Adds do
    if not HasUse(U) then
    begin
      N:= TRuleNode.Create; N.Kind:= rnkUse; N.UseUnit:= U; N.Dirty:= True;
      InsertUnitNode(N); Inc(addUse);
    end;
  for U in S.Removes do
    if not HasUnuse(U) then
    begin
      N:= TRuleNode.Create; N.Kind:= rnkUnuse; N.UnuseUnit:= U; N.Dirty:= True;
      InsertUnitNode(N); Inc(addUnuse);
    end;
  RefreshUnitList;
  SyncRawFromModel;
  SetStatus(Format('Derived: +%d #use, +%d #unuse (deduped against existing).', [addUse, addUnuse]));
end; // begin

procedure TConvRulesForm.DoCheckUnits(Sender: TObject);
var
  S: TUnitSets;
begin
  S:= NormalizeUnitSets(FBook);
  RefreshUnitList;
  if Length(S.Conflicts) > 0 then
    SetError(Format('Unit conflicts (ADD wins): %s', [string.Join(', ', S.Conflicts)]))
  else
    SetStatus(Format('Units OK: %d add, %d remove, no doubles.', [Length(S.Adds), Length(S.Removes)]));
end;

procedure TConvRulesForm.ClassSearchChange(Sender: TObject);
begin
  RefreshFormTypes;
end;

end.
