unit NetHttpWorker;

interface

uses
  Windows, SysUtils, Classes, SyncObjs;

type
  TNetHttpRequestKind = (hkText, hkDownload);

  TNetHttpGetOptions = record
    UserAgent: string;
    ResolveMs: Integer;
    ConnectMs: Integer;
    SendMs: Integer;
    ReceiveMs: Integer;
  end;

  TNetHttpResponse = record
    Ok: Boolean;
    StatusCode: DWORD;
    Host: string;
    BodyText: string;
    SavedPath: string;
    BytesSaved: Int64;
    ErrorMessage: string;
  end;

  TNetHttpRequest = record
    Url: string;
    Kind: TNetHttpRequestKind;
    SaveToFile: string;
    Options: TNetHttpGetOptions;
    UserData: NativeInt;
  end;

  TNetHttpTask = class
  public
    Request: TNetHttpRequest;
    constructor Create(const ARequest: TNetHttpRequest);
  end;

  TNetHttpCompleteEvent = procedure(Sender: TObject; ATask: TNetHttpTask;
    const AResponse: TNetHttpResponse) of object;

  { 后台单线程顺序执行 HTTP；WinHTTP 异步 API + 可警报等待投递回调 }
  TNetHttpWorker = class(TThread)
  private
    FLogTag: string;
    FQueue: TList;
    FQueueLock: TCriticalSection;
    FWakeEvt: TEvent;
    FOnCompleted: TNetHttpCompleteEvent;
    FSliceMs: Cardinal;
    procedure WaitInterruptible(ATotalMs: Cardinal);
    function PopTask: TNetHttpTask;
    procedure DispatchTask(ATask: TNetHttpTask);
  protected
    procedure Execute; override;
  public
    constructor Create(const ALogTag: string = 'NetHttp');
    destructor Destroy; override;
    function Enqueue(const ARequest: TNetHttpRequest): TNetHttpTask;
    procedure Wake;
    class function DefaultOptions: TNetHttpGetOptions;
    class function ExecuteSync(const ARequest: TNetHttpRequest): TNetHttpResponse;
    property OnCompleted: TNetHttpCompleteEvent read FOnCompleted write FOnCompleted;
  end;

procedure NetHttpAbortAllPending;

implementation

uses
  WinHTTP2;

const
  cNoHdrLen = 0;
  cChunkSize = 8192;
  cDefaultUserAgent = 'QDesktop/1.0';
  ERROR_IO_PENDING = 997;
  cAbortPollMs = 100;

var
  GNetHttpAbortPending: Longint;

function NetHttpIsAbortPending: Boolean;
begin
  Result := GNetHttpAbortPending <> 0;
end;

procedure NetHttpAbortAllPending;
begin
  InterlockedExchange(GNetHttpAbortPending, 1);
end;

type
  TNetHttpAsyncStage = (nsIdle, nsActive, nsDone, nsFailed);

  TNetHttpAsyncCtx = class
  private
    FRequest: TNetHttpRequest;
    FResponse: TNetHttpResponse;
    FHost: string;
    FPath: string;
    FOpts: TNetHttpGetOptions;
    FLogTag: string;
    FStage: TNetHttpAsyncStage;
    FhSes: HINTERNET;
    FhConn: HINTERNET;
    FhReq: HINTERNET;
    FRawBody: AnsiString;
    FReadBuf: array[0..cChunkSize - 1] of AnsiChar;
    FFileStream: TFileStream;
    FCompleteEvt: TEvent;
    FDeadlineTick: Cardinal;
    procedure SetFailed(const AMsg: string);
    procedure SetSucceeded;
    procedure SignalComplete;
    procedure CloseHandles;
    procedure FinalizeBody;
    function IsTimedOut: Boolean;
    function CalcWaitMs: DWORD;
    procedure WaitUntilFinished;
    function WinHttpCallStarted(const AOk: BOOL): Boolean;
    procedure BeginReceiveResponse;
    procedure BeginQueryDataAvailable;
    procedure BeginReadData(ADwSize: DWORD);
    procedure HandleRequestError(lpvStatusInformation: Pointer);
    procedure HandleSendRequestComplete;
    procedure HandleHeadersAvailable;
    procedure HandleDataAvailable(lpvStatusInformation: Pointer);
    procedure HandleReadComplete(dwStatusInformationLength: DWORD);
  public
    constructor Create(const ARequest: TNetHttpRequest; const ALogTag: string);
    destructor Destroy; override;
    function StartRequest: Boolean;
    function RunUntilComplete: TNetHttpResponse;
    procedure HandleStatus(hInternet: HINTERNET; dwInternetStatus: DWORD;
      lpvStatusInformation: Pointer; dwStatusInformationLength: DWORD);
  end;

