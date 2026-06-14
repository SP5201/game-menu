unit NetHttpWorker;

interface

uses
  Windows, SysUtils;

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
    PostBody: AnsiString;
    PostContentType: string;
    Options: TNetHttpGetOptions;
    UserData: NativeInt;
  end;

function NetHttpDefaultOptions: TNetHttpGetOptions;
function NetHttpExecuteSync(const ARequest: TNetHttpRequest): TNetHttpResponse;
procedure NetHttpAbortAllPending;
function NetHttpIsAbortPending: Boolean;

implementation

uses
  Classes, libcurl, AppConfig;

const
  cHttpsResolvePort = 443;
  cDeadlineSlackMs = 5000;

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

function NetHttpDefaultOptions: TNetHttpGetOptions;
begin
  Result.UserAgent := TAppConfig.GetUserAgent;
  Result.ResolveMs := 8000;
  Result.ConnectMs := 8000;
  Result.SendMs := 20000;
  Result.ReceiveMs := 30000;
end;

function NetHttpMergeOptions(const AOptions: TNetHttpGetOptions): TNetHttpGetOptions;
var
  defs: TNetHttpGetOptions;
begin
  defs := NetHttpDefaultOptions;
  Result := AOptions;
  if Result.UserAgent = '' then
    Result.UserAgent := defs.UserAgent;
  if Result.ResolveMs <= 0 then
    Result.ResolveMs := defs.ResolveMs;
  if Result.ConnectMs <= 0 then
    Result.ConnectMs := defs.ConnectMs;
  if Result.SendMs <= 0 then
    Result.SendMs := defs.SendMs;
  if Result.ReceiveMs <= 0 then
    Result.ReceiveMs := defs.ReceiveMs;
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

function ExtractCharsetFromContentType(const AContentType: string): string;
var
  lower, part: string;
  p, semi: Integer;
begin
  Result := '';
  lower := LowerCase(Trim(AContentType));
  p := Pos('charset=', lower);
  if p = 0 then
    Exit;
  part := Trim(Copy(AContentType, p + 8, MaxInt));
  semi := Pos(';', part);
  if semi > 0 then
    part := Copy(part, 1, semi - 1);
  part := Trim(part);
  if (Length(part) >= 2) and (part[1] = '"') and (part[Length(part)] = '"') then
    part := Copy(part, 2, Length(part) - 2);
  Result := Trim(part);
end;

function CharsetToCodePage(const ACharset: string): UINT;
var
  cs: string;
begin
  cs := UpperCase(Trim(ACharset));
  if (cs = 'UTF-8') or (cs = 'UTF8') then
    Exit(CP_UTF8);
  if (cs = 'GBK') or (cs = 'GB2312') or (cs = 'GB18030') or (cs = 'CP936') then
    Exit(936);
  Result := 0;
end;

function AnsiBytesToString(const ABytes: AnsiString; ACodePage: UINT): string;
var
  wlen: Integer;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;
  wlen := MultiByteToWideChar(ACodePage, 0, PAnsiChar(ABytes), Length(ABytes), nil, 0);
  if wlen <= 0 then
    Exit;
  SetLength(Result, wlen);
  MultiByteToWideChar(ACodePage, 0, PAnsiChar(ABytes), Length(ABytes), PWideChar(Result), wlen);
end;

function DecodeHttpTextBody(const ABytes: AnsiString; const AContentType: string): string;
const
  MB_ERR_INVALID_CHARS = $00000008;
var
  cp, wlen: UINT;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;
  cp := CharsetToCodePage(ExtractCharsetFromContentType(AContentType));
  if cp <> 0 then
    Exit(AnsiBytesToString(ABytes, cp));
  if (Length(ABytes) >= 3) and (Byte(ABytes[1]) = $EF) and (Byte(ABytes[2]) = $BB) and
    (Byte(ABytes[3]) = $BF) then
    Exit(AnsiBytesToString(Copy(ABytes, 4, MaxInt), CP_UTF8));
  wlen := MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, PAnsiChar(ABytes),
    Length(ABytes), nil, 0);
  if wlen > 0 then
    Exit(AnsiBytesToString(ABytes, CP_UTF8));
  Result := AnsiBytesToString(ABytes, CP_ACP);
end;

function LooksLikeIpAddress(const AValue: string): Boolean;
var
  i: Integer;
  ch: Char;
begin
  Result := False;
  if Trim(AValue) = '' then
    Exit;
  for i := 1 to Length(AValue) do
  begin
    ch := AValue[i];
    if not CharInSet(ch, ['0'..'9', '.', ':', 'a'..'f', 'A'..'F']) then
      Exit;
  end;
  Result := True;
