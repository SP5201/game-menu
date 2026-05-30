unit NetInfoNwInfo;

{
  通过 NwInfoRunner 调用 nwinfox86.exe --net=active,phys 获取网卡信息并解析。
  字段名参考 libnw/network.c NW_Network。
}

interface

uses
  SysUtils, NetInfoTypes;

function NetTryQueryFromNwInfo(out AInfo: TNetAdapterInfo): Boolean;

implementation

uses
  Classes, NwInfoRunner, NwInfoParse;

type
  TNetNwIfaceRec = record
    Name: string;
    TypeText: string;
    Mac: string;
    LinkSpeedBps: UInt64;
    SentOctetsText: string;
    ReceivedOctetsText: string;
    IsEthernet: Boolean;
  end;

  TNetNwIfaceArray = array of TNetNwIfaceRec;

procedure NetNwClearIface(var ARec: TNetNwIfaceRec);
begin
  FillChar(ARec, SizeOf(ARec), 0);
end;

function NetNwTryParseLinkSpeedBps(const AText: string; out AValue: UInt64): Boolean;
begin
  Result := NwInfoTryParseUInt64(AText, AValue) and (AValue > 0);
end;

procedure NetNwSetLinkSpeedBps(var ARec: TNetNwIfaceRec; const AText: string);
var
  bps: UInt64;
begin
  if not NetNwTryParseLinkSpeedBps(AText, bps) then
    Exit;
  ARec.LinkSpeedBps := bps;
end;

function NetNwPickBestIface(const AList: TNetNwIfaceArray): Integer;
var
  i, bestIdx: Integer;
  score, bestScore: Integer;
begin
  bestIdx := -1;
  bestScore := -1;
  for i := Low(AList) to High(AList) do
  begin
    if AList[i].Name = '' then
      Continue;
    score := 0;
    if AList[i].IsEthernet then
      Inc(score, 4);
    if (bestIdx < 0) or (score > bestScore) then
    begin
      bestScore := score;
      bestIdx := i;
    end;
  end;
  Result := bestIdx;
end;

procedure NetNwFlushIface(const ARec: TNetNwIfaceRec; var AList: TNetNwIfaceArray);
begin
  if ARec.Name = '' then
    Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := ARec;
end;

procedure NetParseNwInfoOutput(const AText: string; out AInfo: TNetAdapterInfo);
var
  sl: TStringList;
  i, pickIdx: Integer;
  line, key, val: string;
  cur: TNetNwIfaceRec;
  ifaces: TNetNwIfaceArray;
begin
  NetInitAdapterInfo(AInfo);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    NetNwClearIface(cur);
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if line = '' then
        Continue;
      key := NwInfoParseLineKey(line);
      if key = '' then
        Continue;
      val := NwInfoParseLineValue(line);

      if SameText(key, 'Network Adapter') then
      begin
        NetNwFlushIface(cur, ifaces);
        NetNwClearIface(cur);
        Continue;
      end;

      if SameText(key, 'Description') then
      begin
        if cur.Name <> '' then
        begin
          NetNwFlushIface(cur, ifaces);
          NetNwClearIface(cur);
        end;
        cur.Name := val;
      end
      else if SameText(key, 'Type') then
      begin
        cur.TypeText := NetFormatAdapterTypeFromNwType(val);
        cur.IsEthernet := SameText(val, 'Ethernet');
      end
      else if SameText(key, 'MAC Address') then
        cur.Mac := val
      else if SameText(key, 'Receive Link Speed') then
      begin
        if val <> '' then
          NetNwSetLinkSpeedBps(cur, val);
      end
      else if SameText(key, 'Transmit Link Speed') then
      begin
        if (cur.LinkSpeedBps = 0) and (val <> '') then
          NetNwSetLinkSpeedBps(cur, val);
      end
      else if SameText(key, 'Received (Octets)') then
        cur.ReceivedOctetsText := val
      else if SameText(key, 'Sent (Octets)') then
        cur.SentOctetsText := val;
    end;
    NetNwFlushIface(cur, ifaces);

    pickIdx := NetNwPickBestIface(ifaces);
    if pickIdx < 0 then
      Exit;

    AInfo.Name := ifaces[pickIdx].Name;
    if ifaces[pickIdx].TypeText <> '' then
      AInfo.TypeText := ifaces[pickIdx].TypeText
    else
      AInfo.TypeText := cNetDash;
    if ifaces[pickIdx].Mac <> '' then
      AInfo.Mac := ifaces[pickIdx].Mac
    else
      AInfo.Mac := cNetDash;
    AInfo.LinkSpeedText := NetFormatLinkSpeedMbpsText(ifaces[pickIdx].LinkSpeedBps);
    if ifaces[pickIdx].SentOctetsText <> '' then
      AInfo.SentOctetsText := ifaces[pickIdx].SentOctetsText
    else
      AInfo.SentOctetsText := cNetDash;
    if ifaces[pickIdx].ReceivedOctetsText <> '' then
      AInfo.ReceivedOctetsText := ifaces[pickIdx].ReceivedOctetsText
    else
      AInfo.ReceivedOctetsText := cNetDash;
  finally
    sl.Free;
  end;
end;

function NetNwInfoHasData(const AInfo: TNetAdapterInfo): Boolean;
begin
  Result := (AInfo.Name <> '') and (AInfo.Name <> cNetDash);
end;

function NetTryQueryFromNwInfo(out AInfo: TNetAdapterInfo): Boolean;
var
  output: string;
begin
  NetInitAdapterInfo(AInfo);
  if not NwInfoRunCapture(cNwInfoArgsNet, output, cNwInfoMarkerNet) then
    Exit(False);
  NetParseNwInfoOutput(output, AInfo);
  Result := NetNwInfoHasData(AInfo);
end;

end.