procedure NetHttpStatusCallback(hInternet: HINTERNET; dwContext: Pointer;
  dwInternetStatus: DWORD; lpvStatusInformation: Pointer;
  dwStatusInformationLength: DWORD); stdcall;
var
  ctx: TNetHttpAsyncCtx;
begin
  ctx := TNetHttpAsyncCtx(dwContext);
  if ctx <> nil then
    ctx.HandleStatus(hInternet, dwInternetStatus, lpvStatusInformation, dwStatusInformationLength);
end;

class function TNetHttpWorker.DefaultOptions: TNetHttpGetOptions;
begin
  Result.UserAgent := cDefaultUserAgent;
  Result.ResolveMs := 8000;
  Result.ConnectMs := 8000;
  Result.SendMs := 20000;
  Result.ReceiveMs := 30000;
end;

function SysErrText(ACode: DWORD): string;
begin
  Result := Trim(SysErrorMessage(ACode));
end;

function FormatWinHttpError(hInet: HINTERNET): string;
var
  errCode, extErr, extLen: DWORD;
  sysText: string;
begin
  errCode := GetLastError;
  Result := 'Win32=' + IntToStr(errCode);
  sysText := SysErrText(errCode);
  if sysText <> '' then
    Result := Result + ' (' + sysText + ')';
  if hInet <> nil then
  begin
    extErr := 0;
    extLen := SizeOf(extErr);
    if WinHttpQueryOption(hInet, WINHTTP_OPTION_EXTENDED_ERROR, extErr, extLen) then
      Result := Result + ', WinHttpExt=' + IntToStr(extErr);
  end;
end;

function FormatWinHttpErrorCode(AErrCode: DWORD; hInet: HINTERNET): string;
begin
  SetLastError(AErrCode);
  Result := FormatWinHttpError(hInet);
end;

procedure ApplySessionTls(hSesInet: HINTERNET);
var
  protocols: DWORD;
begin
  protocols := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3 or
    WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
  if not WinHttpSetOption(hSesInet, WINHTTP_OPTION_SECURE_PROTOCOLS, @protocols, SizeOf(protocols)) then
  begin
    protocols := WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
    WinHttpSetOption(hSesInet, WINHTTP_OPTION_SECURE_PROTOCOLS, @protocols, SizeOf(protocols));
  end;
end;

procedure ApplyRequestSecurity(hReqInet: HINTERNET);
var
  secFlags: DWORD;
begin
  secFlags := SECURITY_FLAG_IGNORE_REVOCATION or
    SECURITY_FLAG_IGNORE_UNKNOWN_CA or
    SECURITY_FLAG_IGNORE_CERT_DATE_INVALID or
    SECURITY_FLAG_IGNORE_CERT_CN_INVALID or
    SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
  WinHttpSetOption(hReqInet, WINHTTP_OPTION_SECURITY_FLAGS, @secFlags, SizeOf(secFlags));
end;

function ParseHttpsUrl(const AUrl: string; out AHost, APath: string): Boolean;
var
  rest: string;
  slashPos, colonPos: Integer;
begin
  Result := False;
  AHost := '';
  APath := '/';
  rest := Trim(AUrl);
  if not SameText(Copy(rest, 1, 8), 'https://') then
    Exit;
  rest := Copy(rest, 9, MaxInt);
  slashPos := Pos('/', rest);
  if slashPos > 0 then
  begin
    AHost := Copy(rest, 1, slashPos - 1);
    APath := Copy(rest, slashPos, MaxInt);
  end
  else
    AHost := rest;
  colonPos := Pos(':', AHost);
  if colonPos > 0 then
    AHost := Copy(AHost, 1, colonPos - 1);
  Result := AHost <> '';
end;

function QueryStatusCode(hReqInet: HINTERNET): DWORD;
var
  statusCode, bufLen: DWORD;
begin
  statusCode := 0;
  bufLen := SizeOf(statusCode);
  if WinHttpQueryHeaders(hReqInet, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_HEADER_NAME_BY_INDEX, @statusCode, bufLen, WINHTTP_NO_HEADER_INDEX) then
    Result := statusCode
  else
    Result := 0;
end;

