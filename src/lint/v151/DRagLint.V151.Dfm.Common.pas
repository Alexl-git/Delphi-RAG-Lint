unit DRagLint.V151.Dfm.Common;

{ Run v1511 lane V151F (T01) -- the one .dfm node model the v151 form rules share:
  DFM-A (DRagLint.V151.DFMA.Support) and DFM-B (DRagLint.V151.DFMB.Support) used to
  declare TDfmProp (and DFM-A TDfmNode / TDfmNodeKind) each. }

interface

type
  /// <summary>Header kind of one .dfm node.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.Dfm.Common.pas), declaration (DRagLint.V151.DFMA.Support.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmNodeKind = (dnkObject, dnkInherited, dnkInline, dnkItem);  // dl:ok duplicate-global-decl@9546 -- REVIEWED 2026-11-16: Convert.DfmReemit keeps its own copy until the 1.52 consolidation (V151F T01 FOUND); the lint unit must not depend on the converter's unit

  /// <summary>One property line of a .dfm node; Value is the raw text after '=' for a
  /// one-line value and '' for a string, list, blob or collection.</summary>
  /// <remarks>
  /// Col is 1-based and set by the DFM-B parser; DFM-A leaves it 0.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMA.Support.LoadDfm (DRagLint.V151.DFMA.Support.pas), DRagLint.V151.DFMB.Support.CheckDisallowed (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.TDfmModel.Parse (DRagLint.V151.DFMB.Support.pas) ?, DRagLint.V151.DFMB.Support.TDfmObj.Create (DRagLint.V151.DFMB.Support.pas) ? (+3 more)</para>
  /// <para>Used in units: DRagLint.FieldRepo.ParamArray.Prepare, DRagLint.V151.Dfm.Common, DRagLint.V151.DFMA.Support, DRagLint.V151.DFMB.Support, DRagLint.V152.UNCONN.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmProp = record
    /// <summary>Property name, dotted for sub-properties (DataBinding.DataField).</summary>
    Name : string;
    /// <summary>Raw value text; continuation lines are joined with LF.</summary>
    Value: string;
    /// <summary>1-based line of the property name.</summary>
    Line : Integer;
    /// <summary>1-based column of the property name (0 = not recorded).</summary>
    Col  : Integer;
  end;

  /// <summary>One .dfm node. Parent is the index of the enclosing node (-1 for the root).
  /// InInline is True when an enclosing node is an `inline` frame instance: such nodes
  /// belong to the frame class, not to the form class.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.DFMA.Support.pas) ?, DRagLint.V151.DFMA.CheckFieldTypes (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas) ?, DRagLint.V151.DFMA.Support.LoadDfm (DRagLint.V151.DFMA.Support.pas), DRagLint.V152.UNCONN.Support.PropWires (DRagLint.V152.UNCONN.Support.pas) ? (+3 more)</para>
  /// <para>Used in units: DRagLint.V151.DFMA, DRagLint.V151.DFMA.Support, DRagLint.V152.UNCONN, DRagLint.V152.UNCONN.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDfmNode = record
    Name     : string;
    CompClass: string;
    Kind     : TDfmNodeKind;
    Line     : Integer;
    Col      : Integer;
    Parent   : Integer;
    InInline : Boolean;
    Props    : TArray<TDfmProp>;
  end;

implementation

end.
