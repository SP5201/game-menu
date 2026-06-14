unit libcurl;

{ Minimal libcurl 7.x bindings for NetHttpWorker.
  Runtime: Bin\libcurl.dll + Bin\libssl-1_1.dll + Bin\libcrypto-1_1.dll (+ Bin\libssh2.dll if linked).
  Loaded dynamically so transitive dependencies resolve from Bin\ directory. }

interface

uses
  SysUtils;

type
  PCURL = Pointer;
  PCurlSlist = ^TCurlSlist;
  TCurlSlist = record
    Data: PAnsiChar;
    Next: PCurlSlist;
  end;
  TCURLcode = Integer;
  TCurlWriteCallback = function(AData: PAnsiChar; ASize, ACount: NativeUInt;
    AUserData: Pointer): NativeUInt; cdecl;
  TCurlXferInfoCallback = function(AClientp: Pointer; ADlTotal, ADlNow, AUlTotal,
    AUlNow: Int64): Integer; cdecl;
  TCurlReadCallback = function(ptr: PAnsiChar; size, nmemb: NativeUInt;
    userdata: Pointer): NativeUInt; cdecl;

const
  CURL_GLOBAL_SSL = 1;
  CURL_GLOBAL_WIN32 = 2;
  CURL_GLOBAL_ALL = CURL_GLOBAL_SSL or CURL_GLOBAL_WIN32;

  CURLOPT_URL = 10002;
  CURLOPT_PROXY = 10004;
  CURLOPT_WRITEDATA = 10001;
  CURLOPT_WRITEFUNCTION = 20011;
  CURLOPT_USERAGENT = 10018;
  CURLOPT_TIMEOUT_MS = 155;
  CURLOPT_CONNECTTIMEOUT_MS = 156;
  CURLOPT_FOLLOWLOCATION = 52;
  CURLOPT_NOSIGNAL = 99;
  CURLOPT_NOPROGRESS = 43;
  CURLOPT_HTTPGET = 80;
  CURLOPT_POST = 47;
  CURLOPT_POSTFIELDS = 10015;
  CURLOPT_HTTPHEADER = 10023;
  CURLOPT_UPLOAD = 46;
  CURLOPT_READDATA = 10009;
  CURLOPT_READFUNCTION = 20012;
  CURLOPT_USERNAME = 10173;
  CURLOPT_PASSWORD = 10174;
  CURLOPT_MAIL_FROM = 10186;
  CURLOPT_MAIL_RCPT = 10187;
  CURLOPT_USE_SSL = 119;
  CURLOPT_LOGIN_OPTIONS = 10224;
  CURLOPT_SSL_VERIFYPEER = 64;
  CURLOPT_SSL_VERIFYHOST = 81;
  CURLOPT_XFERINFODATA = 10057;
  CURLOPT_XFERINFOFUNCTION = 20219;

  CURLOPT_RESOLVE = 10203;
  CURLOPT_DNS_CACHE_TIMEOUT = 92;

  CURLINFO_RESPONSE_CODE = $200002;
  CURLINFO_CONTENT_TYPE = $100012;
  CURLINFO_EFFECTIVE_URL = $100001;

  CURLE_OK = 0;
  CURLE_OPERATION_TIMEDOUT = 28;
  CURLE_ABORTED_BY_CALLBACK = 42;

function CurlLibraryLoaded: Boolean;

function curl_global_init(AFlags: LongInt): TCURLcode; cdecl;
procedure curl_global_cleanup; cdecl;

function curl_easy_init: PCURL; cdecl;
procedure curl_easy_cleanup(ACurl: PCURL); cdecl;
function curl_easy_perform(ACurl: PCURL): TCURLcode; cdecl;
function curl_easy_strerror(ACode: TCURLcode): PAnsiChar; cdecl;

function curl_easy_setopt_str(ACurl: PCURL; AOption: Integer; AParam: PAnsiChar): TCURLcode; cdecl;
function curl_easy_setopt_ptr(ACurl: PCURL; AOption: Integer; AParam: Pointer): TCURLcode; cdecl;
function curl_easy_setopt_cb(ACurl: PCURL; AOption: Integer; AParam: Pointer): TCURLcode; cdecl;
function curl_easy_setopt_long(ACurl: PCURL; AOption: Integer; AParam: LongInt): TCURLcode; cdecl;

