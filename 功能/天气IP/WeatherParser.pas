unit WeatherParser;

interface

uses
  SysUtils, NetHttpWorker;

const
  cWeatherDash = '--';
  cWeatherLoadingText = '获取中...';
  cOpenMeteoApiBase = 'https://api.open-meteo.com';
  cOpenMeteoPollutantsApiBase = 'https://air-quality-api.open-meteo.com';

type
  TWeatherInfo = record
    City: string;
    Temperature: string;
    CurrentTemperature: string;
    ApparentTemperature: string;
    Precipitation: string;
    WindSpeed: string;
    WindDirection: string;
    Pressure: string;
    Sunrise: string;
    Sunset: string;
    Humidity: string;
    PrecipitationProbability: string;
    UvIndex: string;
    Pollutants: string;
    Condition: string;
    IconCode: Integer;
  end;

function EmptyWeatherInfo: TWeatherInfo;
function BuildOpenMeteoForecastRequest(const ALatitude, ALongitude: Double): TNetHttpRequest;
function BuildOpenMeteoPollutantsRequest(const ALatitude, ALongitude: Double): TNetHttpRequest;
function TryParseGeoCoords(const ALatText, ALonText: string; out ALatitude, ALongitude: Double): Boolean;
function CleanCityName(const ACity: string): string;
function DescribeHttpResponseError(const AResponse: TNetHttpResponse): string;
function DescribeForecastParseError(const ABody: string): string;
function ParseWeatherResponse(const AResponse: TNetHttpResponse;
  out AInfo: TWeatherInfo; out AErrorReason: string): Boolean;
function ParsePollutantsResponse(const AResponse: TNetHttpResponse;
  var AInfo: TWeatherInfo; out AErrorReason: string): Boolean;

implementation

uses
  Windows, Math;

function EmptyWeatherInfo: TWeatherInfo;
begin
  Result.City := cWeatherDash;
  Result.Temperature := cWeatherDash;
  Result.CurrentTemperature := cWeatherDash;
  Result.ApparentTemperature := cWeatherDash;
  Result.Precipitation := cWeatherDash;
  Result.WindSpeed := cWeatherDash;
  Result.WindDirection := cWeatherDash;
  Result.Pressure := cWeatherDash;
  Result.Sunrise := cWeatherDash;
  Result.Sunset := cWeatherDash;
  Result.Humidity := cWeatherDash;
  Result.PrecipitationProbability := cWeatherDash;
  Result.UvIndex := cWeatherDash;
  Result.Pollutants := cWeatherDash;
  Result.Condition := cWeatherDash;
  Result.IconCode := 999;
end;

function FloatToUrlParam(const V: Double): string;
begin
  Result := StringReplace(Format('%.4f', [V]), ',', '.', [rfReplaceAll]);
end;

function MakeNetHttpRequest(const AUrl: string): TNetHttpRequest;
begin
  Result.Url := AUrl;
  Result.Kind := hkText;
  Result.SaveToFile := '';
  Result.Options := NetHttpDefaultOptions;
  Result.UserData := 0;
end;

function TryParseGeoCoords(const ALatText, ALonText: string; out ALatitude, ALongitude: Double): Boolean;
var
  latStr, lonStr: string;
begin
  Result := False;
  ALatitude := 0;
  ALongitude := 0;
  latStr := Trim(ALatText);
  lonStr := Trim(ALonText);
  if (latStr = '') or (lonStr = '') or (latStr = cWeatherDash) or (lonStr = cWeatherDash) then
    Exit;
  latStr := StringReplace(latStr, ',', '.', [rfReplaceAll]);
  lonStr := StringReplace(lonStr, ',', '.', [rfReplaceAll]);
  ALatitude := StrToFloatDef(latStr, 0);
  ALongitude := StrToFloatDef(lonStr, 0);
  if (ALatitude < -90) or (ALatitude > 90) or (ALongitude < -180) or (ALongitude > 180) then
    Exit;
  if (Abs(ALatitude) < 0.0001) and (Abs(ALongitude) < 0.0001) then
    Exit;
  Result := True;
end;

function BuildOpenMeteoForecastRequest(const ALatitude, ALongitude: Double): TNetHttpRequest;
begin
  Result := MakeNetHttpRequest(
    cOpenMeteoApiBase + '/v1/forecast' +
    '?latitude=' + FloatToUrlParam(ALatitude) +
    '&longitude=' + FloatToUrlParam(ALongitude) +
    '&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,wind_speed_10m,wind_direction_10m,surface_pressure,pressure_msl,weather_code,is_day' +
    '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,uv_index_max,sunrise,sunset' +
    '&timezone=auto&forecast_days=1');
