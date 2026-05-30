unit HardwareMonitor;

interface

uses
  Windows, SysUtils, Classes, SyncObjs;

type
  THardwareUpdateProc = procedure(const ACpuText, AMemText, AGpuText: string);

  THardwareSamplerThread = class(TThread)
  private
    FWakeEvent: TEvent;
    FOnUpdate: THardwareUpdateProc;
    FPreIdleTime: TFileTime;
    FPreKernelTime: TFileTime;
    FPreUserTime: TFileTime;
    FHasCpuBase: Boolean;
    FGpuQuery: THandle;
    FGpuCounter: THandle;
    FGpuPdhReady: Boolean;
    FLastCpuText: string;
    FLastMemText: string;
    FLastGpuText: string;
    function SampleCpuPercent: Integer;
    function SampleMemoryPercent: Integer;
    function SampleGpuPercent: Integer;
    function InitGpuPdh: Boolean;
    procedure CleanupGpuPdh;
    procedure NotifyUi(const ACpuText, AMemText, AGpuText: string);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property OnUpdate: THardwareUpdateProc read FOnUpdate write FOnUpdate;
  end;

function ParseHardwarePercent(const AText: string): Integer;

implementation

uses
  Math;

const
  cSampleIntervalMs = 1000;
  PDH_FMT_DOUBLE = $00000200;
  PDH_FMT_NOCAP100 = $00008000;
  ERROR_SUCCESS = 0;
  PDH_MORE_DATA = DWORD($800007D2);

type
  PDH_STATUS = Longint;
  PPDH_FMT_COUNTERVALUE = ^TPDH_FMT_COUNTERVALUE;
  TPDH_FMT_COUNTERVALUE = record
    CStatus: DWORD;
    doubleValue: Double;
  end;

  PPDH_FMT_COUNTERVALUE_ITEM_W = ^TPDH_FMT_COUNTERVALUE_ITEM_W;
  TPDH_FMT_COUNTERVALUE_ITEM_W = record
    szName: PWideChar;
    FmtValue: TPDH_FMT_COUNTERVALUE;
  end;

