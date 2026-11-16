unit DRagLint.V151.Dfm.Common;

{ Run v1511 lane V151F (T01) -- the one .dfm node model the v151 form rules share:
  DFM-A (DRagLint.V151.DFMA.Support) and DFM-B (DRagLint.V151.DFMB.Support) used to
  declare TDfmProp (and DFM-A TDfmNode / TDfmNodeKind) each. }

interface

type
  /// <summary>Header kind of one .dfm node.</summary>
  TDfmNodeKind = (dnkObject, dnkInherited, dnkInline, dnkItem);

  /// <summary>One property line of a .dfm node; Value is the raw text after '=' for a
  /// one-line value and '' for a string, list, blob or collection.</summary>
  /// <remarks>Col is 1-based and set by the DFM-B parser; DFM-A leaves it 0.</remarks>
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