end;

function ParseHostsResolveLine(const ALine: string; out AHost, AIp: string): Boolean;
var
  line, left, right: string;
  eqPos, spPos: Integer;
begin
  Result := False;
  AHost := '';
  AIp := '';
  line := Trim(ALine);
  if (line = '') or (line[1] = '#') then
    Exit;
  eqPos := Pos('=', line);
  if eqPos > 0 then
  begin
    left := Trim(Copy(line, 1, eqPos - 1));
    right := Trim(Copy(line, eqPos + 1, MaxInt));
    if (left <> '') and (right <> '') then
    begin
      if LooksLikeIpAddress(left) then
      begin
        AIp := left;
        AHost := right;
      end
      else
      begin
        AHost := left;
        AIp := right;
      end;
      Result := (AHost <> '') and (AIp <> '');
      Exit;
    end;
  end;
  spPos := Pos(' ', line);
  if spPos = 0 then
    spPos := Pos(#9, line);
  if spPos <= 0 then
    Exit;
  left := Trim(Copy(line, 1, spPos - 1));
  right := Trim(Copy(line, spPos + 1, MaxInt));
  if (left = '') or (right = '') then
    Exit;
  if LooksLikeIpAddress(left) then
  begin
    AIp := left;
    AHost := right;
  end
  else
  begin
    AHost := left;
    AIp := right;
  end;
  Result := (AHost <> '') and (AIp <> '');
end;

function BuildHostsResolveSlist(const AText: string): PCurlSlist;
var
  lines: TStringList;
  i: Integer;
  host, ip, entry: string;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  lines := TStringList.Create;
  try
    lines.Text := AText;
    for i := 0 to lines.Count - 1 do
    begin
      if not ParseHostsResolveLine(lines[i], host, ip) then
        Continue;
      entry := host + ':' + IntToStr(cHttpsResolvePort) + ':' + ip;
      Result := curl_slist_append(Result, PAnsiChar(AnsiString(UTF8Encode(entry))));
    end;
  finally
    lines.Free;
  end;
end;

function FormatCurlError(ACode: TCURLcode): string;
var
  msg: PAnsiChar;
begin
  msg := curl_easy_strerror(ACode);
  if msg <> nil then
    Result := string(AnsiString(msg))
  else
    Result := 'CURLE_' + IntToStr(ACode);
end;

type
  TNetHttpCurlCtx = class
  private
    FRequest: TNetHttpRequest;
    FResponse: TNetHttpResponse;
    FOpts: TNetHttpGetOptions;
    FContentType: string;
    FRawBody: AnsiString;
    FCurl: PCURL;
    FUrlAnsi: AnsiString;
    FUserAgentAnsi: AnsiString;
    FProxyAnsi: AnsiString;
    FResolveSlist: PCurlSlist;
    FHeaderSlist: PCurlSlist;
    function ApplyOptions: TCURLcode;
    function OnWrite(AData: PAnsiChar; ASize: NativeUInt): NativeUInt;
    procedure ReadResponseInfo;
    procedure FinalizeBody;
    procedure CloseResources;
  public
    constructor Create(const ARequest: TNetHttpRequest);
    destructor Destroy; override;
    function Execute: TNetHttpResponse;
  end;

function NetHttpCurlWriteCallback(AData: PAnsiChar; ASize, ACount: NativeUInt;
  AUserData: Pointer): NativeUInt; cdecl;
var
  ctx: TNetHttpCurlCtx;
  total: NativeUInt;
begin
  ctx := TNetHttpCurlCtx(AUserData);
  if ctx = nil then
    Exit(0);
  total := ASize * ACount;
  Result := ctx.OnWrite(AData, total);
end;

function NetHttpCurlXferInfoCallback(AClientp: Pointer; ADlTotal, ADlNow, AUlTotal,
  AUlNow: Int64): Integer; cdecl;
var
  ctx: TNetHttpCurlCtx;
begin
  ctx := TNetHttpCurlCtx(AClientp);
  if (ctx = nil) or NetHttpIsAbortPending then
    Exit(1);
  Result := 0;
end;

{ TNetHttpCurlCtx }

constructor TNetHttpCurlCtx.Create(const ARequest: TNetHttpRequest);
begin
  inherited Create;
  FRequest := ARequest;
  FOpts := NetHttpMergeOptions(ARequest.Options);
  FCurl := nil;
  FResolveSlist := nil;
  FHeaderSlist := nil;
  FRawBody := '';
  FContentType := '';
  FillChar(FResponse, SizeOf(FResponse), 0);
end;

destructor TNetHttpCurlCtx.Destroy;
begin
  CloseResources;
  inherited;
end;

procedure TNetHttpCurlCtx.CloseResources;
begin
  if FHeaderSlist <> nil then
  begin
    curl_slist_free_all(FHeaderSlist);
    FHeaderSlist := nil;
  end;
  if FResolveSlist <> nil then
  begin
    curl_slist_free_all(FResolveSlist);
    FResolveSlist := nil;
  end;
  if FCurl <> nil then
  begin
    curl_easy_cleanup(FCurl);
    FCurl := nil;
  end;
end;

function TNetHttpCurlCtx.OnWrite(AData: PAnsiChar; ASize: NativeUInt): NativeUInt;
var
  chunk: AnsiString;
begin
  if NetHttpIsAbortPending then
    Exit(0);
  if ASize = 0 then
    Exit(0);
  SetLength(chunk, ASize);
  Move(AData^, chunk[1], ASize);
  FRawBody := FRawBody + chunk;
  Result := ASize;
end;

function TNetHttpCurlCtx.ApplyOptions: TCURLcode;
var
  totalMs: LongInt;
  contentType: AnsiString;
  headerLine: AnsiString;
begin
  totalMs := FOpts.ResolveMs + FOpts.ConnectMs + FOpts.SendMs + FOpts.ReceiveMs +
    cDeadlineSlackMs;
  Result := CURLE_OK;
  if Result = CURLE_OK then
    Result := curl_easy_setopt_str(FCurl, CURLOPT_URL, PAnsiChar(FUrlAnsi));
  if Result = CURLE_OK then
  begin
    if FRequest.PostBody <> '' then
    begin
      Result := curl_easy_setopt_long(FCurl, CURLOPT_POST, 1);
      if Result = CURLE_OK then
        Result := curl_easy_setopt_str(FCurl, CURLOPT_POSTFIELDS, PAnsiChar(FRequest.PostBody));
      if Result = CURLE_OK then
      begin
        contentType := AnsiString(UTF8Encode(FRequest.PostContentType));
        if contentType = '' then
          contentType := 'application/json';
        headerLine := 'Content-Type: ' + contentType;
        FHeaderSlist := curl_slist_append(FHeaderSlist, PAnsiChar(headerLine));
        FHeaderSlist := curl_slist_append(FHeaderSlist, 'Accept: application/json');
        if FHeaderSlist <> nil then
          Result := curl_easy_setopt_ptr(FCurl, CURLOPT_HTTPHEADER, FHeaderSlist);
      end;
    end
    else
      Result := curl_easy_setopt_long(FCurl, CURLOPT_HTTPGET, 1);
  end;
  if Result = CURLE_OK then
    Result := curl_easy_setopt_str(FCurl, CURLOPT_USERAGENT, PAnsiChar(FUserAgentAnsi));
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_TIMEOUT_MS, totalMs);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_CONNECTTIMEOUT_MS, FOpts.ConnectMs);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_FOLLOWLOCATION, 0);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_NOSIGNAL, 1);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_SSL_VERIFYPEER, 0);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_SSL_VERIFYHOST, 0);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_cb(FCurl, CURLOPT_WRITEFUNCTION,
      @NetHttpCurlWriteCallback);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_ptr(FCurl, CURLOPT_WRITEDATA, Self);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_long(FCurl, CURLOPT_NOPROGRESS, 0);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_cb(FCurl, CURLOPT_XFERINFOFUNCTION,
      @NetHttpCurlXferInfoCallback);
  if Result = CURLE_OK then
    Result := curl_easy_setopt_ptr(FCurl, CURLOPT_XFERINFODATA, Self);
  if Result = CURLE_OK then
  begin
    FProxyAnsi := TAppConfig.BuildCurlProxyUrl;
    if FProxyAnsi <> '' then
      Result := curl_easy_setopt_str(FCurl, CURLOPT_PROXY, PAnsiChar(FProxyAnsi));
  end;
  if Result = CURLE_OK then
  begin
    FResolveSlist := BuildHostsResolveSlist(TAppConfig.GetHostsResolve);
    if FResolveSlist <> nil then
      Result := curl_easy_setopt_ptr(FCurl, CURLOPT_RESOLVE, FResolveSlist);
  end;