function PdhOpenQueryW(szDataSource: PWideChar; dwUserData: ULONG_PTR; out phQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhAddEnglishCounterW(hQuery: THandle; szFullCounterPath: PWideChar; dwUserData: ULONG_PTR; out phCounter: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhAddCounterW(hQuery: THandle; szFullCounterPath: PWideChar; dwUserData: ULONG_PTR; out phCounter: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhCollectQueryData(hQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhGetFormattedCounterArrayW(hCounter: THandle; dwFormat: DWORD; lpdwBufferSize: PDWORD; lpdwItemCount: PDWORD; ItemBuffer: PPDH_FMT_COUNTERVALUE_ITEM_W): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhCloseQuery(hQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';

function FileTimeDiff(const AOldTime, ANewTime: TFileTime): Int64;
var
  OldValue: UInt64;
  NewValue: UInt64;
begin
  OldValue := (UInt64(AOldTime.dwHighDateTime) shl 32) or AOldTime.dwLowDateTime;
  NewValue := (UInt64(ANewTime.dwHighDateTime) shl 32) or ANewTime.dwLowDateTime;
  if NewValue >= OldValue then
    Result := Int64(NewValue - OldValue)
  else
    Result := 0;
end;

constructor THardwareSamplerThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  FHasCpuBase := False;
  FGpuQuery := 0;
  FGpuCounter := 0;
  FGpuPdhReady := False;
  FillChar(FPreIdleTime, SizeOf(FPreIdleTime), 0);
  FillChar(FPreKernelTime, SizeOf(FPreKernelTime), 0);
  FillChar(FPreUserTime, SizeOf(FPreUserTime), 0);
end;

destructor THardwareSamplerThread.Destroy;
begin
  Terminate;
  FWakeEvent.SetEvent;
  WaitFor;
  CleanupGpuPdh;
  FWakeEvent.Free;
  inherited;
end;

function THardwareSamplerThread.InitGpuPdh: Boolean;
var
  Status: PDH_STATUS;
begin
  Result := False;
  FGpuQuery := 0;
  FGpuCounter := 0;
  Status := PdhOpenQueryW(nil, 0, FGpuQuery);
  if Status <> ERROR_SUCCESS then
    Exit;

  Status := PdhAddEnglishCounterW(FGpuQuery, '\GPU Engine(*)\Utilization Percentage', 0, FGpuCounter);
  if Status <> ERROR_SUCCESS then
    Status := PdhAddCounterW(FGpuQuery, '\GPU Engine(*)\Utilization Percentage', 0, FGpuCounter);
  if Status <> ERROR_SUCCESS then
  begin
    PdhCloseQuery(FGpuQuery);
    FGpuQuery := 0;
    Exit;
  end;

  Status := PdhCollectQueryData(FGpuQuery);
  if Status <> ERROR_SUCCESS then
  begin
    PdhCloseQuery(FGpuQuery);
    FGpuQuery := 0;
    FGpuCounter := 0;
    Exit;
  end;
  FGpuPdhReady := True;
  Result := True;
end;

procedure THardwareSamplerThread.CleanupGpuPdh;
begin
  FGpuPdhReady := False;
  if FGpuQuery <> 0 then
    PdhCloseQuery(FGpuQuery);
  FGpuQuery := 0;
  FGpuCounter := 0;
end;

function THardwareSamplerThread.SampleCpuPercent: Integer;
var
  IdleTime: TFileTime;
  KernelTime: TFileTime;
  UserTime: TFileTime;
  IdleDelta: Int64;
  KernelDelta: Int64;
  UserDelta: Int64;
  TotalDelta: Int64;
begin
  Result := 0;
  if not GetSystemTimes(IdleTime, KernelTime, UserTime) then
    Exit;

  if not FHasCpuBase then
  begin
    FPreIdleTime := IdleTime;
    FPreKernelTime := KernelTime;
    FPreUserTime := UserTime;
    FHasCpuBase := True;
    Exit;
  end;

  IdleDelta := FileTimeDiff(FPreIdleTime, IdleTime);
  KernelDelta := FileTimeDiff(FPreKernelTime, KernelTime);
  UserDelta := FileTimeDiff(FPreUserTime, UserTime);
  TotalDelta := KernelDelta + UserDelta;
  if TotalDelta > 0 then
    Result := Round(Abs((TotalDelta - IdleDelta) * 100.0 / TotalDelta))
  else
    Result := 0;

  if Result < 0 then
    Result := 0
  else if Result > 100 then
    Result := 100;

  FPreIdleTime := IdleTime;
  FPreKernelTime := KernelTime;
  FPreUserTime := UserTime;
end;

function THardwareSamplerThread.SampleMemoryPercent: Integer;
var
  memStatus: TMemoryStatusEx;
begin
  Result := 0;
  memStatus.dwLength := SizeOf(memStatus);
  if not GlobalMemoryStatusEx(memStatus) then
    Exit;
  Result := memStatus.dwMemoryLoad;
  if Result < 0 then
    Result := 0
  else if Result > 100 then
    Result := 100;
end;

function THardwareSamplerThread.SampleGpuPercent: Integer;
var
  Status: PDH_STATUS;
  BufferSize: DWORD;
  ItemCount: DWORD;
  Buffer: Pointer;
  Items: PPDH_FMT_COUNTERVALUE_ITEM_W;
  i: Integer;
  Usage: Double;
  EngineGroup: string;
  SepIndex: Integer;
  GroupUsage: TStringList;
  GroupValue: Double;
  MaxUsage: Double;
begin
  Result := -1;
  if not FGpuPdhReady then
  begin
    if not InitGpuPdh then
      Exit;
  end;

  Status := PdhCollectQueryData(FGpuQuery);
  if Status <> ERROR_SUCCESS then
    Exit;

  BufferSize := 0;
  ItemCount := 0;
  Status := PdhGetFormattedCounterArrayW(FGpuCounter, PDH_FMT_DOUBLE, @BufferSize, @ItemCount, nil);
  if (DWORD(Status) <> PDH_MORE_DATA) and (Status <> ERROR_SUCCESS) then
    Exit;
  if BufferSize = 0 then
    Exit;

  GroupUsage := TStringList.Create;
  GroupUsage.Sorted := False;
  GetMem(Buffer, BufferSize);
  try
    Status := PdhGetFormattedCounterArrayW(FGpuCounter, PDH_FMT_DOUBLE, @BufferSize, @ItemCount, PPDH_FMT_COUNTERVALUE_ITEM_W(Buffer));
    if Status <> ERROR_SUCCESS then
      Exit;

    MaxUsage := 0;
    Items := PPDH_FMT_COUNTERVALUE_ITEM_W(Buffer);
    for i := 0 to Integer(ItemCount) - 1 do
    begin
      EngineGroup := LowerCase(string(Items^.szName));
      SepIndex := LastDelimiter('_', EngineGroup);
      if SepIndex > 0 then
        EngineGroup := Copy(EngineGroup, SepIndex + 1, MaxInt);

      GroupValue := Items^.FmtValue.doubleValue;
      if GroupValue < 0 then
        GroupValue := 0;

      SepIndex := GroupUsage.IndexOfName(EngineGroup);
      if SepIndex < 0 then
        GroupUsage.Add(EngineGroup + '=' + FloatToStr(GroupValue))
      else
      begin
        Usage := StrToFloatDef(GroupUsage.ValueFromIndex[SepIndex], 0);
        GroupUsage.ValueFromIndex[SepIndex] := FloatToStr(Usage + GroupValue);
      end;
      Inc(Items);
    end;

    for i := 0 to GroupUsage.Count - 1 do
    begin
      Usage := StrToFloatDef(GroupUsage.ValueFromIndex[i], 0);
      if Usage > MaxUsage then
        MaxUsage := Usage;
    end;

    if MaxUsage > 100 then
      MaxUsage := 100;
    Result := Round(MaxUsage);
  finally
    FreeMem(Buffer);
    GroupUsage.Free;
  end;
end;

procedure THardwareSamplerThread.NotifyUi(const ACpuText, AMemText, AGpuText: string);
begin
  if not Assigned(FOnUpdate) then
    Exit;
  if (ACpuText = FLastCpuText) and (AMemText = FLastMemText) and (AGpuText = FLastGpuText) then
    Exit;
  FLastCpuText := ACpuText;
  FLastMemText := AMemText;
  FLastGpuText := AGpuText;
  FOnUpdate(ACpuText, AMemText, AGpuText);
end;

procedure THardwareSamplerThread.Execute;
var
  CpuUsage: Integer;
  MemUsage: Integer;
  GpuUsage: Integer;
  GpuText: string;
begin
  while not Terminated do
  begin
    CpuUsage := SampleCpuPercent;
    MemUsage := SampleMemoryPercent;
    GpuUsage := SampleGpuPercent;
    if GpuUsage >= 0 then
      GpuText := Format('%d%%', [GpuUsage])
    else
      GpuText := '--';
    NotifyUi(Format('%d%%', [CpuUsage]), Format('%d%%', [MemUsage]), GpuText);
    FWakeEvent.WaitFor(cSampleIntervalMs);
  end;
end;

function ParseHardwarePercent(const AText: string): Integer;
var
  s: string;
begin
  s := Trim(StringReplace(AText, '%', '', [rfReplaceAll]));
  Result := EnsureRange(StrToIntDef(s, 0), 0, 100);
end;

end.