function curl_easy_getinfo_long(ACurl: PCURL; AInfo: Integer; var AParam: LongInt): TCURLcode; cdecl;
function curl_easy_getinfo_str(ACurl: PCURL; AInfo: Integer; var AParam: PAnsiChar): TCURLcode; cdecl;

function curl_slist_append(ASlist: PCurlSlist; AData: PAnsiChar): PCurlSlist; cdecl;
procedure curl_slist_free_all(ASlist: PCurlSlist); cdecl;

function CurlAnsiUrl(const AUrl: string): AnsiString;

implementation

uses
  Windows, AppPaths;

type
  TCurl_global_init = function(AFlags: LongInt): TCURLcode; cdecl;
  TCurl_global_cleanup = procedure; cdecl;
  TCurl_easy_init = function: PCURL; cdecl;
  TCurl_easy_cleanup = procedure(ACurl: PCURL); cdecl;
  TCurl_easy_perform = function(ACurl: PCURL): TCURLcode; cdecl;
  TCurl_easy_strerror = function(ACode: TCURLcode): PAnsiChar; cdecl;
  TCurl_easy_setopt = function(ACurl: PCURL; AOption: Integer; AParam: Pointer): TCURLcode; cdecl;
  TCurl_easy_getinfo = function(ACurl: PCURL; AInfo: Integer; AParam: Pointer): TCURLcode; cdecl;
  TCurl_slist_append = function(ASlist: PCurlSlist; AData: PAnsiChar): PCurlSlist; cdecl;
  TCurl_slist_free_all = procedure(ASlist: PCurlSlist); cdecl;

var
  GCurlLib: HMODULE = 0;
  GCurl_global_init: TCurl_global_init = nil;
  GCurl_global_cleanup: TCurl_global_cleanup = nil;
  GCurl_easy_init: TCurl_easy_init = nil;
  GCurl_easy_cleanup: TCurl_easy_cleanup = nil;
  GCurl_easy_perform: TCurl_easy_perform = nil;
  GCurl_easy_strerror: TCurl_easy_strerror = nil;
  GCurl_easy_setopt: TCurl_easy_setopt = nil;
  GCurl_easy_getinfo: TCurl_easy_getinfo = nil;
  GCurl_slist_append: TCurl_slist_append = nil;
  GCurl_slist_free_all: TCurl_slist_free_all = nil;
  GCurlInitRef: Integer = 0;

function EnsureCurlLoaded: Boolean;
begin
  Result := GCurlLib <> 0;
  if Result then
    Exit;
  GCurlLib := LoadLibrary(PChar(AppBinDllPath('libcurl.dll')));
  if GCurlLib = 0 then
    Exit(False);
  @GCurl_global_init := GetProcAddress(GCurlLib, 'curl_global_init');
  @GCurl_global_cleanup := GetProcAddress(GCurlLib, 'curl_global_cleanup');
  @GCurl_easy_init := GetProcAddress(GCurlLib, 'curl_easy_init');
  @GCurl_easy_cleanup := GetProcAddress(GCurlLib, 'curl_easy_cleanup');
  @GCurl_easy_perform := GetProcAddress(GCurlLib, 'curl_easy_perform');
  @GCurl_easy_strerror := GetProcAddress(GCurlLib, 'curl_easy_strerror');
  @GCurl_easy_setopt := GetProcAddress(GCurlLib, 'curl_easy_setopt');
  @GCurl_easy_getinfo := GetProcAddress(GCurlLib, 'curl_easy_getinfo');
  @GCurl_slist_append := GetProcAddress(GCurlLib, 'curl_slist_append');
  @GCurl_slist_free_all := GetProcAddress(GCurlLib, 'curl_slist_free_all');
  Result := Assigned(GCurl_global_init) and Assigned(GCurl_global_cleanup) and
    Assigned(GCurl_easy_init) and Assigned(GCurl_easy_cleanup) and
    Assigned(GCurl_easy_perform) and Assigned(GCurl_easy_setopt) and
    Assigned(GCurl_easy_getinfo) and Assigned(GCurl_slist_append) and
    Assigned(GCurl_slist_free_all);
  if not Result then
  begin
    FreeLibrary(GCurlLib);
    GCurlLib := 0;
  end;
