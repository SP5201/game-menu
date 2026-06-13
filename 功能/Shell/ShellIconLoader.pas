unit ShellIconLoader;

interface

uses
  Windows, Messages, SysUtils, Classes, SyncObjs, ActiveX, ShellIconHelper, XCGUI;

const
  WM_QD_LIST_ICON_READY = WM_APP + 112;
  WM_QD_LIST_DEFERRED_REFRESH = WM_APP + 113;
  cIconLoaderWorkerCount = 3;

type
  PShellIconLoadResult = ^TShellIconLoadResult;
  TShellIconLoadResult = record
    ListGeneration: Cardinal;
    ScrollGeneration: Cardinal;
    ListEle: HELE;
    ItemIndex: Integer;
    FilePath: string;
    IconCachePath: string;
    IconCachePathOut: string;
    PixelKey: string;
    CachedImage: HIMAGE;
    FromCache: Boolean;
  end;

procedure ShellIconLoaderInit(AMainWindow: HWINDOW);
procedure ShellIconLoaderShutdown;
function ShellIconLoaderBumpListGeneration: Cardinal;
function ShellIconLoaderBumpScrollGeneration: Cardinal;
function ShellIconLoaderCurrentListGeneration: Cardinal;
function ShellIconLoaderCurrentScrollGeneration: Cardinal;
function ShellIconLoaderRequestItem(AListGeneration, AScrollGeneration: Cardinal; AListEle: HELE;
  AItemIndex: Integer; const AFilePath, AIconCachePath: string; AHighPriority: Boolean = False): Boolean;
procedure ShellIconLoaderScheduleDeferredListRefresh;
function ShellIconLoaderTryHandleMessage(AMsg: UINT; ALParam: LPARAM): Boolean;
procedure ShellIconLoaderDisposeResult(AData: PShellIconLoadResult);

implementation

type
  PShellIconLoadJob = ^TShellIconLoadJob;
  TShellIconLoadJob = record
    ListGeneration: Cardinal;
    ScrollGeneration: Cardinal;
    ListEle: HELE;
    ItemIndex: Integer;
    FilePath: string;
    IconCachePath: string;
    RequestKey: string;
  end;

  TShellIconLoaderThread = class(TThread)
  private
    FMainWindow: HWINDOW;
    FWakeEvent: THandle;
    procedure DrainQueue;
    procedure PostResult(const AJob: TShellIconLoadJob; const AFromCache: Boolean;
      const APixelKey, AIconCachePathOut: string; ACachedImage: HIMAGE = 0);
    function JobStillValid(const AJob: TShellIconLoadJob): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AMainWindow: HWINDOW);
    destructor Destroy; override;
    procedure SignalWork;
  end;

var
  GMainWindow: HWINDOW;
  GLoaderThreads: array of TShellIconLoaderThread;
  GListGeneration: Cardinal;
  GScrollGeneration: Cardinal;
  GQueue: TList;
  GPendingKeys: TStringList;
  GQueueLock: TCriticalSection;

procedure SignalAllLoaderWorkers;
var
  i: Integer;
begin
  for i := 0 to High(GLoaderThreads) do
    if GLoaderThreads[i] <> nil then
      GLoaderThreads[i].SignalWork;
end;

procedure ClearLoaderQueueLocked;
var
  i: Integer;
  job: PShellIconLoadJob;
begin
  if GQueue = nil then
    Exit;
  for i := 0 to GQueue.Count - 1 do
  begin
    job := PShellIconLoadJob(GQueue.List[i]);
    if job <> nil then
      Dispose(job);
  end;
  GQueue.Clear;
  if GPendingKeys <> nil then
    GPendingKeys.Clear;
end;

procedure PostIconResult(AMainWindow: HWINDOW; AData: PShellIconLoadResult);
var
  hRealWnd: Windows.HWND;
begin
  if XC_GetObjectType(AMainWindow) <> XC_WINDOW then
  begin
    ShellIconLoaderDisposeResult(AData);
    Exit;
  end;
  if XC_PostMessage(AMainWindow, WM_QD_LIST_ICON_READY, 0, LPARAM(AData)) then
    Exit;
  hRealWnd := XWnd_GetHWND(AMainWindow);
  if hRealWnd <> 0 then
    if PostMessageW(hRealWnd, WM_QD_LIST_ICON_READY, 0, LPARAM(AData)) then
      Exit;
  ShellIconLoaderDisposeResult(AData);
end;

procedure PostIconLoadResult(AMainWindow: HWINDOW; AListGeneration, AScrollGeneration: Cardinal;
  AListEle: HELE; AItemIndex: Integer; const AFilePath, AIconCachePath, AIconCachePathOut, APixelKey: string;
  AFromCache: Boolean; ACachedImage: HIMAGE);
