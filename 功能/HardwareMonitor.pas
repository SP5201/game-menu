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
    FLastCpuText: string;
    FLastMemText: string;
    FLastGpuText: string;
    function SampleCpuPercent: Integer;
    function SampleMemoryPercent: Integer;
    function SampleGpuPercent: Integer;
    procedure NotifyUi(const ACpuText, AMemText, AGpuText: string);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RequestStop;
    property OnUpdate: THardwareUpdateProc read FOnUpdate write FOnUpdate;
  end;

function ParseHardwarePercent(const AText: string): Integer;

implementation

uses
  Math, HardwarePdh;

const
  cSampleIntervalMs = 1000;

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
  FillChar(FPreIdleTime, SizeOf(FPreIdleTime), 0);
  FillChar(FPreKernelTime, SizeOf(FPreKernelTime), 0);
  FillChar(FPreUserTime, SizeOf(FPreUserTime), 0);
end;

destructor THardwareSamplerThread.Destroy;
begin
  RequestStop;
  WaitFor;
  FWakeEvent.Free;
  inherited;
end;

procedure THardwareSamplerThread.RequestStop;
begin
  if Terminated then
    Exit;
  Terminate;
  FWakeEvent.SetEvent;
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
  if not Windows.GetSystemTimes(IdleTime, KernelTime, UserTime) then
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
  usage: Double;
begin
  Result := -1;
  usage := HardwarePdhSampleGpuUtilization;
  if usage < 0 then
    Exit;
  Result := Round(usage);
  if Result < 0 then
    Result := 0
  else if Result > 100 then
    Result := 100;
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