{ TNetHttpAsyncCtx }

constructor TNetHttpAsyncCtx.Create(const ARequest: TNetHttpRequest; const ALogTag: string);
begin
  inherited Create;
  FRequest := ARequest;
  FLogTag := ALogTag;
  FStage := nsIdle;
  FhSes := nil;
  FhConn := nil;
  FhReq := nil;
  FRawBody := '';
  FFileStream := nil;
  FCompleteEvt := TEvent.Create(nil, True, False, '');
  FillChar(FResponse, SizeOf(FResponse), 0);
  FOpts := ARequest.Options;
  if FOpts.UserAgent = '' then
    FOpts := TNetHttpWorker.DefaultOptions
  else
  begin
    if FOpts.ResolveMs <= 0 then FOpts.ResolveMs := TNetHttpWorker.DefaultOptions.ResolveMs;
    if FOpts.ConnectMs <= 0 then FOpts.ConnectMs := TNetHttpWorker.DefaultOptions.ConnectMs;
    if FOpts.SendMs <= 0 then FOpts.SendMs := TNetHttpWorker.DefaultOptions.SendMs;
    if FOpts.ReceiveMs <= 0 then FOpts.ReceiveMs := TNetHttpWorker.DefaultOptions.ReceiveMs;
  end;
  FDeadlineTick := GetTickCount + Cardinal(FOpts.ResolveMs + FOpts.ConnectMs +
    FOpts.SendMs + FOpts.ReceiveMs + 5000);
end;

destructor TNetHttpAsyncCtx.Destroy;
begin
  CloseHandles;
  FCompleteEvt.Free;
  inherited;
end;

function TNetHttpAsyncCtx.IsTimedOut: Boolean;
var
  nowTick: Cardinal;
begin
  nowTick := GetTickCount;
  if nowTick >= FDeadlineTick then
    Result := True
  else if FDeadlineTick - nowTick > $7FFFFFFF then
    Result := True
  else
    Result := False;
end;

function TNetHttpAsyncCtx.CalcWaitMs: DWORD;
var
  nowTick: Cardinal;
begin
  nowTick := GetTickCount;
  if nowTick >= FDeadlineTick then
    Result := 0
  else
    Result := FDeadlineTick - nowTick;
end;

procedure TNetHttpAsyncCtx.SignalComplete;
begin
  FCompleteEvt.SetEvent;
end;

procedure TNetHttpAsyncCtx.WaitUntilFinished;
var
  wr: DWORD;
  waitMs: DWORD;
begin
  while (FStage <> nsDone) and (FStage <> nsFailed) do
  begin
    if NetHttpIsAbortPending then
    begin
      SetFailed('Aborted');
      Break;
    end;
    waitMs := CalcWaitMs;
    if waitMs = 0 then
    begin
      SetFailed('Timeout');
      Break;
    end;
    if NetHttpIsAbortPending and (waitMs > cAbortPollMs) then
      waitMs := cAbortPollMs;
    { 可警报等待：WinHTTP 回调返回 WAIT_IO_COMPLETION；完成时 SetEvent 返回 WAIT_OBJECT_0 }
    wr := WaitForSingleObjectEx(FCompleteEvt.Handle, waitMs, True);
    if wr = WAIT_OBJECT_0 then
      Break
    else if wr = WAIT_TIMEOUT then
    begin
      SetFailed('Timeout');
      Break;
    end;
  end;
end;

procedure TNetHttpAsyncCtx.SetFailed(const AMsg: string);
begin
  if FStage = nsFailed then
    Exit;
  FStage := nsFailed;
  FResponse.Ok := False;
  if FResponse.ErrorMessage = '' then
    FResponse.ErrorMessage := AMsg;
  SignalComplete;
end;

procedure TNetHttpAsyncCtx.SetSucceeded;
begin
  if FStage = nsDone then
    Exit;
  FStage := nsDone;
  FResponse.Ok := True;
  SignalComplete;
end;

procedure TNetHttpAsyncCtx.CloseHandles;
begin
  if FFileStream <> nil then
  begin
    FFileStream.Free;
    FFileStream := nil;
  end;
  if FhReq <> nil then
  begin
    WinHttpCloseHandle(FhReq);
    FhReq := nil;
  end;
  if FhConn <> nil then
  begin
    WinHttpCloseHandle(FhConn);
    FhConn := nil;
  end;
  if FhSes <> nil then
  begin
    WinHttpCloseHandle(FhSes);
    FhSes := nil;
  end;