end;

function BuildOpenMeteoPollutantsRequest(const ALatitude, ALongitude: Double): TNetHttpRequest;
begin
  Result := MakeNetHttpRequest(
    cOpenMeteoPollutantsApiBase + '/v1/air-quality' +
    '?latitude=' + FloatToUrlParam(ALatitude) +
    '&longitude=' + FloatToUrlParam(ALongitude) +
    '&current=pm2_5,pm10,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,aerosol_optical_depth,dust' +
    '&timezone=auto');
end;

function FindCharFrom(const S: string; const ACh: Char; StartPos: Integer): Integer;
var
  i: Integer;
begin
  for i := StartPos to Length(S) do
    if S[i] = ACh then
      Exit(i);
  Result := 0;
end;

function ExtractBalancedJsonObject(const Json: string; ObjStart: Integer): string;
var
  i, depth: Integer;
begin
  Result := '';
  if (ObjStart < 1) or (ObjStart > Length(Json)) or (Json[ObjStart] <> '{') then
    Exit;
  depth := 0;
  for i := ObjStart to Length(Json) do
  begin
    if Json[i] = '{' then
      Inc(depth)
    else if Json[i] = '}' then
    begin
      Dec(depth);
      if depth = 0 then
      begin
        Result := Copy(Json, ObjStart, i - ObjStart + 1);
        Exit;
      end;
    end;
  end;
end;

function ExtractJsonObjectField(const Json, FieldName: string): string;
var
  fieldPos, objPos: Integer;
begin
  Result := '';
  fieldPos := Pos('"' + FieldName + '"', Json);
  if fieldPos = 0 then
    Exit;
  objPos := FindCharFrom(Json, '{', fieldPos);
  Result := ExtractBalancedJsonObject(Json, objPos);
end;

function ExtractJsonNumberField(const Obj, FieldName: string): string;
var
  marker: string;
  p: Integer;
