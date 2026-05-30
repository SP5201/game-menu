unit ExternalIpParser;

interface

uses
  SysUtils, Classes, NetHttpWorker;

const
  cIpipMyIpUrl = 'https://myip.ipip.net/';
  cExternalIpDash = '--';

type
  TExternalIpInfo = record
    Ip: string;
    Country: string;
    Region: string;
    City: string;
    Area: string;
    Isp: string;
    Longitude: string;
    Latitude: string;
  end;

function EmptyExternalIpInfo: TExternalIpInfo;
function ResolveExternalIpInfo(out AInfo: TExternalIpInfo): Boolean;
function ExternalIpJoinLocation(const AInfo: TExternalIpInfo): string;
procedure FillExternalIpGeoDefaults(var AInfo: TExternalIpInfo);

implementation

uses
  IpCityCoords;

function EmptyExternalIpInfo: TExternalIpInfo;
begin
  Result.Ip := cExternalIpDash;
  Result.Country := cExternalIpDash;
  Result.Region := cExternalIpDash;
  Result.City := cExternalIpDash;
  Result.Area := cExternalIpDash;
  Result.Isp := cExternalIpDash;
  Result.Longitude := cExternalIpDash;
  Result.Latitude := cExternalIpDash;
end;

function IsValidPublicIpv4(const AIp: string): Boolean;
var
  parts: TStringList;
  i, n: Integer;
begin
  Result := False;
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Trim(AIp);
    if parts.Count <> 4 then
      Exit;
    for i := 0 to 3 do
    begin
      n := StrToIntDef(Trim(parts[i]), -1);
      if (n < 0) or (n > 255) then
        Exit;
    end;
    Result := True;
  finally
    parts.Free;
  end;
end;

function ExtractFirstIpv4FromText(const AText: string): string;
var
  i, start, n, dots: Integer;
  ch: Char;
  part: string;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    while (i <= Length(AText)) and not CharInSet(AText[i], ['0'..'9']) do
      Inc(i);
    if i > Length(AText) then
      Break;
    start := i;
    dots := 0;
    part := '';
    while i <= Length(AText) do
    begin
      ch := AText[i];
      if CharInSet(ch, ['0'..'9']) then
        part := part + ch
      else if ch = '.' then
      begin
        n := StrToIntDef(part, -1);
        if (n < 0) or (n > 255) then
          Break;
        part := '';
        Inc(dots);
        if dots > 3 then
          Break;
      end
      else
        Break;
      Inc(i);
    end;
    if (dots = 3) and (part <> '') then
    begin
      n := StrToIntDef(part, -1);
      if (n >= 0) and (n <= 255) then
      begin
        Result := Copy(AText, start, i - start);
        if IsValidPublicIpv4(Result) then
          Exit;
      end;
    end;
    Inc(i);
  end;
  Result := '';
end;

function RegionFieldValid(const S: string): Boolean;
begin
  Result := (S <> '') and (S <> '0') and (S <> cExternalIpDash);
end;

function NormalizeIspName(const S: string): string;
begin
  if Pos('移动', S) > 0 then
    Exit('移动');
  if Pos('联通', S) > 0 then
    Exit('联通');
  if Pos('电信', S) > 0 then
    Exit('电信');
  Result := Trim(S);
end;

procedure AppendLocationPart(var ADest: string; const APart: string);
begin
  if not RegionFieldValid(APart) then
    Exit;
  if ADest <> '' then
    ADest := ADest + ' ';
  ADest := ADest + APart;
end;

function ExternalIpJoinLocation(const AInfo: TExternalIpInfo): string;
begin
  Result := '';
  if RegionFieldValid(AInfo.Country) and (AInfo.Country <> '中国') then
    AppendLocationPart(Result, AInfo.Country);
  AppendLocationPart(Result, AInfo.Region);
  AppendLocationPart(Result, AInfo.City);
  AppendLocationPart(Result, AInfo.Area);
  if Result = '' then
    Result := cExternalIpDash;
end;

procedure FillExternalIpGeoDefaults(var AInfo: TExternalIpInfo);
begin
  if AInfo.Ip = '' then
    AInfo.Ip := cExternalIpDash;
  if AInfo.Country = '' then
    AInfo.Country := cExternalIpDash;
  if AInfo.Region = '' then
    AInfo.Region := cExternalIpDash;
  if AInfo.City = '' then
    AInfo.City := cExternalIpDash;
  if AInfo.Area = '' then
    AInfo.Area := cExternalIpDash;
  if AInfo.Isp = '' then
    AInfo.Isp := cExternalIpDash;
  if AInfo.Longitude = '' then
    AInfo.Longitude := cExternalIpDash;
  if AInfo.Latitude = '' then
    AInfo.Latitude := cExternalIpDash;
end;

function Utf8Marker(const AUtf8: AnsiString): string;
begin
  if AUtf8 = '' then
    Result := ''
  else
    Result := UTF8ToString(AUtf8);
end;

function FindIpipFromPos(const AText: string): Integer;
var
  mFull, mShort: string;