end;

procedure TNetHttpAsyncCtx.FinalizeBody;
begin
  if FRequest.Kind = hkText then
  begin
    if FRawBody <> '' then
    begin
      try
        FResponse.BodyText := Trim(UTF8ToString(FRawBody));
      except
        FResponse.BodyText := Trim(string(FRawBody));
      end;
    end;
  end;
end;

function TNetHttpAsyncCtx.WinHttpCallStarted(const AOk: BOOL): Boolean;
begin
  Result := AOk or (GetLastError = ERROR_IO_PENDING);
end;

procedure TNetHttpAsyncCtx.BeginReceiveResponse;
begin
  if FStage <> nsActive then
    Exit;
  if IsTimedOut then
  begin
    SetFailed('Timeout ReceiveResponse');
    Exit;
  end;
  if not WinHttpCallStarted(WinHttpReceiveResponse(FhReq, nil)) then
    SetFailed('ReceiveResponse ' + FormatWinHttpError(FhReq));
end;

procedure TNetHttpAsyncCtx.BeginQueryDataAvailable;
begin
  if FStage <> nsActive then
    Exit;
  if IsTimedOut then
  begin
    SetFailed('Timeout QueryDataAvailable');
    Exit;
  end;
  if not WinHttpCallStarted(WinHttpQueryDataAvailable(FhReq, nil)) then
    SetFailed('QueryDataAvailable ' + FormatWinHttpError(FhReq));
end;

procedure TNetHttpAsyncCtx.BeginReadData(ADwSize: DWORD);
var
  toRead: DWORD;
begin
  if FStage <> nsActive then
    Exit;
  if IsTimedOut then
  begin
    SetFailed('Timeout ReadData');
    Exit;
  end;
  if ADwSize = 0 then
  begin
    SetSucceeded;
    Exit;
  end;
  toRead := ADwSize;
  if toRead > cChunkSize then
    toRead := cChunkSize;
  if not WinHttpCallStarted(WinHttpReadData(FhReq, FReadBuf[0], toRead, nil)) then
    SetFailed('ReadData ' + FormatWinHttpError(FhReq));
end;

procedure TNetHttpAsyncCtx.HandleRequestError(lpvStatusInformation: Pointer);
var
  asyncRes: PWinHttpAsyncResult;
  apiName: string;
begin
  if FStage <> nsActive then
    Exit;
  if lpvStatusInformation = nil then
  begin
    SetFailed('REQUEST_ERROR');
    Exit;
  end;
  asyncRes := PWinHttpAsyncResult(lpvStatusInformation);
  case asyncRes.dwResult of
    API_RECEIVE_RESPONSE: apiName := 'ReceiveResponse';
    API_QUERY_DATA_AVAILABLE: apiName := 'QueryDataAvailable';
    API_READ_DATA: apiName := 'ReadData';
    API_WRITE_DATA: apiName := 'WriteData';
    API_SEND_REQUEST: apiName := 'SendRequest';
  else
    apiName := 'API#' + IntToStr(asyncRes.dwResult);
  end;
  SetFailed(apiName + ' ' + FormatWinHttpErrorCode(asyncRes.dwError, FhReq));
end;

procedure TNetHttpAsyncCtx.HandleSendRequestComplete;
begin
  if FStage <> nsActive then
    Exit;
  BeginReceiveResponse;
end;

procedure TNetHttpAsyncCtx.HandleHeadersAvailable;
begin
  if FStage <> nsActive then
    Exit;
  FResponse.StatusCode := QueryStatusCode(FhReq);
  if FResponse.StatusCode <> 200 then
  begin
    FResponse.ErrorMessage := 'HTTP ' + IntToStr(FResponse.StatusCode);
    FResponse.Ok := False;
  end;
  if FRequest.Kind = hkDownload then
  begin
    if FRequest.SaveToFile = '' then
    begin
      SetFailed('SaveToFile empty');
      Exit;
    end;
    if FResponse.StatusCode = 200 then
    begin
      ForceDirectories(ExtractFilePath(FRequest.SaveToFile));
      FFileStream := TFileStream.Create(FRequest.SaveToFile, fmCreate);
      FResponse.SavedPath := FRequest.SaveToFile;
    end;
  end;
  BeginQueryDataAvailable;
end;

procedure TNetHttpAsyncCtx.HandleDataAvailable(lpvStatusInformation: Pointer);
var
  avail: DWORD;
