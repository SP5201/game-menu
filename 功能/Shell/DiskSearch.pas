unit DiskSearch;

interface

uses
  Windows, Messages, SysUtils, Classes, LibraryStore, XCGUI, EverythingIndex, SearchVM;

const
  WM_QD_DISK_SEARCH = WM_APP + 110;
  WM_QD_DISK_SEARCH_ERROR = WM_APP + 111;
  WM_QD_DISK_SEARCH_SORT_DONE = WM_APP + 114;
  WM_QD_INDEX_HIT_CHANGES = WM_APP + 116;

type
  TDiskSearchError = (dseIndexMissing, dseIndexAccess, dseQueryFailed);

  PSearchSortDoneMsg = ^TSearchSortDoneMsg;
  TSearchSortDoneMsg = record
    Generation: Cardinal;
    SortMs: Cardinal;
    HitIndices: TEverythingHitArray;
  end;

  PDiskSearchResult = ^TDiskSearchResult;
  TDiskSearchResult = record
    Needle: string;
    Generation: Cardinal;
    TotalCount: Cardinal;
    IndexWaitMs: Cardinal;
    QueryElapsedMs: Cardinal;
    SearchTiming: TSearchTiming;
    HitIndices: TEverythingHitArray;
  end;

  PDiskSearchErrorMsg = ^TDiskSearchErrorMsg;
  TDiskSearchErrorMsg = record
    ErrorKind: TDiskSearchError;
    Generation: Cardinal;
    Needle: string;
  end;