var
  data: PShellIconLoadResult;
begin
  New(data);
  data^.ListGeneration := AListGeneration;
  data^.ScrollGeneration := AScrollGeneration;
  data^.ListEle := AListEle;
  data^.ItemIndex := AItemIndex;
  data^.FilePath := AFilePath;
  data^.IconCachePath := AIconCachePath;
  data^.IconCachePathOut := AIconCachePathOut;
  data^.PixelKey := APixelKey;
  data^.CachedImage := ACachedImage;
  data^.FromCache := AFromCache;
  PostIconResult(AMainWindow, data);
end;

{ TShellIconLoaderThread }

constructor TShellIconLoaderThread.Create(AMainWindow: HWINDOW);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FMainWindow := AMainWindow;
  FWakeEvent := CreateEvent(nil, False, False, nil);
end;

destructor TShellIconLoaderThread.Destroy;
begin
  if FWakeEvent <> 0 then
    CloseHandle(FWakeEvent);
  inherited;
end;

procedure TShellIconLoaderThread.SignalWork;
begin
  if FWakeEvent <> 0 then
    SetEvent(FWakeEvent);
end;

function TShellIconLoaderThread.JobStillValid(const AJob: TShellIconLoadJob): Boolean;
begin
  Result := (AJob.ListGeneration = GListGeneration) and (AJob.ScrollGeneration = GScrollGeneration);
end;

procedure TShellIconLoaderThread.PostResult(const AJob: TShellIconLoadJob; const AFromCache: Boolean;
  const APixelKey, AIconCachePathOut: string; ACachedImage: HIMAGE);
begin
  PostIconLoadResult(FMainWindow, AJob.ListGeneration, AJob.ScrollGeneration, AJob.ListEle, AJob.ItemIndex,
    AJob.FilePath, AJob.IconCachePath, AIconCachePathOut, APixelKey, AFromCache, ACachedImage);
end;

procedure TShellIconLoaderThread.DrainQueue;
var
  job: PShellIconLoadJob;
  pixel: TShellIconPixelData;
  targetPath, pixelKey: string;
  cachedImg: HIMAGE;
  i: Integer;
begin
  job := nil;
  while not Terminated do
  begin
    GQueueLock.Enter;
    try
      if GQueue.Count = 0 then
        Break;
      job := PShellIconLoadJob(GQueue.List[0]);
      GQueue.Delete(0);
      if job <> nil then
      begin
        i := GPendingKeys.IndexOf(job^.RequestKey);
        if i >= 0 then
          GPendingKeys.Delete(i);
      end;
    finally
      GQueueLock.Leave;
    end;

    if job = nil then
      Continue;
    try
      if not JobStillValid(job^) then
        Continue;

      targetPath := job^.FilePath;
      if targetPath = '' then
        Continue;

      if TryAcquireCachedListFileImage(job^.IconCachePath, targetPath, cachedImg) then
      begin
        if not JobStillValid(job^) then
          Continue;
        if cachedImg <> 0 then
          PostResult(job^, True, '', job^.IconCachePath, cachedImg)
        else
          PostResult(job^, False, '', job^.IconCachePath);
        Continue;
      end;

      FillChar(pixel, SizeOf(pixel), 0);
      if not ExtractShellIconPixels(targetPath, job^.IconCachePath, pixel) then
      begin
        if JobStillValid(job^) then
          PostResult(job^, False, '', job^.IconCachePath);
        Continue;
      end;

      if not JobStillValid(job^) then
        Continue;
      pixelKey := BuildListFileImageRequestKey(job^.IconCachePath, targetPath);
      StorePendingIconPixels(pixelKey, pixel);
      PostResult(job^, False, pixelKey, pixel.IconCachePath);
    finally
      Dispose(job);
    end;
  end;
end;

procedure TShellIconLoaderThread.Execute;
begin
  CoInitialize(nil);
  try
    while not Terminated do
    begin
      DrainQueue;
      if Terminated then
        Break;
      WaitForSingleObject(FWakeEvent, INFINITE);
    end;
    DrainQueue;
  finally
    CoUninitialize;
  end;
end;

procedure ShellIconLoaderInit(AMainWindow: HWINDOW);
var
  i: Integer;
