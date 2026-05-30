unit MemInfoNwInfo;

{
  通过 NwInfoRunner 调用 nwinfox86.exe --sys --smbios=16,17 获取内存与 SMBIOS 信息。
}

interface

uses
  SysUtils, MemInfoTypes;

function MemTryLoadFromNwInfo(out AInfo: TMemStaticInfo): Boolean;

implementation

uses
  Windows, Classes, Math, StrUtils, NwInfoRunner, NwInfoParse;

type
  TType17Rec = record
    BankLocator: string;
    DeviceLocator: string;
    DeviceSize: UInt64;
    DeviceType: string;
    SpeedMts: Cardinal;
    Manufacturer: string;
  end;

  TType17ModuleList = array of TType17Rec;

function MemNwIsMeaningfulText(const AText: string): Boolean;
begin
  Result := (AText <> '') and (AText <> '0000');
end;

procedure MemNwClearType17(var ARec: TType17Rec);
begin
  FillChar(ARec, SizeOf(ARec), 0);
end;

function MemNwLocatorKey(const ARec: TType17Rec): string;
begin
  Result := UpperCase(Trim(ARec.BankLocator)) + '|' + UpperCase(Trim(ARec.DeviceLocator));
  if Result = '|' then
    Result := '';
end;

function MemNwParseChannelIndex(const ABankLocator: string): Integer;
var
  s, token: string;
  i, p: Integer;
begin
  Result := -1;
  s := UpperCase(Trim(ABankLocator));
  if s = '' then
    Exit;
  p := Pos('CHANNEL', s);
  if p > 0 then
  begin
    token := Trim(Copy(s, p + Length('CHANNEL'), MaxInt));
    if token = '' then
      Exit;
    if Length(token) = 1 then
    begin
      Result := Ord(token[1]) - Ord('A');
      if (Result >= 0) and (Result <= 25) then
        Exit;
    end;
    if TryStrToInt(token, Result) then
      Exit;
  end;
  for i := Length(s) downto 1 do
  begin
    if (s[i] >= 'A') and (s[i] <= 'Z') then
    begin
      Result := Ord(s[i]) - Ord('A');
      Exit;
    end;
  end;
end;

function MemNwParseDimmIndex(const ADeviceLocator: string): Integer;
var
  s: string;
  i, n: Integer;
begin
  Result := -1;
  s := UpperCase(Trim(ADeviceLocator));
  if s = '' then
    Exit;
  if TryStrToInt(Trim(StringReplace(s, 'DIMM', '', [rfIgnoreCase])), n) then
  begin
    Result := n;
    Exit;
  end;
  i := Pos('DIMM', s);
  if i > 0 then
  begin
    s := Trim(Copy(s, i + 4, MaxInt));
    if TryStrToInt(s, n) then
    begin
      Result := n;
      Exit;
    end;
    if (s <> '') and (s[1] >= 'A') and (s[1] <= 'Z') and (Length(s) >= 2) then
    begin
      if TryStrToInt(Copy(s, 2, MaxInt), n) then
        Result := Max(0, n - 1);
    end;
  end;
end;

function MemNwCountDistinctChannels(const AType17List: TType17ModuleList): Integer;
var
  channels: TStringList;
  i, chIdx: Integer;
begin
  channels := TStringList.Create;
  try
    channels.Sorted := True;
    channels.Duplicates := dupIgnore;
    for i := 0 to High(AType17List) do
    begin
      chIdx := MemNwParseChannelIndex(AType17List[i].BankLocator);
      if chIdx >= 0 then
        channels.Add(IntToStr(chIdx));
    end;
    Result := channels.Count;
    if Result = 0 then
      Result := 1;
  finally
    channels.Free;
  end;
end;

function MemNwResolvePhysicalSlotIndex(const ARec: TType17Rec; ASlotCount, ADimmsPerChannel: Integer): Integer;
var
  channelIdx, dimmIdx: Integer;
begin
  Result := 0;
  channelIdx := MemNwParseChannelIndex(ARec.BankLocator);
  dimmIdx := MemNwParseDimmIndex(ARec.DeviceLocator);
  if (channelIdx < 0) or (dimmIdx < 0) then
    Exit;
  if ADimmsPerChannel <= 0 then
    ADimmsPerChannel := 1;
  Result := dimmIdx + channelIdx * ADimmsPerChannel + 1;
  if (ASlotCount > 0) and (Result > Integer(ASlotCount)) then
    Result := 0;