end;

function CurlLibraryLoaded: Boolean;
begin
  Result := EnsureCurlLoaded;
end;

function curl_global_init(AFlags: LongInt): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_global_init(AFlags);
end;

procedure curl_global_cleanup;
begin
  if Assigned(GCurl_global_cleanup) then
    GCurl_global_cleanup;
end;

function curl_easy_init: PCURL;
begin
  if not EnsureCurlLoaded then
    Exit(nil);
  Result := GCurl_easy_init;
end;

procedure curl_easy_cleanup(ACurl: PCURL);
begin
  if Assigned(GCurl_easy_cleanup) then
    GCurl_easy_cleanup(ACurl);
end;

function curl_easy_perform(ACurl: PCURL): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_perform(ACurl);
end;

function curl_easy_strerror(ACode: TCURLcode): PAnsiChar;
begin
  if not EnsureCurlLoaded then
    Exit(nil);
  Result := GCurl_easy_strerror(ACode);
end;

function curl_easy_setopt_str(ACurl: PCURL; AOption: Integer; AParam: PAnsiChar): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_setopt(ACurl, AOption, AParam);
end;

function curl_easy_setopt_ptr(ACurl: PCURL; AOption: Integer; AParam: Pointer): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_setopt(ACurl, AOption, AParam);
end;

function curl_easy_setopt_cb(ACurl: PCURL; AOption: Integer; AParam: Pointer): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_setopt(ACurl, AOption, AParam);
end;

function curl_easy_setopt_long(ACurl: PCURL; AOption: Integer; AParam: LongInt): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_setopt(ACurl, AOption, Pointer(AParam));
end;

function curl_easy_getinfo_long(ACurl: PCURL; AInfo: Integer; var AParam: LongInt): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_getinfo(ACurl, AInfo, @AParam);
end;

function curl_easy_getinfo_str(ACurl: PCURL; AInfo: Integer; var AParam: PAnsiChar): TCURLcode;
begin
  if not EnsureCurlLoaded then
    Exit(-1);
  Result := GCurl_easy_getinfo(ACurl, AInfo, @AParam);
end;

function curl_slist_append(ASlist: PCurlSlist; AData: PAnsiChar): PCurlSlist;
begin
  if not EnsureCurlLoaded then
    Exit(nil);
  Result := GCurl_slist_append(ASlist, AData);
end;

procedure curl_slist_free_all(ASlist: PCurlSlist);
begin
  if Assigned(GCurl_slist_free_all) then
    GCurl_slist_free_all(ASlist);
end;

function CurlAnsiUrl(const AUrl: string): AnsiString;
begin
  Result := AnsiString(UTF8Encode(Trim(AUrl)));
end;

procedure CurlGlobalAcquire;
begin
  if InterlockedIncrement(GCurlInitRef) = 1 then
    curl_global_init(CURL_GLOBAL_ALL);
end;

procedure CurlGlobalRelease;
begin
  if InterlockedDecrement(GCurlInitRef) = 0 then
  begin
    curl_global_cleanup;
    if GCurlLib <> 0 then
    begin
      FreeLibrary(GCurlLib);
      GCurlLib := 0;
      GCurl_global_init := nil;
      GCurl_global_cleanup := nil;
      GCurl_easy_init := nil;
      GCurl_easy_cleanup := nil;
      GCurl_easy_perform := nil;
      GCurl_easy_strerror := nil;
      GCurl_easy_setopt := nil;
      GCurl_easy_getinfo := nil;
      GCurl_slist_append := nil;
      GCurl_slist_free_all := nil;
    end;
  end;
end;

initialization
  CurlGlobalAcquire;

finalization
  CurlGlobalRelease;

end.