begin
  if Length(GLoaderThreads) > 0 then
    Exit;
  GMainWindow := AMainWindow;
  GListGeneration := 1;
  GScrollGeneration := 0;
  GQueue := TList.Create;
  GPendingKeys := TStringList.Create;
  GPendingKeys.Sorted := True;
  GPendingKeys.Duplicates := dupIgnore;
  GQueueLock := TCriticalSection.Create;
  SetLength(GLoaderThreads, cIconLoaderWorkerCount);
  for i := 0 to High(GLoaderThreads) do
  begin
    GLoaderThreads[i] := TShellIconLoaderThread.Create(AMainWindow);
    GLoaderThreads[i].Start;
  end;
end;

procedure ShellIconLoaderShutdown;
var
  i: Integer;
  th: TShellIconLoaderThread;
begin
  for i := 0 to High(GLoaderThreads) do
  begin
    th := GLoaderThreads[i];
    GLoaderThreads[i] := nil;
    if th <> nil then
    begin
      th.Terminate;
      th.SignalWork;
      th.WaitFor;
      FreeAndNil(th);
    end;
  end;
  SetLength(GLoaderThreads, 0);
  if GQueueLock <> nil then
  begin
    GQueueLock.Enter;
    try
      ClearLoaderQueueLocked;
    finally
      GQueueLock.Leave;
    end;
  end;
  FreeAndNil(GQueue);
  FreeAndNil(GPendingKeys);
  FreeAndNil(GQueueLock);
  ClearAllPendingIconPixels;
end;

function ShellIconLoaderBumpListGeneration: Cardinal;
begin
  Inc(GListGeneration);
  if GListGeneration = 0 then
    GListGeneration := 1;
  Result := GListGeneration;
  ClearAllPendingIconPixels;
  if GQueueLock = nil then
    Exit;
  GQueueLock.Enter;
  try
    ClearLoaderQueueLocked;
  finally
    GQueueLock.Leave;
  end;
  SignalAllLoaderWorkers;
end;

function ShellIconLoaderBumpScrollGeneration: Cardinal;
begin
  Inc(GScrollGeneration);
  if GScrollGeneration = 0 then
    GScrollGeneration := 1;
  Result := GScrollGeneration;
  if GQueueLock = nil then
    Exit;
  GQueueLock.Enter;
  try
    ClearLoaderQueueLocked;
  finally
    GQueueLock.Leave;
  end;
  SignalAllLoaderWorkers;
end;

function ShellIconLoaderCurrentListGeneration: Cardinal;
begin
  Result := GListGeneration;
end;

function ShellIconLoaderCurrentScrollGeneration: Cardinal;
begin
  Result := GScrollGeneration;
end;

function ShellIconLoaderRequestItem(AListGeneration, AScrollGeneration: Cardinal; AListEle: HELE;
  AItemIndex: Integer; const AFilePath, AIconCachePath: string; AHighPriority: Boolean): Boolean;
var
  job: PShellIconLoadJob;
  reqKey: string;
begin
  Result := False;
  if (Length(GLoaderThreads) = 0) or (Trim(AFilePath) = '') then
    Exit;
  reqKey := BuildListFileImageRequestKey(AIconCachePath, AFilePath);
  GQueueLock.Enter;
  try
    if GPendingKeys.IndexOf(reqKey) >= 0 then
      Exit(True);
    New(job);
    job^.ListGeneration := AListGeneration;
    job^.ScrollGeneration := AScrollGeneration;
    job^.ListEle := AListEle;
    job^.ItemIndex := AItemIndex;
    job^.FilePath := AFilePath;
    job^.IconCachePath := AIconCachePath;
    job^.RequestKey := reqKey;
    GPendingKeys.Add(reqKey);
    if AHighPriority then
      GQueue.Insert(0, job)
    else
      GQueue.Add(job);
    Result := True;
  finally
    GQueueLock.Leave;
  end;
  if Result then
    SignalAllLoaderWorkers;
end;

procedure ShellIconLoaderScheduleDeferredListRefresh;
begin
  if GMainWindow = 0 then
    Exit;
  XC_PostMessage(GMainWindow, WM_QD_LIST_DEFERRED_REFRESH, 0, 0);
end;

procedure ShellIconLoaderDisposeResult(AData: PShellIconLoadResult);
begin
  if AData = nil then
    Exit;
  if (not AData^.FromCache) and (AData^.PixelKey <> '') then
    DiscardPendingIconPixelEntry(AData^.PixelKey);
  if XC_GetObjectType(AData^.CachedImage) = XC_IMAGE then
    XImage_Release(AData^.CachedImage);
  Dispose(AData);
end;

function ShellIconLoaderTryHandleMessage(AMsg: UINT; ALParam: LPARAM): Boolean;
begin
  Result := (AMsg = WM_QD_LIST_ICON_READY) or (AMsg = WM_QD_LIST_DEFERRED_REFRESH);
end;

initialization

finalization
  ShellIconLoaderShutdown;

end.
