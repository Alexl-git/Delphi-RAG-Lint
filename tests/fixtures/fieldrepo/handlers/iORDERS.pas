unit iORDERS;

interface

type
  ImcORDERS = interface
    ['{7C0D8F0B-3B8C-4F3B-9D36-6B1C0B1F5A11}']
    {$REGION 'DB-RAD 2'}
    function GetNOTE: string;
    {$REGION 'Documentation'}
    /// <summary>Note.</summary>
    {$ENDREGION}
    property NOTE: string read GetNOTE;
    {$ENDREGION 'DB-RAD 2'}
  end;

// {$REGION 'DB-RAD 3'} a comment, not a region
const
  /// <summary>Hand-kept.</summary>
  ORDERS_REFNO_MAXLEN = 11;

implementation

end.