end;

procedure TNetHttpCurlCtx.ReadResponseInfo;
var
  statusCode: LongInt;
  contentType: PAnsiChar;
begin
  statusCode := 0;
  if curl_easy_getinfo_long(FCurl, CURLINFO_RESPONSE_CODE, statusCode) = CURLE_OK then
    FResponse.StatusCode := statusCode;
  contentType := nil;
  if curl_easy_getinfo_str(FCurl, CURLINFO_CONTENT_TYPE, contentType) = CURLE_OK then
  begin
    if contentType <> nil then
      FContentType := string(AnsiString(contentType));
  end;
end;

procedure TNetHttpCurlCtx.FinalizeBody;
var
  fs: TFileStream;
begin
  if FRequest.Kind = hkText then
  begin
    if FRawBody <> '' then
      FResponse.BodyText := Trim(DecodeHttpTextBody(FRawBody, FContentType));
    Exit;
  end;
  if (FRequest.Kind = hkDownload) and FResponse.Ok and (FRawBody <> '') then
  begin
    ForceDirectories(ExtractFilePath(FRequest.SaveToFile));
    fs := TFileStream.Create(FRequest.SaveToFile, fmCreate);
    try
      if Length(FRawBody) > 0 then
        fs.WriteBuffer(FRawBody[1], Length(FRawBody));
      FResponse.BytesSaved := Length(FRawBody);
      FResponse.SavedPath := FRequest.SaveToFile;
    finally
      fs.Free;
    end;
  end;
