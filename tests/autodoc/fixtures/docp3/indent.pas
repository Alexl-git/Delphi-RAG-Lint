unit indent;

interface

// v(ADP3 T3g): the INDENTATION fixtures.
//
// `document --apply` used to write every doc-comment line at column 0 no
// matter how deeply the declaration it documents is indented -- the Prefix
// handed to TDocRegions.MergeComment was the hardcoded literal '/// '. For a
// unit-level routine that is invisible; for a class member it silently
// re-formatted the author's documentation on the very first apply, and the
// idempotency compares are per-line Trimmed, so nothing in the battery could
// see it.
//
// One shape per edge case below. EVERY shape carries a CALLER, so Facts is
// non-empty and Merged is genuinely computed: the REPAIR branch is what runs,
// never the Merged='' early exit.
//
// Deliberately NOT all four-space. TTwoSpace is declared at column 0 so its
// members sit at TWO spaces, and TOuter.TInner's member sits at EIGHT, so a
// fix that hardcodes any single indent width cannot pass. TTabbed uses a TAB,
// so a fix that normalizes tabs to spaces cannot pass either.

/// <summary>Unit-level control: this comment sits at column 0 and must STAY
/// at column 0. Without it, a fix that indents unconditionally would go
/// unnoticed.</summary>
procedure UnitLevelControl;

procedure CallsUnitLevelControl;

type
// TTwoSpace is declared at COLUMN 0 on purpose: its members then sit at TWO
// spaces, not the four this codebase normally uses.
TTwoSpace = class
public
  /// <summary>A two-space-indented member.</summary>
  procedure TwoSpaceMember;
end;

  // A nested type: TOuter.TInner's own member sits EIGHT spaces deep.
  TOuter = class
  public
    type
      TInner = class
      public
        /// <summary>A nested type's member, eight spaces deep.</summary>
        procedure DeepMember;
      end;
  end;

  // Indented with a TAB, not spaces. A fix that rebuilds the indentation from
  // a space count instead of copying the declaration's own leading whitespace
  // verbatim converts these to spaces and fails here.
  TTabbed = class
  public
	/// <summary>A tab-indented member.</summary>
	procedure TabMember;
  end;

  // v(ADP3 T3f) interaction: the residual carry-through re-emits an author
  // line the engine models nothing on. Its interior text must survive
  // verbatim AND it must land at the member's indent like every other line --
  // never doubled, never left at column 0 beside indented siblings.
  TResidual = class
  public
    /// <value>Hand-written value tag; unmodeled, must survive verbatim.</value>
    /// <summary>Carries an unmodeled tag beside a real summary.</summary>
    procedure ResidualMember;
  end;

  // A doc region separated from its declaration by a blank line
  // (FindDocRegionAbove tolerates a 1-line gap). Which line's indentation
  // governs? The DECLARATION's -- the comment documents the declaration, so
  // the declaration is the anchor. Pinned here.
  TGapped = class
  public
      /// <summary>Separated from its declaration by a blank line, and
      /// deliberately mis-indented to six spaces so the answer is
      /// unambiguous.</summary>

    procedure GappedMember;
  end;

  // The ALREADY-DAMAGED case. This starts correctly indented; the runner
  // de-indents its whole block to column 0 after cycle 1, exactly as a
  // pre-fix build would have left it, and then asserts the engine puts it
  // back. That is option (B) -- indent on write PLUS a deliberate re-indent
  // of files an earlier build already flattened.
  TDamaged = class
  public
    /// <summary>Gets de-indented by the runner, then must be restored.</summary>
    procedure DamagedMember;
  end;

  // No comment at all: the FRESH-insert branch must place its new block at
  // the member's indent, not at column 0.
  TFresh = class
  public
    procedure FreshMember;
  end;

procedure CallsMembers;

implementation

procedure UnitLevelControl;
begin
end;

procedure CallsUnitLevelControl;
begin
  UnitLevelControl;
end;

procedure TTwoSpace.TwoSpaceMember;
begin
end;

procedure TOuter.TInner.DeepMember;
begin
end;

procedure TTabbed.TabMember;
begin
end;

procedure TResidual.ResidualMember;
begin
end;

procedure TGapped.GappedMember;
begin
end;

procedure TDamaged.DamagedMember;
begin
end;

procedure TFresh.FreshMember;
begin
end;

procedure CallsMembers;
var
  LTwo    : TTwoSpace     ;
  LDeep   : TOuter.TInner ;
  LTab    : TTabbed       ;
  LResid  : TResidual     ;
  LGap    : TGapped       ;
  LDamaged: TDamaged      ;
  LFresh  : TFresh        ;
begin
  LTwo    := TTwoSpace.Create    ;
  LDeep   := TOuter.TInner.Create;
  LTab    := TTabbed.Create      ;
  LResid  := TResidual.Create    ;
  LGap    := TGapped.Create      ;
  LDamaged:= TDamaged.Create     ;
  LFresh  := TFresh.Create       ;
  LTwo.TwoSpaceMember  ;
  LDeep.DeepMember     ;
  LTab.TabMember       ;
  LResid.ResidualMember;
  LGap.GappedMember    ;
  LDamaged.DamagedMember;
  LFresh.FreshMember   ;
end;

end.
