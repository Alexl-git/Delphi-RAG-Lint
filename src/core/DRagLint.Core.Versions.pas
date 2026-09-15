unit DRagLint.Core.Versions;

/// <summary>Version ORDERING and the schema_meta key an index is stamped
/// under -- the two things the never-downgrade gate needs and nothing else
/// does. Split out of DRagLint.Core.Model on 2026-09-15 rather than pushing
/// that unit past the 2000-line limit.</summary>
/// <remarks>The version CONSTANTS stay in DRagLint.Core.Model, where both the
/// CLI and the LSP already read them; this unit only knows how to COMPARE two
/// of them. Owner rulings 2026-09-14 (docs\PLAN-multi-client-index-safety.md):
/// the extractor must never downgrade a database, and only the IDE writes.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

const
  /// <summary>schema_meta key under which an index records the fingerprint of
  /// the engine that last COMPLETED a walk over it:
  /// `v=&lt;DRAGLINT_EXTRACTOR_VERSION&gt;;schema=&lt;n&gt;;pp=&lt;0|1&gt;;plat=&lt;p&gt;`.</summary>
  /// <remarks>Written by DRagLint.CLI.CommitIndexerFingerprint only after a run
  /// that ran to completion; read by the never-downgrade gate
  /// (DRagLint.CLI.RefuseIfEngineOlderThanDb) and reported by the LSP server at
  /// startup. One spelling here so the writer and its readers cannot drift.</remarks>
  INDEXER_FINGERPRINT_META_KEY = 'indexer_fingerprint';

/// <summary>Orders two dotted version strings SEMANTICALLY -- numeric limb by
/// numeric limb -- so that '1.100.0' is above '1.16.0' and '1.9.0' is below
/// '1.10.0', which is exactly where a string comparison gets both wrong.</summary>
/// <param name="AVersionA">A version such as '1.16.0-alpha'. Limbs are the
/// dot-separated integers before the first '-'; a missing limb reads as 0.</param>
/// <param name="AVersionB">The version to compare against, same form.</param>
/// <returns>Negative when AVersionA is older than AVersionB, 0 when they name the
/// same release, positive when AVersionA is newer.</returns>
/// <remarks>The pre-release suffix is decided only when every numeric limb is
/// equal, and then per SemVer: a version WITHOUT a suffix is newer than the same
/// numbers WITH one ('1.16.0' &gt; '1.16.0-alpha'); two suffixes compare ordinally.
/// Exists for the never-downgrade gate on the extractor stamp
/// (PLAN-multi-client-index-safety, ruling 1): the pair that would let an old
/// engine through a lexical comparison -- a stamp of 1.10.0 against an engine at
/// 1.9.0 -- is the pair tests\autotest\run_index_never_downgrades.ps1 plants.
/// Pure; no allocation beyond the split.</remarks>
function CompareDottedVersions(const AVersionA, AVersionB: string): Integer;

implementation

uses
  System.SysUtils
  ;

function CompareDottedVersions(const AVersionA, AVersionB: string): Integer;

  { Numeric limbs before the first '-', and the suffix after it (may be ''). }
  procedure Split(const AVersion: string; out ALimbs: TArray<Integer>; out ASuffix: string);
  var
    Core : string        ;
    Parts: TArray<string>;
    I    : Integer       ;
    Dash : Integer       ;
  begin
    Dash:= Pos('-', AVersion);
    if Dash > 0 then
    begin
      Core   := Copy(AVersion, 1, Dash - 1);
      ASuffix:= Copy(AVersion, Dash + 1, MaxInt);
    end
    else
    begin
      Core   := AVersion;
      ASuffix:= '';
    end;
    Parts:= Core.Split(['.']);
    SetLength(ALimbs, Length(Parts));
    for I:= 0 to High(Parts) do ALimbs[I]:= StrToIntDef(Trim(Parts[I]), 0);
  end;

  function LimbAt(const ALimbs: TArray<Integer>; AIndex: Integer): Integer;
  begin
    Result:= if AIndex <= High(ALimbs) then ALimbs[AIndex] else 0;
  end;

var
  LA, LB: TArray<Integer>;
  SA, SB: string         ;
  I     : Integer        ;
  N     : Integer        ;
begin
  Split(AVersionA, LA, SA);
  Split(AVersionB, LB, SB);
  N:= Length(LA);
  if Length(LB) > N then N:= Length(LB);
  for I:= 0 to N - 1 do
  begin
    if LimbAt(LA, I) < LimbAt(LB, I) then Exit(-1);
    if LimbAt(LA, I) > LimbAt(LB, I) then Exit( 1);
  end;
  { Same numbers. SemVer: a release outranks any pre-release of itself. }
  if (SA = '') and (SB <> '') then Exit( 1);
  if (SA <> '') and (SB = '') then Exit(-1);
  Result:= CompareStr(SA, SB);
end;

end.
