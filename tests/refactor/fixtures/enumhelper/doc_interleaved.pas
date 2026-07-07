unit DocInterleaved;
interface
type
  TStage = (
    /// <summary>Not yet started.</summary>
    stPending,
    {$REGION 'active states'}
    /// <summary>Currently running.</summary>
    stRunning,
    {$ENDREGION}
    /// <summary>Finished successfully.</summary>
    stDone
  );
implementation
end.
