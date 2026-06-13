unit WeatherFetcher;

interface

uses
  SysUtils, Classes, SyncObjs, WeatherParser;

type
  TWeatherUpdateProc = procedure(const AInfo: TWeatherInfo);
  TWeatherLoadingProc = procedure;

  TWeatherFetcherThread = class(TThread)
  private
    FWakeEvent: TEvent;
    FOnUpdate: TWeatherUpdateProc;
    FOnLoading: TWeatherLoadingProc;
    procedure NotifyUi(const AInfo: TWeatherInfo);
    procedure NotifyLoading;
    procedure WaitForNextRun(AMs: Cardinal);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    { 唤醒线程立即拉取（IP 坐标变更等） }
    procedure RequestRefresh;
    { 关闭标识 + 唤醒：中断等待与进行中的 HTTP }
    procedure RequestStop;
    { IP 解析成功后传入经纬度；天气仅按坐标请求 Open-Meteo，城市名仅用于展示 }
    class procedure SetLocationFromIp(const ACity, ALatText, ALonText: string);
    class procedure SignalLoading;
    property OnUpdate: TWeatherUpdateProc read FOnUpdate write FOnUpdate;
    property OnLoading: TWeatherLoadingProc read FOnLoading write FOnLoading;
  end;

function FetchWeatherInfo: TWeatherInfo;
function WeatherFormatDisplay(const AInfo: TWeatherInfo): string;
function WeatherFormatTooltip(const AInfo: TWeatherInfo; AIncludeLocationLine: Boolean = True): string;
function WeatherIconSvgPath(const AIconCode: Integer): string;

implementation

uses
  Windows, NetHttpWorker, SafeLog;

const
  cRefreshIntervalMs = 2 * 60 * 60 * 1000; { 2 小时 }

var
  GCityLock: TCriticalSection;
  GWeatherCity: string;
  GWeatherLat: Double;
  GWeatherLon: Double;
  GWeatherHasCoords: Boolean;
  GWeatherThread: TWeatherFetcherThread;

procedure GetWeatherQuery(out ACity: string; out ALat, ALon: Double; out AHasCoords: Boolean);
begin
  GCityLock.Enter;
  try
    ACity := GWeatherCity;
    ALat := GWeatherLat;
    ALon := GWeatherLon;
    AHasCoords := GWeatherHasCoords;
  finally
    GCityLock.Leave;
  end;
end;

function WeatherIconSvgPath(const AIconCode: Integer): string;
begin
  Result := 'Resource\QWeatherIcons\' + IntToStr(AIconCode) + '.svg';
end;

function WeatherFieldValid(const AValue: string): Boolean;
begin
  Result := (AValue <> '') and (AValue <> cWeatherDash);
end;

function AppendTooltipLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

function WeatherFormatTooltip(const AInfo: TWeatherInfo; AIncludeLocationLine: Boolean): string;
var
  locLine, tempLine, tempPart: string;