procedure DiskSearchRequest(AMainWindow: HWINDOW; const ANeedle: string;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
function DiskSearchPrepare(AMainWindow: HWINDOW; out AError: TDiskSearchError): Boolean;
function DiskSearchCurrentGeneration: Cardinal;
function DiskSearchIsLatestGeneration(const AGeneration: Cardinal): Boolean;
procedure DiskSearchStop;
procedure DiskSearchStopAndWait;
procedure DiskSearchSetHandlers(AOnResult, AOnError: Pointer);
procedure DiskSearchDisposeResult(AData: PDiskSearchResult);
procedure DiskSearchDisposeError(AData: PDiskSearchErrorMsg);
procedure DiskSearchDisposeSortDone(AData: PSearchSortDoneMsg);
procedure DiskSearchPumpWindowMessages(AMainWindow: HWINDOW);
function DiskSearchIsActive: Boolean;

implementation

uses
  StrUtils, SafeLog;

const
  cIndexPrepareTimeoutMs = 0;
  cStopWaitTimeoutMs = 2000;
  { 与 UI_MainWindow 中搜索防抖定时器 ID 一致；索引等待泵消息时不得触发防抖搜索 }
  cMainSearchDebounceTimerId = 901;

type
  TDiskResultHandler = procedure(AData: PDiskSearchResult);
  TDiskErrorHandler = procedure(AData: PDiskSearchErrorMsg);

var
  GSearchThread: TThread;
  GSearchGeneration: Cardinal;
  GResultHandler: TDiskResultHandler;
  GErrorHandler: TDiskErrorHandler;

procedure DiskSearchDebug(const ASummary: string; const ADetail: string = '');
begin
  SafeLogRecord('调试', '搜索', ASummary, True, ADetail);
  OutputDebugString(PChar('[DiskSearch] ' + ASummary +
    IfThen(ADetail <> '', ' | ' + ADetail, '') + #0));
end;

function MapIndexErrorToSearchError(const AError: TEverythingIndexError): TDiskSearchError;
begin
  case AError of
    eieVolumeAccess:
      Result := dseIndexAccess;
    eieNoNtfsVolume, eieBuildFailed:
      Result := dseIndexMissing;
  else
    Result := dseQueryFailed;
  end;
end;

function PostSearchResult(AMainWindow: HWINDOW; AData: PDiskSearchResult): Boolean;
var
  hRealWnd: Windows.HWND;
begin
  Result := XC_GetObjectType(AMainWindow) = XC_WINDOW;
  if not Result then
  begin
    DiskSearchDebug('投递结果失败', '主窗口无效');
    Dispose(AData);
    Exit;
  end;
  Result := XC_PostMessage(AMainWindow, WM_QD_DISK_SEARCH, 0, LPARAM(AData));
  if Result then
    Exit;
  hRealWnd := XWnd_GetHWND(AMainWindow);
  if hRealWnd <> 0 then
    Result := PostMessageW(hRealWnd, WM_QD_DISK_SEARCH, 0, LPARAM(AData));
  if Result then
    Exit;
  DiskSearchDebug('投递结果失败', Format('命中数=%d', [Length(AData^.HitIndices)]));
  Dispose(AData);
end;

function PostSearchError(AMainWindow: HWINDOW; AData: PDiskSearchErrorMsg): Boolean;
var
  hRealWnd: Windows.HWND;
begin
  Result := XC_GetObjectType(AMainWindow) = XC_WINDOW;
  if not Result then
  begin
    DiskSearchDebug('投递错误失败', '主窗口无效');
    Dispose(AData);
    Exit;
  end;
  Result := XC_PostMessage(AMainWindow, WM_QD_DISK_SEARCH_ERROR, 0, LPARAM(AData));
  if Result then
    Exit;
  hRealWnd := XWnd_GetHWND(AMainWindow);
  if hRealWnd <> 0 then
    Result := PostMessageW(hRealWnd, WM_QD_DISK_SEARCH_ERROR, 0, LPARAM(AData));
  if not Result then
    Dispose(AData);
end;

type
  TDiskSearchThread = class(TThread)
  private
    FNeedle: string;
    FSortKind: TLibraryListSortKind;
    FSortAsc: Boolean;
    FGeneration: Cardinal;
    FMainWindow: HWINDOW;
  protected
    procedure Execute; override;
  public
    constructor Create(const ANeedle: string; const ASortKind: TLibraryListSortKind;
      const ASortAsc: Boolean; AGeneration: Cardinal; AMainWindow: HWINDOW);
  end;

constructor TDiskSearchThread.Create(const ANeedle: string; const ASortKind: TLibraryListSortKind;
  const ASortAsc: Boolean; AGeneration: Cardinal; AMainWindow: HWINDOW);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FNeedle := ANeedle;
  FSortKind := ASortKind;
  FSortAsc := ASortAsc;
  FGeneration := AGeneration;
  FMainWindow := AMainWindow;
end;

procedure TDiskSearchThread.Execute;
var
  hitIndices: TEverythingHitArray;
  totalCount: Cardinal;
  indexWaitStart, queryStartTick: Cardinal;
  searchTiming: TSearchTiming;
  resultMsg: PDiskSearchResult;
  errorMsg: PDiskSearchErrorMsg;

  procedure DispatchResult;
  begin
    if PostSearchResult(FMainWindow, resultMsg) then
      Exit;
    if Assigned(GResultHandler) then
      GResultHandler(resultMsg)
    else
      DiskSearchDisposeResult(resultMsg);
  end;

  procedure DispatchError;
  begin
    if PostSearchError(FMainWindow, errorMsg) then
      Exit;
    if Assigned(GErrorHandler) then
      GErrorHandler(errorMsg)
    else
      DiskSearchDisposeError(errorMsg);
  end;

begin
  try
    try
    if Terminated then
      Exit;
    indexWaitStart := GetTickCount;
    if not EverythingIndexWaitUntilReady(cIndexPrepareTimeoutMs,
      procedure
      begin
        DiskSearchPumpWindowMessages(FMainWindow);
      end) then
    begin
      New(errorMsg);
      errorMsg^.ErrorKind := MapIndexErrorToSearchError(EverythingIndexGetLastError);
      errorMsg^.Generation := FGeneration;
      errorMsg^.Needle := FNeedle;
      DiskSearchDebug('索引未就绪', '错误=' + IntToStr(Ord(EverythingIndexGetLastError)));
      DispatchError;
      Exit;
    end;
    queryStartTick := GetTickCount;
    if EverythingIndexSearch(FNeedle, FSortKind, FSortAsc,
      function: Boolean
      begin
        Result := Terminated or (not DiskSearchIsLatestGeneration(FGeneration));
      end, hitIndices, totalCount, searchTiming, False) then
    begin
      if Terminated then
        Exit;
      New(resultMsg);
      resultMsg^.Needle := FNeedle;
      resultMsg^.Generation := FGeneration;
      resultMsg^.TotalCount := totalCount;
      resultMsg^.IndexWaitMs := queryStartTick - indexWaitStart;
      resultMsg^.QueryElapsedMs := GetTickCount - queryStartTick;
      resultMsg^.SearchTiming := searchTiming;
      resultMsg^.HitIndices := hitIndices;
      DispatchResult;
      Exit;
    end;
    if Terminated or (not DiskSearchIsLatestGeneration(FGeneration)) then
    begin
      DiskSearchDebug('搜索已取消', Format('关键字=%s 代次=%d', [FNeedle, FGeneration]));
      Exit;
    end;
    New(errorMsg);
    errorMsg^.ErrorKind := dseQueryFailed;
    errorMsg^.Generation := FGeneration;
    errorMsg^.Needle := FNeedle;
    DispatchError;
    except
      on E: Exception do
        DiskSearchDebug('搜索线程异常', E.Message);
    end;
  finally
    if GSearchThread = Self then
      GSearchThread := nil;
  end;
end;

function DiskSearchPrepare(AMainWindow: HWINDOW; out AError: TDiskSearchError): Boolean;
begin
  AError := dseQueryFailed;
  if EverythingIndexIsReady then
    Exit(True);
  EverythingIndexStartBuild;
  if not EverythingIndexWaitUntilReady(cIndexPrepareTimeoutMs,
    procedure
    begin
      DiskSearchPumpWindowMessages(AMainWindow);
    end) then
  begin
    AError := MapIndexErrorToSearchError(EverythingIndexGetLastError);
    if AError = dseQueryFailed then
      AError := dseIndexMissing;
    Exit(False);
  end;
  Result := True;
end;

function DiskSearchCurrentGeneration: Cardinal;
begin
  Result := GSearchGeneration;
end;

function DiskSearchIsLatestGeneration(const AGeneration: Cardinal): Boolean;
begin
  Result := AGeneration = GSearchGeneration;
end;

procedure DiskSearchRequest(AMainWindow: HWINDOW; const ANeedle: string;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
begin
  if XC_GetObjectType(AMainWindow) <> XC_WINDOW then
    Exit;
  DiskSearchStop;
  Inc(GSearchGeneration);
  if not EverythingIndexIsReady then
    EverythingIndexStartBuild;
  GSearchThread := TDiskSearchThread.Create(ANeedle, ASortKind, ASortAsc, GSearchGeneration,
    AMainWindow);
  GSearchThread.Start;
end;

function DiskSearchIsActive: Boolean;
begin
  Result := GSearchThread <> nil;
end;

procedure DiskSearchStop;
var
  oldThread: TThread;
begin
  oldThread := GSearchThread;
  GSearchThread := nil;
  if oldThread = nil then
    Exit;
  oldThread.Terminate;
end;

procedure DiskSearchStopAndWait;
var
  oldThread: TThread;
  startTick: Cardinal;
begin
  oldThread := GSearchThread;
  GSearchThread := nil;
  if oldThread = nil then
    Exit;
  oldThread.Terminate;
  startTick := GetTickCount;
  while not oldThread.Finished do
  begin
    if GetTickCount - startTick >= cStopWaitTimeoutMs then
      Break;
    CheckSynchronize;
    Sleep(1);
  end;
end;

procedure DiskSearchSetHandlers(AOnResult, AOnError: Pointer);
begin
  GResultHandler := TDiskResultHandler(AOnResult);
  GErrorHandler := TDiskErrorHandler(AOnError);
end;

procedure DiskSearchDisposeResult(AData: PDiskSearchResult);
begin
  if AData = nil then
    Exit;
  SetLength(AData^.HitIndices, 0);
  Dispose(AData);
end;

procedure DiskSearchDisposeError(AData: PDiskSearchErrorMsg);
begin
  if AData <> nil then
    Dispose(AData);
end;

procedure DiskSearchDisposeSortDone(AData: PSearchSortDoneMsg);
begin
  if AData = nil then
    Exit;
  SetLength(AData^.HitIndices, 0);
  Dispose(AData);
end;

procedure DiskSearchPumpWindowMessages(AMainWindow: HWINDOW);
var
  hRealWnd: Windows.HWND;
  msg: TMsg;
begin
  if XC_GetObjectType(AMainWindow) <> XC_WINDOW then
    Exit;
  hRealWnd := XWnd_GetHWND(AMainWindow);
  if hRealWnd = 0 then
    Exit;
  while PeekMessageW(msg, hRealWnd, 0, 0, PM_REMOVE) do
  begin
    if (msg.message = WM_QD_DISK_SEARCH) or (msg.message = WM_QD_DISK_SEARCH_ERROR) or
      (msg.message = WM_QD_DISK_SEARCH_SORT_DONE) or (msg.message = WM_QD_INDEX_HIT_CHANGES) then
    begin
      PostMessageW(hRealWnd, msg.message, msg.wParam, msg.lParam);
      Continue;
    end;
    if (msg.message = WM_TIMER) and (UINT(msg.wParam) = cMainSearchDebounceTimerId) then
      Continue;
    TranslateMessage(msg);
    DispatchMessageW(msg);
  end;
end;

initialization

finalization
  DiskSearchStopAndWait;

end.