begin
  mFull := Utf8Marker(#$E6#$9D#$A5#$E8#$87#$AA#$E4#$BA#$8E);
  Result := Pos(mFull, AText);
  if Result > 0 then
    Exit;
  Result := Pos('来自于', AText);
  if Result > 0 then
    Exit;
  mShort := Utf8Marker(#$E6#$9D#$A5#$E8#$87#$AA);
  Result := Pos(mShort, AText);
end;

function FromMarkerLength(const AText: string; APos: Integer): Integer;
var
  mFull, mShort: string;
begin
  mFull := Utf8Marker(#$E6#$9D#$A5#$E8#$87#$AA#$E4#$BA#$8E);
  if (APos > 0) and (Copy(AText, APos, Length(mFull)) = mFull) then
    Exit(Length(mFull));
  if (APos > 0) and (Copy(AText, APos, Length('来自于')) = '来自于') then
    Exit(Length('来自于'));
  mShort := Utf8Marker(#$E6#$9D#$A5#$E8#$87#$AA);
  if (APos > 0) and (Copy(AText, APos, Length(mShort)) = mShort) then
    Exit(Length(mShort));
  Result := 0;
end;

procedure StripLeadingLocNoise(var S: string);
begin
  S := Trim(S);
  while (S <> '') and (CharInSet(S[1], [' ', #9]) or (S[1] = ':') or (S[1] = WideChar($FF1A))) do
    Delete(S, 1, 1);
end;

procedure SplitLocationTokens(const AText: string; ATokens: TStringList);
var
  i: Integer;
  ch: Char;
  token: string;
begin
  ATokens.Clear;
  token := '';
  i := 1;
  while i <= Length(AText) do
  begin
    ch := AText[i];
    if CharInSet(ch, [' ', #9, #13, #10]) then
    begin
      if token <> '' then
      begin
        ATokens.Add(token);
        token := '';
      end;
    end
    else
      token := token + ch;
    Inc(i);
  end;
  if token <> '' then
    ATokens.Add(token);
end;

procedure ParseIpipLocationTokens(const ATokens: TStringList; var AInfo: TExternalIpInfo);
var
  n: Integer;
begin
  n := ATokens.Count;
  if n <= 0 then
    Exit;
  AInfo.Country := ATokens[0];
  if n = 1 then
    Exit;
  if n = 2 then
  begin
    AInfo.Isp := NormalizeIspName(ATokens[1]);
    Exit;
  end;
  if n = 3 then
  begin
    AInfo.Region := ATokens[1];
    AInfo.Isp := NormalizeIspName(ATokens[2]);
    Exit;
  end;
  AInfo.Region := ATokens[1];
  AInfo.City := ATokens[2];
  AInfo.Isp := NormalizeIspName(ATokens[n - 1]);
  if n > 4 then
    AInfo.Area := ATokens[3];
end;

function ParseIpipMyIpBody(const ABody: string; out AInfo: TExternalIpInfo): Boolean;
var
  body, locPart, tail: string;
  pFrom, markerLen, ipPos: Integer;
  tokens: TStringList;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  body := Trim(ABody);
  if body = '' then
    Exit;
  AInfo.Ip := ExtractFirstIpv4FromText(body);
  if not IsValidPublicIpv4(AInfo.Ip) then
    Exit;
  ipPos := Pos(AInfo.Ip, body);
  if ipPos > 0 then
    tail := Trim(Copy(body, ipPos + Length(AInfo.Ip), MaxInt))
  else
    tail := '';
  StripLeadingLocNoise(tail);
  pFrom := FindIpipFromPos(tail);
  if pFrom > 0 then
    locPart := Copy(tail, pFrom, MaxInt)
  else
  begin
    pFrom := FindIpipFromPos(body);
    if pFrom > 0 then
      locPart := Copy(body, pFrom, MaxInt)
    else
      locPart := tail;
  end;
  markerLen := FromMarkerLength(locPart, 1);
  if markerLen > 0 then
    locPart := Copy(locPart, markerLen + 1, MaxInt);
  StripLeadingLocNoise(locPart);
  if locPart <> '' then
  begin
    tokens := TStringList.Create;
    try
      SplitLocationTokens(locPart, tokens);
      ParseIpipLocationTokens(tokens, AInfo);
    finally
      tokens.Free;
    end;
  end;
  AInfo.Ip := ExtractFirstIpv4FromText(body);
  Result := IsValidPublicIpv4(AInfo.Ip);
end;

function ParseIpipMyIpResponse(const AResponse: TNetHttpResponse;
  out AInfo: TExternalIpInfo): Boolean;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  if AResponse.StatusCode <> 200 then
    Exit;
  if Trim(AResponse.BodyText) = '' then
    Exit;
  Result := ParseIpipMyIpBody(AResponse.BodyText, AInfo);
end;

procedure ApplyCityCoords(var AInfo: TExternalIpInfo);
var
  lat, lon: Double;
begin
  if not IpCityCoordsLookup(AInfo.City, AInfo.Region, lat, lon) then
    Exit;
  AInfo.Latitude := FloatToStrF(lat, ffFixed, 15, 4);
  AInfo.Longitude := FloatToStrF(lon, ffFixed, 15, 4);
end;

function ResolveExternalIpInfo(out AInfo: TExternalIpInfo): Boolean;
var
  req: TNetHttpRequest;
  resp: TNetHttpResponse;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  req.Url := cIpipMyIpUrl;
  req.Kind := hkText;
  req.SaveToFile := '';
  req.Options := TNetHttpWorker.DefaultOptions;
  req.UserData := 0;
  resp := TNetHttpWorker.ExecuteSync(req);
  if not ParseIpipMyIpResponse(resp, AInfo) then
    Exit;
  ApplyCityCoords(AInfo);
  FillExternalIpGeoDefaults(AInfo);
  Result := True;
end;

end.