begin
  Result := '';
  marker := '"' + FieldName + '":';
  p := Pos(marker, Obj);
  if p = 0 then
    Exit;
  p := p + Length(marker);
  while (p <= Length(Obj)) and CharInSet(Obj[p], [' ', #9]) do
    Inc(p);
  if (p + 3 <= Length(Obj)) and SameText(Copy(Obj, p, 4), 'null') then
    Exit;
  while (p <= Length(Obj)) and CharInSet(Obj[p], ['0'..'9', '-', '.']) do
  begin
    Result := Result + Obj[p];
    Inc(p);
  end;
end;

function ExtractJsonArrayFirstNumber(const Obj, FieldName: string): Double;
var
  marker: string;
  p: Integer;
  numText: string;
begin
  Result := -999;
  marker := '"' + FieldName + '":';
  p := Pos(marker, Obj);
  if p = 0 then
    Exit;
  p := FindCharFrom(Obj, '[', p);
  if p = 0 then
    Exit;
  Inc(p);
  while (p <= Length(Obj)) and CharInSet(Obj[p], [' ', #9]) do
    Inc(p);
  numText := '';
  while (p <= Length(Obj)) and CharInSet(Obj[p], ['0'..'9', '-', '.']) do
  begin
    numText := numText + Obj[p];
    Inc(p);
  end;
  if numText <> '' then
    Result := StrToFloatDef(StringReplace(numText, ',', '.', [rfReplaceAll]), -999);
end;

function ExtractJsonArrayFirstString(const Obj, FieldName: string): string;
var
  marker: string;
  p, q: Integer;
begin
  Result := '';
  marker := '"' + FieldName + '":';
  p := Pos(marker, Obj);
  if p = 0 then
    Exit;
  p := FindCharFrom(Obj, '[', p);
  if p = 0 then
    Exit;
  Inc(p);
  while (p <= Length(Obj)) and CharInSet(Obj[p], [' ', #9]) do
    Inc(p);
  if (p > Length(Obj)) or (Obj[p] <> '"') then
    Exit;
  Inc(p);
  q := p;
  while (q <= Length(Obj)) and (Obj[q] <> '"') do
    Inc(q);
  Result := Copy(Obj, p, q - p);
end;

function FormatWeatherTempC(const ADegrees: Double): string;
begin
  Result := IntToStr(Round(ADegrees)) + '°C';
end;

{ 蒲福风级（m/s 阈值与国标 GB/T 28591-2012 一致） }
function WindSpeedMsToBeaufortZh(const AMs: Double): string;
begin
  if AMs < 0 then
    Result := ''
  else if AMs <= 0.2 then
    Result := '0级'
  else if AMs <= 1.5 then
    Result := '1级'
  else if AMs <= 3.3 then
    Result := '2级'
  else if AMs <= 5.4 then
    Result := '3级'
  else if AMs <= 7.9 then
    Result := '4级'
  else if AMs <= 10.7 then
    Result := '5级'
  else if AMs <= 13.8 then
    Result := '6级'
  else if AMs <= 17.1 then
    Result := '7级'
  else if AMs <= 20.7 then
    Result := '8级'
  else if AMs <= 24.4 then
    Result := '9级'
  else if AMs <= 28.4 then
    Result := '10级'
  else if AMs <= 32.6 then
    Result := '11级'
  else
    Result := '12级';
end;

function FormatWindSpeedMs(const AMs: Double): string;
begin
  if AMs < 0 then
    Result := ''
  else if Abs(AMs - Round(AMs)) < 0.05 then
    Result := IntToStr(Round(AMs)) + 'm/s'
  else
    Result := StringReplace(Format('%.1f', [AMs]), ',', '.', [rfReplaceAll]) + 'm/s';
end;

function FormatPressureHpa(const AHpa: Double): string;
begin
  if AHpa < 0 then
    Result := cWeatherDash
  else if Abs(AHpa - Round(AHpa)) < 0.05 then
    Result := IntToStr(Round(AHpa)) + 'hPa'
  else
    Result := StringReplace(Format('%.1f', [AHpa]), ',', '.', [rfReplaceAll]) + 'hPa';
end;

function FormatWindSpeedDisplay(const AKmh: Double): string;
var
  ms: Double;
  level, speedText: string;
begin
  if AKmh < 0 then
    Result := cWeatherDash
  else
  begin
    ms := AKmh / 3.6;
    level := WindSpeedMsToBeaufortZh(ms);
    speedText := FormatWindSpeedMs(ms);
    if (level <> '') and (speedText <> '') then
      Result := level + ' ' + speedText
    else if speedText <> '' then
      Result := speedText
    else
      Result := cWeatherDash;
  end;
end;

function WindDegreesToZh(const ADegrees: Integer): string;
const
  DirNames: array[0..7] of string = ('北', '东北', '东', '东南', '南', '西南', '西', '西北');
var
  normDeg, idx: Integer;
begin
  normDeg := ADegrees mod 360;
  if normDeg < 0 then
    Inc(normDeg, 360);
  idx := ((normDeg + 22) div 45) mod 8;
  Result := DirNames[idx] + '风';
end;

function FormatWeatherPrecipMm(const AMm: Double): string;
begin
  if AMm < 0 then
    Result := cWeatherDash
  else if AMm < 0.05 then
    Result := '0mm'
  else if Abs(AMm - Round(AMm)) < 0.05 then
    Result := IntToStr(Round(AMm)) + 'mm'
  else
    Result := StringReplace(Format('%.1f', [AMm]), ',', '.', [rfReplaceAll]) + 'mm';
end;

function FormatHumidityPercent(const APct: Double): string;
begin 
  if APct < 0 then
    Result := cWeatherDash
  else
    Result := IntToStr(EnsureRange(Round(APct), 0, 100)) + '%';
end;

function FormatPrecipitationProbability(const APct: Double): string;
begin
  if APct < 0 then
    Result := cWeatherDash
  else
    Result := IntToStr(EnsureRange(Round(APct), 0, 100)) + '%';
end;

function UvIndexToZhLevel(const AIndex: Double): string;
begin
  Result := '';
  if AIndex < 0 then
    Exit;
  if AIndex <= 2 then
    Result := '最弱'
  else if AIndex <= 5 then
    Result := '弱'
  else if AIndex <= 7 then
    Result := '中等'
  else if AIndex <= 10 then
    Result := '强'
  else
    Result := '极强';
end;

function FormatUvIndex(const AIndex: Double): string;
var
  numText, levelText: string;
begin
  if AIndex < 0 then
    Result := cWeatherDash
  else
  begin
    if Abs(AIndex - Round(AIndex)) < 0.05 then
      numText := IntToStr(Round(AIndex))
    else
      numText := StringReplace(Format('%.1f', [AIndex]), ',', '.', [rfReplaceAll]);
    levelText := UvIndexToZhLevel(AIndex);
    if levelText = '' then
      Result := numText
    else
      Result := numText + '(' + levelText + ')';
  end;
end;

function FormatPmUgM3(const AValue: Double): string;
begin
  if AValue < 0 then
    Result := ''
  else if Abs(AValue - Round(AValue)) < 0.05 then
    Result := IntToStr(Round(AValue)) + 'μg/m³'
  else
    Result := StringReplace(Format('%.1f', [AValue]), ',', '.', [rfReplaceAll]) + 'μg/m³';
end;

function JsonFieldToFloat(const Obj, FieldName: string): Double;
begin
  Result := StrToFloatDef(
    StringReplace(ExtractJsonNumberField(Obj, FieldName), ',', '.', [rfReplaceAll]), -1);
end;

function AppendPollutantLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

{ 颗粒物国标分档（HJ 633-2012 / GB 3095-2012 24h 浓度 μg/m³；沙尘同用 PM10 档） }
function Pm25UgToZhAirLevel(const APm25: Double): string;
begin
  Result := '';
  if APm25 < 0 then
    Exit;
  if APm25 <= 35 then
    Result := '优'
  else if APm25 <= 75 then
    Result := '良'
  else if APm25 <= 115 then
    Result := '轻度污染'
  else if APm25 <= 150 then
    Result := '中度污染'
  else if APm25 <= 250 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

function Pm10UgToZhAirLevel(const APm10: Double): string;
begin
  Result := '';
  if APm10 < 0 then
    Exit;
  if APm10 <= 50 then
    Result := '优'
  else if APm10 <= 150 then
    Result := '良'
  else if APm10 <= 250 then
    Result := '轻度污染'
  else if APm10 <= 350 then
    Result := '中度污染'
  else if APm10 <= 420 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

{ 气态污染物国标分档（HJ 633-2012 / GB 3095-2012 浓度阈值；Open-Meteo 为 μg/m³） }
function CoUgToZhAirLevel(const ACoUg: Double): string;
begin
  Result := '';
  if ACoUg < 0 then
    Exit;
  { CO 24h：2/4/14/24/36 mg/m³ → 2000/4000/14000/24000/36000 μg/m³ }
  if ACoUg <= 2000 then
    Result := '优'
  else if ACoUg <= 4000 then
    Result := '良'
  else if ACoUg <= 14000 then
    Result := '轻度污染'
  else if ACoUg <= 24000 then
    Result := '中度污染'
  else if ACoUg <= 36000 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

function No2UgToZhAirLevel(const ANo2: Double): string;
begin
  Result := '';
  if ANo2 < 0 then
    Exit;
  if ANo2 <= 40 then
    Result := '优'
  else if ANo2 <= 80 then
    Result := '良'
  else if ANo2 <= 180 then
    Result := '轻度污染'
  else if ANo2 <= 280 then
    Result := '中度污染'
  else if ANo2 <= 565 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

function So2UgToZhAirLevel(const ASo2: Double): string;
begin
  Result := '';
  if ASo2 < 0 then
    Exit;
  if ASo2 <= 50 then
    Result := '优'
  else if ASo2 <= 150 then
    Result := '良'
  else if ASo2 <= 475 then
    Result := '轻度污染'
  else if ASo2 <= 800 then
    Result := '中度污染'
  else if ASo2 <= 1600 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

function O3UgToZhAirLevel(const AO3: Double): string;
begin
  Result := '';
  if AO3 < 0 then
    Exit;
  { 臭氧按 1h 浓度分档（实时 current 近似） }
  if AO3 <= 160 then
    Result := '优'
  else if AO3 <= 200 then
    Result := '良'
  else if AO3 <= 300 then
    Result := '轻度污染'
  else if AO3 <= 400 then
    Result := '中度污染'
  else if AO3 <= 800 then
    Result := '重度污染'
  else
    Result := '严重污染';
end;

function FormatPollutantLine(const AName, AValueText, ALevelZh: string): string;
begin
  if AValueText = '' then
    Result := ''
  else if ALevelZh = '' then
    Result := AName + '：' + AValueText
  else
    Result := AName + '：' + AValueText + '(' + ALevelZh + ')';
end;

function FormatAerosolIndex(const AValue: Double): string;
begin
  if AValue < 0 then
    Result := ''
  else if Abs(AValue - Round(AValue)) < 0.005 then
    Result := IntToStr(Round(AValue))
  else
    Result := StringReplace(Format('%.2f', [AValue]), ',', '.', [rfReplaceAll]);
end;

function BuildPollutantsDisplay(const ACurrentObj: string): string;
var
  v: Double;
  lineLevel: string;
begin
  Result := '';
  v := JsonFieldToFloat(ACurrentObj, 'pm2_5');
  if v >= 0 then
  begin
    lineLevel := Pm25UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('PM2.5', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'pm10');
  if v >= 0 then
  begin
    lineLevel := Pm10UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('PM10', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'carbon_monoxide');
  if v >= 0 then
  begin
    lineLevel := CoUgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('一氧化碳', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'nitrogen_dioxide');
  if v >= 0 then
  begin
    lineLevel := No2UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('二氧化氮', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'sulphur_dioxide');
  if v >= 0 then
  begin
    lineLevel := So2UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('二氧化硫', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'ozone');
  if v >= 0 then
  begin
    lineLevel := O3UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('臭氧', FormatPmUgM3(v), lineLevel));
  end;
  v := JsonFieldToFloat(ACurrentObj, 'aerosol_optical_depth');
  if v >= 0 then
    Result := AppendPollutantLine(Result, '气溶胶指数：' + FormatAerosolIndex(v));
  v := JsonFieldToFloat(ACurrentObj, 'dust');
  if v >= 0 then
  begin
    lineLevel := Pm10UgToZhAirLevel(v);
    Result := AppendPollutantLine(Result, FormatPollutantLine('沙尘', FormatPmUgM3(v), lineLevel));
  end;
end;

function FormatIsoTimeToHm(const AIso: string): string;
var
  tPos: Integer;
  timePart: string;
begin
  Result := cWeatherDash;
  if Trim(AIso) = '' then
    Exit;
  tPos := Pos('T', AIso);
  if tPos = 0 then
    Exit;
  timePart := Copy(AIso, tPos + 1, MaxInt);
  if Length(timePart) >= 5 then
    Result := Copy(timePart, 1, 5);
end;

procedure ApplyDayNightIcon(var AIconCode: Integer; const ADayCode, ANightCode: Integer; const AIsDay: Boolean);
begin
  if AIsDay then
    AIconCode := ADayCode
  else
    AIconCode := ANightCode;
end;

function WmoWeatherCodeToZh(const AWmoCode: Integer): string;
begin
  case AWmoCode of
    0: Result := '晴';
    1: Result := '晴';
    2: Result := '少云';
    3: Result := '阴';
    45: Result := '雾';
    48: Result := '雾';
    51, 53, 55: Result := '毛毛雨';
    56, 57: Result := '冻毛毛雨';
    61: Result := '小雨';
    63: Result := '中雨';
    65: Result := '大雨';
    66, 67: Result := '冻雨';
    71: Result := '小雪';
    73: Result := '中雪';
    75: Result := '大雪';
    77: Result := '雪粒';
    80, 81, 82: Result := '阵雨';
    85, 86: Result := '阵雪';
    95: Result := '雷暴';
    96, 99: Result := '雷暴冰雹';
    4, 5: Result := '霾';
    6, 7: Result := '浮尘';
    8, 9: Result := '沙尘暴';
    10, 11, 12: Result := '雾';
    13, 14, 15: Result := '小雪';
    16, 17: Result := '中雪';
    18, 19: Result := '大雪';
    20, 21: Result := '雨';
    22, 23: Result := '小雪';
    24, 25, 26: Result := '中雪';
    27: Result := '大雪';
    28, 29: Result := '雷暴';
    30, 31, 32, 33, 34, 35: Result := '沙尘';
    36, 37: Result := '雷阵雨';
    38, 39: Result := '雷阵雨';
    40, 41, 42: Result := '暴雨';
    43, 44: Result := '暴雪';
    47: Result := '雾';
    49, 50: Result := '冻雾';
    52, 54: Result := '毛毛雨';
    58, 59: Result := '雨夹雪';
    60: Result := '小雨';
    62: Result := '中雨';
    64: Result := '大雨';
    68, 69: Result := '雨夹雪';
    70: Result := '小雪';
    72: Result := '中雪';
    74: Result := '大雪';
    76: Result := '冰粒';
    78, 79: Result := '小雪';
    83, 84: Result := '阵雨';
    87, 88, 89: Result := '冰雹';
    90, 91, 92: Result := '小雨';
    93, 94: Result := '雷阵雨';
    97, 98: Result := '雷暴';
  else
    Result := '';
  end;
end;

function WmoWeatherCodeToQIcon(const AWmoCode: Integer; const AIsDay: Boolean): Integer;
begin
  Result := 999;
  case AWmoCode of
    0, 1: ApplyDayNightIcon(Result, 100, 150, AIsDay);
    2: ApplyDayNightIcon(Result, 102, 152, AIsDay);
    3: ApplyDayNightIcon(Result, 104, 151, AIsDay);
    4, 5: Result := 502;
    6, 7: Result := 504;
    8, 9: Result := 508;
    10, 11, 12, 45, 47, 48, 49, 50: Result := 501;
    13, 14, 15, 22, 23, 70, 71, 76, 77, 78, 79: Result := 400;
    16, 17, 24, 25, 26, 72, 73: Result := 401;
    18, 19, 27, 74, 75: Result := 402;
    20, 21: Result := 399;
    28, 29, 36, 37, 38, 39, 93, 94, 95, 97, 98: Result := 302;
    30, 31, 32, 33, 34, 35: Result := 503;
    40, 41, 42: Result := 310;
    43, 44: Result := 403;
    51, 52, 53, 54, 55, 60, 61, 90, 91, 92: Result := 305;
    56, 57, 66, 67: Result := 313;
    58, 59, 68, 69: Result := 405;
    62, 63: Result := 306;
    64, 65: Result := 307;
    80, 81, 82, 83, 84: ApplyDayNightIcon(Result, 300, 350, AIsDay);
    85, 86: ApplyDayNightIcon(Result, 407, 457, AIsDay);
    87, 88, 89, 96, 99: Result := 304;
  end;
end;

function ConditionTextToQIcon(const ACondition: string; const AIsDay: Boolean): Integer;

  function HasSubstr(const Sub: string): Boolean;
  begin
    Result := Pos(Sub, ACondition) > 0;
  end;

begin
  Result := 999;
  if ACondition = cWeatherDash then
    Exit;
  if HasSubstr('冰雹') then Exit(304);
  if HasSubstr('雷') then
  begin
    if HasSubstr('强') or HasSubstr('大') then Exit(303);
    Exit(302);
  end;
  if HasSubstr('暴雪') then Exit(403);
  if HasSubstr('雨夹雪') or HasSubstr('雨雪') then Exit(405);
  if HasSubstr('大暴雨') or HasSubstr('特大暴雨') then Exit(312);
  if HasSubstr('暴雨') then Exit(310);
  if HasSubstr('大雨') or HasSubstr('极端') then Exit(307);
  if HasSubstr('中雨') then Exit(306);
  if HasSubstr('小雨') or HasSubstr('毛毛雨') or HasSubstr('细雨') then Exit(305);
  if HasSubstr('阵雨') then
  begin
    ApplyDayNightIcon(Result, 300, 350, AIsDay);
    Exit;
  end;
  if HasSubstr('雨') then Exit(399);
  if HasSubstr('大雪') then Exit(402);
  if HasSubstr('中雪') then Exit(401);
  if HasSubstr('小雪') or HasSubstr('阵雪') then
  begin
    if HasSubstr('阵') then
      ApplyDayNightIcon(Result, 407, 457, AIsDay)
    else
      Result := 400;
    Exit;
  end;
  if HasSubstr('冰粒') or HasSubstr('雪粒') then Exit(400);
  if HasSubstr('雪') then Exit(499);
  if HasSubstr('沙尘暴') then Exit(508);
  if HasSubstr('扬沙') then Exit(503);
  if HasSubstr('沙尘') then Exit(503);
  if HasSubstr('浮尘') then Exit(504);
  if HasSubstr('雾') or HasSubstr('浓雾') or HasSubstr('冻雾') then Exit(501);
  if HasSubstr('薄雾') then Exit(500);
  if HasSubstr('霾') then Exit(502);
  if HasSubstr('阴') then
    ApplyDayNightIcon(Result, 104, 151, AIsDay)
  else if HasSubstr('晴间多云') then
    ApplyDayNightIcon(Result, 103, 153, AIsDay)
  else if HasSubstr('多云') then
    ApplyDayNightIcon(Result, 101, 151, AIsDay)
  else if HasSubstr('少云') then
    ApplyDayNightIcon(Result, 102, 152, AIsDay)
  else if HasSubstr('晴') then
    ApplyDayNightIcon(Result, 100, 150, AIsDay);
end;

function ResolveQWeatherIconCode(const AWmoCode: Integer; const ACondition: string; const AIsDay: Boolean): Integer;
begin
  Result := WmoWeatherCodeToQIcon(AWmoCode, AIsDay);
  if Result <> 999 then
    Exit;
  Result := ConditionTextToQIcon(ACondition, AIsDay);
end;

function IsLocalDaytime: Boolean;
var
  st: TSystemTime;
begin
  GetLocalTime(st);
  Result := (st.wHour >= 6) and (st.wHour < 18);
end;

function ParseOpenMeteoForecastBody(const ABody: string; out AInfo: TWeatherInfo): Boolean;
var
  currentObj, dailyObj, condText, sunriseIso, sunsetIso: string;
  minTemp, maxTemp, curTemp, apparentTemp, precipMm, windKmh, pressureHpa: Double;
  humidityPct, precipProbPct, uvMax: Double;
  wmoCode, isDayFlag, windDeg: Integer;
  isDay: Boolean;
begin
  Result := False;
  AInfo := EmptyWeatherInfo;
  currentObj := ExtractJsonObjectField(ABody, 'current');
  dailyObj := ExtractJsonObjectField(ABody, 'daily');
  if dailyObj = '' then
    Exit;
  minTemp := ExtractJsonArrayFirstNumber(dailyObj, 'temperature_2m_min');
  maxTemp := ExtractJsonArrayFirstNumber(dailyObj, 'temperature_2m_max');
  if (minTemp < -100) or (maxTemp < -100) then
    Exit;
  AInfo.Temperature := IntToStr(Round(minTemp)) + '-' + IntToStr(Round(maxTemp)) + '°C';
  precipMm := ExtractJsonArrayFirstNumber(dailyObj, 'precipitation_sum');
  if precipMm >= 0 then
    AInfo.Precipitation := FormatWeatherPrecipMm(precipMm);
  precipProbPct := ExtractJsonArrayFirstNumber(dailyObj, 'precipitation_probability_max');
  if precipProbPct >= 0 then
    AInfo.PrecipitationProbability := FormatPrecipitationProbability(precipProbPct);
  uvMax := ExtractJsonArrayFirstNumber(dailyObj, 'uv_index_max');
  if uvMax >= 0 then
    AInfo.UvIndex := FormatUvIndex(uvMax);
  sunriseIso := ExtractJsonArrayFirstString(dailyObj, 'sunrise');
  sunsetIso := ExtractJsonArrayFirstString(dailyObj, 'sunset');
  AInfo.Sunrise := FormatIsoTimeToHm(sunriseIso);
  AInfo.Sunset := FormatIsoTimeToHm(sunsetIso);
  wmoCode := -1;
  isDay := IsLocalDaytime;
  if currentObj <> '' then
  begin
    curTemp := StrToFloatDef(
      StringReplace(ExtractJsonNumberField(currentObj, 'temperature_2m'), ',', '.', [rfReplaceAll]),
      -999);
    if curTemp > -100 then
      AInfo.CurrentTemperature := FormatWeatherTempC(curTemp);
    apparentTemp := StrToFloatDef(
      StringReplace(ExtractJsonNumberField(currentObj, 'apparent_temperature'), ',', '.', [rfReplaceAll]),
      -999);
    if apparentTemp > -100 then
      AInfo.ApparentTemperature := FormatWeatherTempC(apparentTemp);
    humidityPct := StrToFloatDef(
      StringReplace(ExtractJsonNumberField(currentObj, 'relative_humidity_2m'), ',', '.', [rfReplaceAll]),
      -999);
    if humidityPct >= 0 then
      AInfo.Humidity := FormatHumidityPercent(humidityPct);
    windKmh := StrToFloatDef(
      StringReplace(ExtractJsonNumberField(currentObj, 'wind_speed_10m'), ',', '.', [rfReplaceAll]),
      -999);
    if windKmh >= 0 then
      AInfo.WindSpeed := FormatWindSpeedDisplay(windKmh);
    windDeg := StrToIntDef(ExtractJsonNumberField(currentObj, 'wind_direction_10m'), -1);
    if windDeg >= 0 then
      AInfo.WindDirection := WindDegreesToZh(windDeg);
    pressureHpa := StrToFloatDef(
      StringReplace(ExtractJsonNumberField(currentObj, 'surface_pressure'), ',', '.', [rfReplaceAll]),
      -999);
    if pressureHpa < 0 then
      pressureHpa := StrToFloatDef(
        StringReplace(ExtractJsonNumberField(currentObj, 'pressure_msl'), ',', '.', [rfReplaceAll]),
        -999);
    if pressureHpa >= 0 then
      AInfo.Pressure := FormatPressureHpa(pressureHpa);
    wmoCode := StrToIntDef(ExtractJsonNumberField(currentObj, 'weather_code'), -1);
    isDayFlag := StrToIntDef(ExtractJsonNumberField(currentObj, 'is_day'), -1);
    if isDayFlag = 1 then
      isDay := True
    else if isDayFlag = 0 then
      isDay := False;
  end;
  if wmoCode < 0 then
  begin
    wmoCode := Trunc(ExtractJsonArrayFirstNumber(dailyObj, 'weather_code'));
    if wmoCode < 0 then
      wmoCode := -1;
  end;
  condText := WmoWeatherCodeToZh(wmoCode);
  if condText <> '' then
    AInfo.Condition := condText
  else
    AInfo.Condition := cWeatherDash;
  AInfo.IconCode := ResolveQWeatherIconCode(wmoCode, AInfo.Condition, isDay);
  Result := True;
end;

function CleanCityName(const ACity: string): string;
const
  SuffixList: array[0..3] of string = ('市', '区', '县', '省');
var
  i: Integer;
begin
  Result := Trim(ACity);
  if Result = '' then
    Exit;
  for i := Low(SuffixList) to High(SuffixList) do
  begin
    if (Length(Result) >= Length(SuffixList[i])) and
       (Copy(Result, Length(Result) - Length(SuffixList[i]) + 1, MaxInt) = SuffixList[i]) then
    begin
      Result := Copy(Result, 1, Length(Result) - Length(SuffixList[i]));
      Result := Trim(Result);
      Break;
    end;
  end;
end;

function CheckHttpResponse(const AResponse: TNetHttpResponse; const AContext: string): Boolean;
begin
  Result := False;
  if not AResponse.Ok then
    Exit;
  if AResponse.StatusCode <> 200 then
    Exit;
  if Trim(AResponse.BodyText) = '' then
    Exit;
  Result := True;
end;

function DescribeHttpResponseError(const AResponse: TNetHttpResponse): string;
var
  msg: string;
begin
  msg := Trim(AResponse.ErrorMessage);
  if (msg = 'Timeout') or (Pos('Timeout', msg) > 0) then
    Exit('服务器超时');
  if SameText(msg, 'Aborted') then
    Exit('请求已中止');
  if msg = 'URL empty' then
    Exit('请求地址为空');
  if msg = 'Only https URL supported' then
    Exit('仅支持 HTTPS 地址');
  if (Pos('Couldn''t connect', msg) > 0) or (Pos('Failed to connect', msg) > 0) or
     (Pos('Connection refused', msg) > 0) or (Pos('curl_easy_init', msg) > 0) or
     (Pos('getaddrinfo', msg) > 0) then
    Exit('无法连接服务器');
  if (not AResponse.Ok) and (AResponse.StatusCode = 0) and (msg = '') then
    Exit('服务器无响应');
  if AResponse.StatusCode = 0 then
  begin
    if msg <> '' then
      Exit(msg);
    Exit('服务器无响应');
  end;
  if AResponse.StatusCode <> 200 then
    Exit('服务器返回错误 HTTP ' + IntToStr(AResponse.StatusCode));
  if Trim(AResponse.BodyText) = '' then
    Exit('服务器返回空内容');
  if not AResponse.Ok then
  begin
    if msg <> '' then
      Exit(msg);
    Exit('网络请求失败');
  end;
  Result := '';
end;

function DescribeForecastParseError(const ABody: string): string;
var
  body: string;
begin
  body := Trim(ABody);
  if body = '' then
    Exit('JSON解析失败：响应为空');
  if Pos('"daily"', body) = 0 then
    Exit('JSON解析失败：缺少 daily 字段');
  if Pos('"temperature_2m_min"', body) = 0 then
    Exit('JSON解析失败：缺少温度数据');
  Result := 'JSON解析失败';
end;

function ParseOpenMeteoPollutantsBody(const ABody: string; var AInfo: TWeatherInfo): Boolean;
var
  currentObj, detail: string;
begin
  Result := False;
  currentObj := ExtractJsonObjectField(ABody, 'current');
  if currentObj = '' then
    Exit;
  detail := BuildPollutantsDisplay(currentObj);
  if detail = '' then
    Exit;
  AInfo.Pollutants := detail;
  Result := True;
end;

function ParseWeatherResponse(const AResponse: TNetHttpResponse;
  out AInfo: TWeatherInfo; out AErrorReason: string): Boolean;
begin
  Result := False;
  AInfo := EmptyWeatherInfo;
  AErrorReason := '';
  if not CheckHttpResponse(AResponse, 'Forecast') then
  begin
    AErrorReason := DescribeHttpResponseError(AResponse);
    Exit;
  end;
  Result := ParseOpenMeteoForecastBody(AResponse.BodyText, AInfo);
  if not Result then
    AErrorReason := DescribeForecastParseError(AResponse.BodyText);
end;

function ParsePollutantsResponse(const AResponse: TNetHttpResponse;
  var AInfo: TWeatherInfo; out AErrorReason: string): Boolean;
begin
  Result := False;
  AErrorReason := '';
  if not CheckHttpResponse(AResponse, 'Pollutants') then
  begin
    AErrorReason := DescribeHttpResponseError(AResponse);
    Exit;
  end;
  Result := ParseOpenMeteoPollutantsBody(AResponse.BodyText, AInfo);
  if not Result then
    AErrorReason := 'JSON解析失败：缺少污染物数据';
end;

end.