begin
  Result := '';
  if AIncludeLocationLine then
  begin
    if WeatherFieldValid(AInfo.City) then
      locLine := '归属地：' + AInfo.City
    else
      locLine := '归属地：' + cWeatherDash;
    Result := locLine;
  end;
  tempPart := '';
  if WeatherFieldValid(AInfo.CurrentTemperature) then
    tempPart := '当前' + AInfo.CurrentTemperature;
  if WeatherFieldValid(AInfo.Temperature) then
  begin
    if tempPart <> '' then
      tempPart := tempPart + '，' + AInfo.Temperature
    else
      tempPart := AInfo.Temperature;
  end;
  if tempPart = '' then
    tempLine := '温度：' + cWeatherDash
  else
    tempLine := '温度：' + tempPart;
  Result := AppendTooltipLine(Result, tempLine);
  if WeatherFieldValid(AInfo.ApparentTemperature) then
    Result := AppendTooltipLine(Result, '体感：' + AInfo.ApparentTemperature)
  else
    Result := AppendTooltipLine(Result, '体感：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Humidity) then
    Result := AppendTooltipLine(Result, '湿度：' + AInfo.Humidity)
  else
    Result := AppendTooltipLine(Result, '湿度：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Condition) then
    Result := AppendTooltipLine(Result, '天气：' + AInfo.Condition)
  else
    Result := AppendTooltipLine(Result, '天气：' + cWeatherDash);
  if WeatherFieldValid(AInfo.UvIndex) then
    Result := AppendTooltipLine(Result, '紫外线：' + AInfo.UvIndex)
  else
    Result := AppendTooltipLine(Result, '紫外线：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Precipitation) then
    Result := AppendTooltipLine(Result, '降水：' + AInfo.Precipitation)
  else
    Result := AppendTooltipLine(Result, '降水：' + cWeatherDash);
  if WeatherFieldValid(AInfo.PrecipitationProbability) then
    Result := AppendTooltipLine(Result, '降水概率：' + AInfo.PrecipitationProbability)
  else
    Result := AppendTooltipLine(Result, '降水概率：' + cWeatherDash);
  if WeatherFieldValid(AInfo.WindSpeed) then
    Result := AppendTooltipLine(Result, '风速：' + AInfo.WindSpeed)
  else
    Result := AppendTooltipLine(Result, '风速：' + cWeatherDash);
  if WeatherFieldValid(AInfo.WindDirection) then
    Result := AppendTooltipLine(Result, '风向：' + AInfo.WindDirection)
  else
    Result := AppendTooltipLine(Result, '风向：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Pressure) then
    Result := AppendTooltipLine(Result, '气压：' + AInfo.Pressure)
  else
    Result := AppendTooltipLine(Result, '气压：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Pollutants) then
    Result := AppendTooltipLine(Result, AInfo.Pollutants);
  if WeatherFieldValid(AInfo.Sunrise) then
    Result := AppendTooltipLine(Result, '日出：' + AInfo.Sunrise)
  else
    Result := AppendTooltipLine(Result, '日出：' + cWeatherDash);
  if WeatherFieldValid(AInfo.Sunset) then
    Result := AppendTooltipLine(Result, '日落：' + AInfo.Sunset)
  else
    Result := AppendTooltipLine(Result, '日落：' + cWeatherDash);
end;

function WeatherFormatDisplay(const AInfo: TWeatherInfo): string;
begin
  if AInfo.Temperature = cWeatherDash then
    Result := cWeatherDash
  else
    Result := AInfo.Temperature;
end;

function AppendLogSegment(const ABase, ASegment: string): string;
begin
  if ASegment = '' then
    Result := ABase
  else if ABase = '' then
    Result := ASegment
  else
    Result := ABase + ' | ' + ASegment;
end;

function WeatherFormatLogParsed(const AInfo: TWeatherInfo): string;
begin
  Result := '';
  if WeatherFieldValid(AInfo.City) then
    Result := AppendLogSegment(Result, AInfo.City);
  if WeatherFieldValid(AInfo.Condition) then
    Result := AppendLogSegment(Result, AInfo.Condition);
  if WeatherFieldValid(AInfo.CurrentTemperature) then
    Result := AppendLogSegment(Result, '当前' + AInfo.CurrentTemperature);
  if WeatherFieldValid(AInfo.Temperature) then
    Result := AppendLogSegment(Result, '全天' + AInfo.Temperature);
  if WeatherFieldValid(AInfo.ApparentTemperature) then
    Result := AppendLogSegment(Result, '体感' + AInfo.ApparentTemperature);
  if WeatherFieldValid(AInfo.Humidity) then
    Result := AppendLogSegment(Result, '湿度' + AInfo.Humidity);
  if WeatherFieldValid(AInfo.WindSpeed) then
    Result := AppendLogSegment(Result, '风速' + AInfo.WindSpeed);
  if WeatherFieldValid(AInfo.WindDirection) then
    Result := AppendLogSegment(Result, AInfo.WindDirection);
  if WeatherFieldValid(AInfo.Precipitation) then
    Result := AppendLogSegment(Result, '降水' + AInfo.Precipitation);
  if WeatherFieldValid(AInfo.PrecipitationProbability) then
    Result := AppendLogSegment(Result, '降水概率' + AInfo.PrecipitationProbability);
  if WeatherFieldValid(AInfo.UvIndex) then
    Result := AppendLogSegment(Result, '紫外线' + AInfo.UvIndex);
  if WeatherFieldValid(AInfo.Pressure) then
    Result := AppendLogSegment(Result, '气压' + AInfo.Pressure);
  if WeatherFieldValid(AInfo.Pollutants) then
    Result := AppendLogSegment(Result, AInfo.Pollutants);
  if WeatherFieldValid(AInfo.Sunrise) then
    Result := AppendLogSegment(Result, '日出' + AInfo.Sunrise);
  if WeatherFieldValid(AInfo.Sunset) then
    Result := AppendLogSegment(Result, '日落' + AInfo.Sunset);
  if Result = '' then
    Result := cWeatherDash;
end;

function FetchWeatherByCoords(const ALatitude, ALongitude: Double; out AInfo: TWeatherInfo;
  out AFetchUrls: string; out AFailReason: string): Boolean;
var
  httpReq: TNetHttpRequest;
  httpResp: TNetHttpResponse;
  parseErr, pollErr: string;
begin
  AInfo := EmptyWeatherInfo;
  AFetchUrls := '';
  AFailReason := '';
  Result := False;
  if NetHttpIsAbortPending then
    Exit;
  httpReq := BuildOpenMeteoForecastRequest(ALatitude, ALongitude);
  AFetchUrls := httpReq.Url;
  httpResp := NetHttpExecuteSync(httpReq);
  if NetHttpIsAbortPending then
    Exit;
  Result := ParseWeatherResponse(httpResp, AInfo, parseErr);
  if not Result then
  begin
    AFailReason := parseErr;
    if AFailReason = '' then
      AFailReason := DescribeHttpResponseError(httpResp);
    Exit;
  end;
  if NetHttpIsAbortPending then
    Exit;
  httpReq := BuildOpenMeteoPollutantsRequest(ALatitude, ALongitude);
  AFetchUrls := AFetchUrls + sLineBreak + httpReq.Url;
  httpResp := NetHttpExecuteSync(httpReq);
  ParsePollutantsResponse(httpResp, AInfo, pollErr);
end;

function ToSingleLine(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, sLineBreak, ' ', [rfReplaceAll]),
    #13#10, ' ', [rfReplaceAll]));
end;

function BuildWeatherLogParsed(const AOk: Boolean; const AInfo: TWeatherInfo;
  const AFailReason, AFetchUrls: string): string;
begin
  if AOk then
    Result := WeatherFormatLogParsed(AInfo)
  else
  begin
    Result := Trim(AFailReason);
    if Result = '' then
      Result := '获取天气失败';
    if Trim(AFetchUrls) <> '' then
      Result := Result + ' | ' + ToSingleLine(AFetchUrls);
  end;
end;

function FetchWeatherInfo: TWeatherInfo;
var
  city, displayCity: string;
  lat, lon: Double;
  hasCoords: Boolean;
  startTime: TDateTime;
  t0, elapsed: Cardinal;
  fetchUrls, failReason, logSummary, logParsed: string;
  ok: Boolean;
  attempted: Boolean;
begin
  Result := EmptyWeatherInfo;
  attempted := False;
  startTime := Now;
  t0 := GetTickCount;
  fetchUrls := '';
  failReason := '';
  try
    GetWeatherQuery(city, lat, lon, hasCoords);
    if not hasCoords then
    begin
      if city <> '' then
      begin
        displayCity := CleanCityName(city);
        if displayCity = '' then
          displayCity := city;
        Result.City := displayCity;
      end;
      Exit;
    end;
    attempted := True;
    ok := FetchWeatherByCoords(lat, lon, Result, fetchUrls, failReason);
    displayCity := CleanCityName(city);
    if displayCity = '' then
      displayCity := city;
    if displayCity <> '' then
      Result.City := displayCity;
  except
    on E: Exception do
    begin
      ok := False;
      failReason := '异常：' + E.Message;
    end;
  end;
  if attempted and (not NetHttpIsAbortPending) then
  begin
    if Cardinal(GetTickCount) >= t0 then
      elapsed := Cardinal(GetTickCount) - t0
    else
      elapsed := (High(Cardinal) - t0) + Cardinal(GetTickCount) + 1;
    if ok then
      logSummary := '获取天气信息并解析'
    else if failReason <> '' then
      logSummary := failReason
    else
      logSummary := '获取天气失败';
    logParsed := BuildWeatherLogParsed(ok, Result, failReason, fetchUrls);
    SafeLogFetch('get', '天气信息', logSummary, startTime, elapsed, ok, logParsed);
  end;
end;

class procedure TWeatherFetcherThread.SetLocationFromIp(const ACity, ALatText, ALonText: string);
var
  changed: Boolean;
  newCity: string;
  lat, lon: Double;
begin
  if not TryParseGeoCoords(ALatText, ALonText, lat, lon) then
    Exit;
  newCity := Trim(ACity);
  if (newCity = '') or (newCity = cWeatherDash) then
    newCity := '';
  GCityLock.Enter;
  try
    changed := (not GWeatherHasCoords) or (GWeatherLat <> lat) or (GWeatherLon <> lon) or
      (GWeatherCity <> newCity);
    GWeatherHasCoords := True;
    GWeatherLat := lat;
    GWeatherLon := lon;
    if newCity <> '' then
      GWeatherCity := newCity;
  finally
    GCityLock.Leave;
  end;
  if changed then
  begin
    SignalLoading;
    if GWeatherThread <> nil then
      GWeatherThread.RequestRefresh;
  end;
end;

procedure TWeatherFetcherThread.RequestRefresh;
begin
  FWakeEvent.SetEvent;
end;

procedure TWeatherFetcherThread.RequestStop;
begin
  if Terminated then
    Exit;
  Terminate;
  FWakeEvent.SetEvent;
end;

procedure TWeatherFetcherThread.WaitForNextRun(AMs: Cardinal);
begin
  FWakeEvent.WaitFor(AMs);
end;

class procedure TWeatherFetcherThread.SignalLoading;
begin
  if GWeatherThread <> nil then
    GWeatherThread.NotifyLoading;
end;

constructor TWeatherFetcherThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  FOnUpdate := nil;
  GWeatherThread := Self;
end;

destructor TWeatherFetcherThread.Destroy;
begin
  if GWeatherThread = Self then
    GWeatherThread := nil;
  RequestStop;
  WaitFor;
  FWakeEvent.Free;
  inherited;
end;

procedure TWeatherFetcherThread.NotifyUi(const AInfo: TWeatherInfo);
begin
  if Assigned(FOnUpdate) then
    FOnUpdate(AInfo);
end;

procedure TWeatherFetcherThread.NotifyLoading;
begin
  if Assigned(FOnLoading) then
    FOnLoading();
end;

procedure TWeatherFetcherThread.Execute;
var
  info: TWeatherInfo;
  hasCoords: Boolean;
  city: string;
  lat, lon: Double;
begin
  while not Terminated do
  begin
    GetWeatherQuery(city, lat, lon, hasCoords);
    if not hasCoords then
    begin
      WaitForNextRun(INFINITE);
      Continue;
    end;
    NotifyLoading;
    try
      info := FetchWeatherInfo;
    except
      on E: Exception do
        info := EmptyWeatherInfo;
    end;
    if Terminated then
      Break;
    NotifyUi(info);
    { 拉取完成后复用线程，等待定时刷新或 RequestRefresh 再执行 }
    WaitForNextRun(cRefreshIntervalMs);
  end;
end;

initialization
  GCityLock := TCriticalSection.Create;

finalization
  FreeAndNil(GCityLock);

end.
