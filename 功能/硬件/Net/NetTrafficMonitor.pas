unit NetTrafficMonitor;

{
  状态栏网速：GetBestInterface 选取默认路由网卡，读取 InOctets/OutOctets 差分计算速率。
  与任务管理器一致，只统计实际走流量的那张网卡（VPN 活跃时统计 VPN 口）。
  悬停网卡详情由 UI 调用 NetInfo 模块。
}

interface

uses
  SysUtils, Classes, SyncObjs, Windows;

type
  TNetTrafficUpdateProc = procedure(const sDown, sUp: string);

  { 后台线程 GetIfTable2 采样；采样后回调刷新 UI。 }
  TNetTrafficSamplerThread = class(TThread)
  private
    FLock: TCriticalSection;
    FWakeEvent: TEvent;
    FOnUpdate: TNetTrafficUpdateProc;
    FPausedFlag: Longint;
    FLastIn: UInt64;
    FLastOut: UInt64;
    FLastTick: UInt64;
    FHasLast: Boolean;
    FLastNotifyDown: UInt64;
    FLastNotifyUp: UInt64;
    FMonitoredIfIndex: DWORD;
    procedure ResetSampler;
    procedure SampleTick(out ADownBps, AUpBps: UInt64);
    procedure NotifyUiIfChanged(const ADownBps, AUpBps: UInt64);
    procedure SetPaused(const APaused: Boolean);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RequestStop;
    procedure PauseSampler;
    procedure ResumeSampler;
    property OnUpdate: TNetTrafficUpdateProc read FOnUpdate write FOnUpdate;
  end;

function NetTrafficFormatDisplay(const BytesPerSec: UInt64): string;

implementation

uses
  NetIfTable2;

const
  cSampleIntervalMs = 1500;

function GetTickCount64: UInt64; stdcall;
  external 'kernel32.dll' name 'GetTickCount64';

function NetTrafficFormatDisplay(const BytesPerSec: UInt64): string;
var
  d: Double;
begin
  if BytesPerSec < 1024 then
    Result := IntToStr(BytesPerSec) + ' B/s'
  else if BytesPerSec < UInt64(1024) * 1024 then
  begin
    d := BytesPerSec / 1024.0;
    Result := IntToStr(Round(d)) + ' KB/s';
  end
  else if BytesPerSec < UInt64(1024) * 1024 * 1024 then
  begin
    d := BytesPerSec / (1024.0 * 1024.0);
    Result := IntToStr(Round(d)) + ' MB/s';
  end
  else if BytesPerSec < UInt64(1024) * 1024 * 1024 * 1024 then
  begin
    d := BytesPerSec / (1024.0 * 1024.0 * 1024.0);
    Result := IntToStr(Round(d)) + ' GB/s';
  end
  else
  begin
    d := BytesPerSec / (1024.0 * 1024.0 * 1024.0 * 1024.0);
    Result := IntToStr(Round(d)) + ' TB/s';
  end;
end;

procedure TNetTrafficSamplerThread.ResetSampler;
begin
  FLock.Enter;
  try
    FHasLast := False;
    FMonitoredIfIndex := 0;
    FLastNotifyDown := UInt64(-1);
    FLastNotifyUp := UInt64(-1);
  finally
    FLock.Leave;
  end;
end;

procedure TNetTrafficSamplerThread.SampleTick(out ADownBps, AUpBps: UInt64);
var
  ifIdx: DWORD;
  inOct, outOct: UInt64;
  t, span, deltaIn, deltaOut: UInt64;
begin
  ADownBps := 0;
  AUpBps := 0;
  if not NetIfCollectDefaultRouteBytes(ifIdx, inOct, outOct) then
  begin
    FHasLast := False;
    FMonitoredIfIndex := 0;
    Exit;
  end;
  if (FMonitoredIfIndex <> 0) and (ifIdx <> FMonitoredIfIndex) then
    FHasLast := False;
  FMonitoredIfIndex := ifIdx;
  t := GetTickCount64;
  if not FHasLast then
  begin
    FLastIn := inOct;
    FLastOut := outOct;
    FLastTick := t;
    FHasLast := True;
    Exit;
  end;
  span := t - FLastTick;
  if span = 0 then
    span := 1;
  if (inOct < FLastIn) or (outOct < FLastOut) then
  begin
    FLastIn := inOct;
    FLastOut := outOct;
    FLastTick := t;
    Exit;
  end;
  deltaIn := inOct - FLastIn;
  deltaOut := outOct - FLastOut;
  ADownBps := (deltaIn * 1000 + span div 2) div span;
  AUpBps := (deltaOut * 1000 + span div 2) div span;
  FLastIn := inOct;
  FLastOut := outOct;
  FLastTick := t;
end;

procedure TNetTrafficSamplerThread.NotifyUiIfChanged(const ADownBps, AUpBps: UInt64);
begin
  if not Assigned(FOnUpdate) then
    Exit;
  FLock.Enter;
  try
    if (ADownBps = FLastNotifyDown) and (AUpBps = FLastNotifyUp) then
      Exit;
    FLastNotifyDown := ADownBps;
    FLastNotifyUp := AUpBps;
  finally
    FLock.Leave;
  end;
  FOnUpdate(NetTrafficFormatDisplay(ADownBps), NetTrafficFormatDisplay(AUpBps));
end;

constructor TNetTrafficSamplerThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  FOnUpdate := nil;
  FPausedFlag := 0;
  FLastNotifyDown := UInt64(-1);
  FLastNotifyUp := UInt64(-1);
  FMonitoredIfIndex := 0;
end;

destructor TNetTrafficSamplerThread.Destroy;
begin
  RequestStop;
  WaitFor;
  FWakeEvent.Free;
  FLock.Free;
  inherited;
end;

procedure TNetTrafficSamplerThread.RequestStop;
begin
  if Terminated then
    Exit;
  Terminate;
  FWakeEvent.SetEvent;
end;

procedure TNetTrafficSamplerThread.SetPaused(const APaused: Boolean);
begin
  InterlockedExchange(FPausedFlag, Ord(APaused));
  FWakeEvent.SetEvent;
  ResetSampler;
end;

procedure TNetTrafficSamplerThread.PauseSampler;
begin
  SetPaused(True);
end;

procedure TNetTrafficSamplerThread.ResumeSampler;
begin
  SetPaused(False);
end;

procedure TNetTrafficSamplerThread.Execute;
var
  d, u: UInt64;
begin
  while not Terminated do
  begin
    if FPausedFlag <> 0 then
    begin
      FWakeEvent.WaitFor(INFINITE);
      Continue;
    end;
    try
      SampleTick(d, u);
    except
      d := 0;
      u := 0;
    end;
    NotifyUiIfChanged(d, u);
    FWakeEvent.WaitFor(cSampleIntervalMs);
  end;
end;

end.