begin
  if FStage <> nsActive then
    Exit;
  if lpvStatusInformation = nil then
  begin
    SetFailed('DATA_AVAILABLE null');
    Exit;
  end;
  avail := PDWORD(lpvStatusInformation)^;
  BeginReadData(avail);
end;

procedure TNetHttpAsyncCtx.HandleReadComplete(dwStatusInformationLength: DWORD);
var
  chunk: AnsiString;
begin
  if FStage <> nsActive then
    Exit;
  if dwStatusInformationLength = 0 then
  begin
    if FResponse.StatusCode = 200 then
      SetSucceeded
    else
    begin
      FinalizeBody;
      SetFailed(FResponse.ErrorMessage);
    end;
    Exit;
  end;
  SetLength(chunk, dwStatusInformationLength);
  Move(FReadBuf[0], chunk[1], dwStatusInformationLength);
  if FFileStream <> nil then
  begin
    FFileStream.WriteBuffer(FReadBuf[0], dwStatusInformationLength);
    Inc(FResponse.BytesSaved, dwStatusInformationLength);
  end
  else
    FRawBody := FRawBody + chunk;
  if FResponse.StatusCode = 200 then
    BeginQueryDataAvailable
  else
  begin
    FinalizeBody;
    SetFailed(FResponse.ErrorMessage);
  end;
end;

procedure TNetHttpAsyncCtx.HandleStatus(hInternet: HINTERNET; dwInternetStatus: DWORD;
  lpvStatusInformation: Pointer; dwStatusInformationLength: DWORD);
begin
  if (FStage <> nsActive) or (hInternet <> FhReq) then
    Exit;
  case dwInternetStatus of
    WINHTTP_CALLBACK_STATUS_REQUEST_ERROR:
      HandleRequestError(lpvStatusInformation);
    WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
      HandleSendRequestComplete;
    WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE:
      HandleHeadersAvailable;
    WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE:
      HandleDataAvailable(lpvStatusInformation);
    WINHTTP_CALLBACK_STATUS_READ_COMPLETE:
      HandleReadComplete(dwStatusInformationLength);
  end;
end;

function TNetHttpAsyncCtx.StartRequest: Boolean;
var
  ua: string;
  ctxPtr: Pointer;
  openFlags: DWORD;