end;

function TNetHttpCurlCtx.Execute: TNetHttpResponse;
var
  host, path: string;
  performRes: TCURLcode;
begin
  Result := FResponse;
  FResponse.Ok := False;
  FResponse.StatusCode := 0;
  FResponse.BodyText := '';
  FResponse.SavedPath := '';
  FResponse.BytesSaved := 0;
  FResponse.ErrorMessage := '';

  if NetHttpIsAbortPending then
  begin
    FResponse.ErrorMessage := 'Aborted';
    Exit(FResponse);
  end;
  if Trim(FRequest.Url) = '' then
  begin
    FResponse.ErrorMessage := 'URL empty';
    Exit(FResponse);
  end;
  if not ParseHttpsUrl(FRequest.Url, host, path) then
  begin
    FResponse.ErrorMessage := 'Only https URL supported';
    Exit(FResponse);
  end;
  FResponse.Host := host;
  if FRequest.Kind = hkDownload then
  begin
    if FRequest.SaveToFile = '' then
    begin
      FResponse.ErrorMessage := 'SaveToFile empty';
      Exit(FResponse);
    end;
  end;

  FUrlAnsi := CurlAnsiUrl(FRequest.Url);
  FUserAgentAnsi := AnsiString(UTF8Encode(FOpts.UserAgent));
  FCurl := curl_easy_init;
  if FCurl = nil then
  begin
    FResponse.ErrorMessage := 'curl_easy_init failed';
    CloseResources;
    Exit(FResponse);
  end;

  performRes := ApplyOptions;
  if performRes <> CURLE_OK then
  begin
    FResponse.ErrorMessage := 'curl_setopt ' + FormatCurlError(performRes);
    CloseResources;
    Exit(FResponse);
  end;

  performRes := curl_easy_perform(FCurl);
  ReadResponseInfo;

  if NetHttpIsAbortPending then
    FResponse.ErrorMessage := 'Aborted'
  else if performRes = CURLE_OPERATION_TIMEDOUT then
    FResponse.ErrorMessage := 'Timeout'
  else if performRes = CURLE_ABORTED_BY_CALLBACK then
    FResponse.ErrorMessage := 'Aborted'
  else if performRes <> CURLE_OK then
    FResponse.ErrorMessage := FormatCurlError(performRes);

  if FResponse.StatusCode <> 200 then
  begin
    if FResponse.ErrorMessage = '' then
      FResponse.ErrorMessage := 'HTTP ' + IntToStr(FResponse.StatusCode);
    FResponse.Ok := False;
  end
  else if (FResponse.ErrorMessage = '') and (performRes = CURLE_OK) then
    FResponse.Ok := True;

  if FResponse.Ok then
    FinalizeBody
  else if (FResponse.StatusCode <> 0) and (FResponse.StatusCode <> 200) then
    FinalizeBody;

  CloseResources;
  Result := FResponse;
end;

function NetHttpExecuteSync(const ARequest: TNetHttpRequest): TNetHttpResponse;
var
  ctx: TNetHttpCurlCtx;
begin
  ctx := TNetHttpCurlCtx.Create(ARequest);
  try
    Result := ctx.Execute;
  finally
    ctx.Free;
  end;
end;

end.