end;

function MemNwFindType17ByKey(const AList: TType17ModuleList; const AKey: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  if AKey = '' then
    Exit;
  for i := 0 to High(AList) do
    if MemNwLocatorKey(AList[i]) = AKey then
      Exit(i);
end;

procedure MemNwStoreType17(const ARec: TType17Rec; var AList: TType17ModuleList);
var
  key: string;
  idx: Integer;
begin
  key := MemNwLocatorKey(ARec);
  if key = '' then
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := ARec;
    Exit;
  end;
  idx := MemNwFindType17ByKey(AList, key);
  if idx < 0 then
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := ARec;
  end
  else if (ARec.DeviceSize > 0) and (AList[idx].DeviceSize = 0) then
    AList[idx] := ARec
  else if ARec.DeviceSize > AList[idx].DeviceSize then
    AList[idx] := ARec;
end;

function MemNwFormatType17Detail(const ARec: TType17Rec): string;
var
  detailText: string;
begin
  Result := '';
  if ARec.DeviceSize = 0 then
    Exit;
  detailText := '';
  if MemNwIsMeaningfulText(ARec.DeviceType) and (ARec.SpeedMts > 0) then
    detailText := ARec.DeviceType + '-' + IntToStr(ARec.SpeedMts) + 'MT/s '
  else if MemNwIsMeaningfulText(ARec.DeviceType) then
    detailText := ARec.DeviceType + ' '
  else if ARec.SpeedMts > 0 then
    detailText := IntToStr(ARec.SpeedMts) + 'MT/s ';
  detailText := detailText + MemFormatBytes(ARec.DeviceSize);
  if MemNwIsMeaningfulText(ARec.Manufacturer) then
    detailText := detailText + ' ' + ARec.Manufacturer;
  Result := Trim(detailText);
end;

function MemNwFormatSlotLine(const ARec: TType17Rec; ASlotIndex: Integer): string;
var
  detailText: string;
begin
  detailText := MemNwFormatType17Detail(ARec);
  if detailText = '' then
    Result := '卡槽' + IntToStr(ASlotIndex) + '：' + cMemDash
  else
    Result := '卡槽' + IntToStr(ASlotIndex) + '：' + detailText;
end;

procedure MemNwBuildSlotModules(const AType17List: TType17ModuleList; var AInfo: TMemStaticInfo);
var
  i, slotCount, channelCount, dimmsPerChannel, slotIdx: Integer;
  slotRecs: array of TType17Rec;
  lineText: string;
begin
  if AInfo.Modules = nil then
    AInfo.Modules := TStringList.Create
  else
    AInfo.Modules.Clear;
  slotCount := AInfo.SlotCount;
  if slotCount = 0 then
    slotCount := Length(AType17List);
  if slotCount = 0 then
    Exit;
  SetLength(slotRecs, slotCount);
  for i := 0 to slotCount - 1 do
    MemNwClearType17(slotRecs[i]);
  channelCount := MemNwCountDistinctChannels(AType17List);
  dimmsPerChannel := slotCount div channelCount;
  if dimmsPerChannel <= 0 then
    dimmsPerChannel := 1;
  for i := 0 to High(AType17List) do
  begin
    slotIdx := MemNwResolvePhysicalSlotIndex(AType17List[i], slotCount, dimmsPerChannel);
    if slotIdx <= 0 then
      Continue;
    Dec(slotIdx);
    if (AType17List[i].DeviceSize > slotRecs[slotIdx].DeviceSize) or
      (slotRecs[slotIdx].DeviceSize = 0) then
      slotRecs[slotIdx] := AType17List[i];
  end;
  for i := 0 to slotCount - 1 do
  begin
    lineText := MemNwFormatSlotLine(slotRecs[i], i + 1);
    AInfo.Modules.Add(lineText);
  end;
end;

procedure MemNwFlushType17(const ARec: TType17Rec; var AType17List: TType17ModuleList);
begin
  MemNwStoreType17(ARec, AType17List);
end;

procedure MemParseNwInfoOutput(const AText: string; var AInfo: TMemStaticInfo);
var
  sl: TStringList;
  i: Integer;
  line, key, val: string;
  tableType: Integer;
  capBytes: UInt64;
  slotsVal: Cardinal;
  inPhys: Boolean;
  cur: TType17Rec;
  type17List: TType17ModuleList;
  pct: Integer;
begin
  AInfo.UsagePct := -1;
  AInfo.PhysTotal := 0;
  AInfo.PhysFree := 0;
  AInfo.SpecText := '';
  AInfo.SlotCount := 0;
  if AInfo.Modules <> nil then
    AInfo.Modules.Clear;
  SetLength(type17List, 0);
  MemNwClearType17(cur);
  sl := TStringList.Create;
  try
    sl.Text := AText;
    tableType := -1;
    inPhys := False;
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if line = '' then
        Continue;
      if Pos('Physical Memory:', line) > 0 then
      begin
        inPhys := True;
        Continue;
      end;
      if inPhys then
      begin
        key := NwInfoParseLineKey(line);
        val := NwInfoParseLineValue(line);
        if SameText(key, 'Free') then
        begin
          NwInfoTryParseUInt64(val, AInfo.PhysFree);
          Continue;
        end;
        if SameText(key, 'Total') then
        begin
          NwInfoTryParseUInt64(val, AInfo.PhysTotal);
          inPhys := False;
          Continue;
        end;
        if (key <> '') and (Pos(' ', key) <> 1) then
          inPhys := False;
      end;
      key := NwInfoParseLineKey(line);
      val := NwInfoParseLineValue(line);
      if SameText(key, 'Memory Usage') then
      begin
        val := StringReplace(val, '%', '', [rfReplaceAll]);
        if TryStrToInt(Trim(val), pct) then
          AInfo.UsagePct := EnsureRange(pct, 0, 100);
        Continue;
      end;
      if SameText(key, 'Table Type') then
      begin
        MemNwFlushType17(cur, type17List);
        MemNwClearType17(cur);
        if TryStrToInt(val, tableType) then
        else
          tableType := -1;
        Continue;
      end;
      case tableType of
        16:
          begin
            if SameText(key, 'Number of Slots') then
            begin
              if NwInfoTryParseCardinal(val, slotsVal) and (slotsVal > AInfo.SlotCount) then
                AInfo.SlotCount := slotsVal;
            end
            else if SameText(key, 'Max Capacity') then
            begin
              if NwInfoTryParseUInt64(val, capBytes) and (capBytes > 0) then
                AInfo.SpecText := MemFormatBytes(capBytes);
            end;
          end;
        17:
          begin
            if SameText(key, 'Bank Locator') then
              cur.BankLocator := val
            else if SameText(key, 'Device Locator') then
              cur.DeviceLocator := val
            else if SameText(key, 'Device Size') then
              NwInfoTryParseUInt64(val, cur.DeviceSize)
            else if SameText(key, 'Volatile Size') then
            begin
              if cur.DeviceSize = 0 then
                NwInfoTryParseUInt64(val, cur.DeviceSize);
            end
            else if SameText(key, 'Device Type') then
              cur.DeviceType := val
            else if SameText(key, 'Speed (MT/s)') then
              NwInfoTryParseCardinal(val, cur.SpeedMts)
            else if SameText(key, 'Manufacturer') then
            begin
              if MemNwIsMeaningfulText(val) then
                cur.Manufacturer := val;
            end
            else if SameText(key, 'Module Manufacturer') then
            begin
              if not MemNwIsMeaningfulText(cur.Manufacturer) and MemNwIsMeaningfulText(val) then
                cur.Manufacturer := val;
            end;
          end;
      end;
    end;
    MemNwFlushType17(cur, type17List);
    MemNwBuildSlotModules(type17List, AInfo);
  finally
    sl.Free;
  end;
end;

function MemNwInfoHasStaticData(const AInfo: TMemStaticInfo): Boolean;
begin
  Result := (AInfo.PhysTotal > 0) or (AInfo.SlotCount > 0) or
    ((AInfo.Modules <> nil) and (AInfo.Modules.Count > 0));
end;

function MemTryLoadFromNwInfo(out AInfo: TMemStaticInfo): Boolean;
var
  output: string;
begin
  MemInitStaticInfo(AInfo);
  if not NwInfoRunCapture(cNwInfoArgsMem, output, cNwInfoMarkerSmbios) then
    Exit(False);
  MemParseNwInfoOutput(output, AInfo);
  Result := MemNwInfoHasStaticData(AInfo);
end;

end.