begin
  Result := False;
  FResponse.Ok := False;
  FResponse.StatusCode := 0;
  FResponse.BodyText := '';
  FResponse.SavedPath := '';
  FResponse.BytesSaved := 0;
  FResponse.ErrorMessage := '';
  if Trim(FRequest.Url) = '' then
  begin
    FResponse.ErrorMessage := 'URL empty';
    Exit;
  end;
  if not ParseHttpsUrl(FRequest.Url, FHost, FPath) then
  begin
    FResponse.ErrorMessage := 'Only https URL supported';
    Exit;
  end;
  FResponse.Host := FHost;
  ua := FOpts.UserAgent;
  FhSes := WinHttpOpen(PWideChar(ua), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC);
  if FhSes = nil then
  begin
    FResponse.ErrorMessage := 'WinHttpOpen ' + FormatWinHttpError(nil);
    Exit;
  end;
  WinHttpSetStatusCallback(FhSes, @NetHttpStatusCallback,
    WINHTTP_CALLBACK_FLAG_ALL_COMPLETIONS, 0);
  WinHttpSetTimeouts(FhSes, FOpts.ResolveMs, FOpts.ConnectMs, FOpts.SendMs, FOpts.ReceiveMs);
  ApplySessionTls(FhSes);
  FhConn := WinHttpConnect(FhSes, PWideChar(FHost), INTERNET_DEFAULT_HTTPS_PORT, 0);
  if FhConn = nil then
  begin
    FResponse.ErrorMessage := FHost + ' Connect ' + FormatWinHttpError(FhSes);
    CloseHandles;
    Exit;
  end;
  openFlags := WINHTTP_FLAG_SECURE;
  FhReq := WinHttpOpenRequest(FhConn, 'GET', PWideChar(FPath), nil,
    WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, openFlags);
  if FhReq = nil then
  begin
    FResponse.ErrorMessage := FHost + ' OpenRequest ' + FormatWinHttpError(FhConn);
    CloseHandles;
    Exit;
  end;
  ctxPtr := Self;
  WinHttpSetOption(FhReq, WINHTTP_OPTION_CONTEXT_VALUE, @ctxPtr, SizeOf(ctxPtr));
  ApplyRequestSecurity(FhReq);
  FStage := nsActive;
  FCompleteEvt.ResetEvent;
  if not WinHttpCallStarted(WinHttpSendRequest(FhReq, WINHTTP_NO_ADDITIONAL_HEADERS, cNoHdrLen,
    WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) then
  begin
    SetFailed('SendRequest ' + FormatWinHttpError(FhReq));
    CloseHandles;
    Exit;
  end;
  Result := True;
end;

function TNetHttpAsyncCtx.RunUntilComplete: TNetHttpResponse;
begin
  Result := FResponse;
  if not StartRequest then
    Exit;
  WaitUntilFinished;
  CloseHandles;
  if FStage = nsDone then
  begin
    FinalizeBody;
    if FResponse.StatusCode = 200 then
      FResponse.Ok := True;
  end;
  Result := FResponse;
end;

class function TNetHttpWorker.ExecuteSync(const ARequest: TNetHttpRequest): TNetHttpResponse;
var
  ctx: TNetHttpAsyncCtx;
begin
  ctx := TNetHttpAsyncCtx.Create(ARequest, 'NetHttp');
  try
    Result := ctx.RunUntilComplete;
  finally
    ctx.Free;
  end;
end;

{ TNetHttpTask }

constructor TNetHttpTask.Create(const ARequest: TNetHttpRequest);
begin
  inherited Create;
  Request := ARequest;
end;

{ TNetHttpWorker }

constructor TNetHttpWorker.Create(const ALogTag: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLogTag := ALogTag;
  FQueue := TList.Create;
  FQueueLock := TCriticalSection.Create;
  FWakeEvt := TEvent.Create(nil, False, False, '');
  FOnCompleted := nil;
  FSliceMs := 500;
end;

destructor TNetHttpWorker.Destroy;
var
  i: Integer;
begin
  Terminate;
  Wake;
  WaitFor;
  FQueueLock.Enter;
  try
    for i := 0 to FQueue.Count - 1 do
      TNetHttpTask(FQueue[i]).Free;
    FQueue.Clear;
  finally
    FQueueLock.Leave;
  end;
  FQueue.Free;
  FQueueLock.Free;
  FWakeEvt.Free;
  inherited;
end;

procedure TNetHttpWorker.Wake;
begin
  FWakeEvt.SetEvent;
end;

function TNetHttpWorker.Enqueue(const ARequest: TNetHttpRequest): TNetHttpTask;
begin
  Result := TNetHttpTask.Create(ARequest);
  FQueueLock.Enter;
  try
    FQueue.Add(Result);
  finally
    FQueueLock.Leave;
  end;
  Wake;
end;

function TNetHttpWorker.PopTask: TNetHttpTask;
begin
  Result := nil;
  FQueueLock.Enter;
  try
    if FQueue.Count > 0 then
    begin
      Result := TNetHttpTask(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    FQueueLock.Leave;
  end;
end;

procedure TNetHttpWorker.WaitInterruptible(ATotalMs: Cardinal);
var
  remaining, slice, wr: DWORD;
begin
  remaining := ATotalMs;
  while (remaining > 0) and (not Terminated) do
  begin
    if remaining > FSliceMs then
      slice := FSliceMs
    else
      slice := remaining;
    wr := WaitForSingleObjectEx(FWakeEvt.Handle, slice, True);
    if (wr = WAIT_OBJECT_0) or Terminated then
      Exit;
    if remaining >= slice then
      Dec(remaining, slice)
    else
      remaining := 0;
  end;
end;

procedure TNetHttpWorker.DispatchTask(ATask: TNetHttpTask);
var
  resp: TNetHttpResponse;
begin
  if ATask = nil then
    Exit;
  try
    resp := ExecuteSync(ATask.Request);
    if Assigned(FOnCompleted) then
      FOnCompleted(Self, ATask, resp);
  except
    on E: Exception do
    begin
      FillChar(resp, SizeOf(resp), 0);
      resp.ErrorMessage := E.ClassName + ': ' + E.Message;
      if Assigned(FOnCompleted) then
        FOnCompleted(Self, ATask, resp);
    end;
  end;
end;

procedure TNetHttpWorker.Execute;
var
  task: TNetHttpTask;
begin
  while not Terminated do
  begin
    task := PopTask;
    if task <> nil then
    begin
      try
        DispatchTask(task);
      finally
        task.Free;
      end;
      Continue;
    end;
    WaitInterruptible(MaxInt);
  end;
end;

end.
