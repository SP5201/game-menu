unit MftReader;

interface

uses
  Windows, SysUtils, Classes, Generics.Collections, Core.Model, Core.Memory;

type
  TMftBuildProgressProc = reference to procedure(const AStatus: string);

  TMftApplyUsnStats = record
    FilesAdded: Integer;
    FilesRemoved: Integer;
    FilesUpdated: Integer;
  end;

function MftIsNtfsVolume(const ADriveLetter: Char): Boolean;
function MftIsSubstDrive(const ADriveLetter: Char): Boolean;
function MftShouldMonitorDrive(const ADriveLetter: Char): Boolean;
procedure EnableVolumeScanPrivileges;
function MftOpenVolumeForJournal(const ADriveLetter: Char): THandle;
function MftBuildFromDrive(const ADriveLetter: Char; ADriveIndex: Byte;
  var ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AExcludedFrn: TDictionary<UInt64, Byte>; const AOnProgress: TMftBuildProgressProc;
  out AFailReason: string): Boolean;
procedure MftRebuildFolderFrnMap(const ADB: TEverythingDB;
  AFrnToFolder: TDictionary<UInt64, Cardinal>);
function MftRebuildFileFrnMapFromUsn(const ADriveLetter: Char; ADriveIndex: Byte;
  const ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray): Boolean;
procedure MftBuildFileParentNameMap(const ADB: TEverythingDB; AMap: TDictionary<AnsiString, Integer>);
function MftApplyUsnRecords(var ADB: TEverythingDB; ADriveIndex: Byte;
  const ARecords: TUsnJournalRecordArray; AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>;
  AExcludedFrn: TDictionary<UInt64, Byte>; var AFileFrnKeys: TFileFrnKeyArray;
  AFileLookup: TDictionary<AnsiString, Integer>; out AStats: TMftApplyUsnStats;
  var AChanges: TIndexHitChangeArray): Boolean;

implementation

function MftWideNameToUtf8Lower(const AName: string): AnsiString;
var
  utf8: AnsiString;
begin
  if AName = '' then
    Exit('');
  utf8 := WideToUtf8(PWideChar(AName), Length(AName));
  if utf8 = '' then
    Exit('');
  Result := Utf8ToLowerAnsi(PAnsiChar(utf8));
end;

function QueryDosDeviceW(lpDeviceName, lpTargetPath: PWideChar; ucchMax: DWORD): DWORD; stdcall;
  external kernel32 name 'QueryDosDeviceW';

const
  FILE_DEVICE_FILE_SYSTEM = $00000009;
  METHOD_BUFFERED = 0;
  METHOD_NEITHER = 3;
  FILE_ANY_ACCESS = 0;
  FSCTL_GET_NTFS_VOLUME_DATA = (FILE_DEVICE_FILE_SYSTEM shl 16) or
    (FILE_ANY_ACCESS shl 14) or (25 shl 2) or METHOD_BUFFERED;
  FSCTL_GET_NTFS_FILE_RECORD = (FILE_DEVICE_FILE_SYSTEM shl 16) or
    (FILE_ANY_ACCESS shl 14) or (26 shl 2) or METHOD_BUFFERED;
  FSCTL_ENUM_USN_DATA = (FILE_DEVICE_FILE_SYSTEM shl 16) or (FILE_ANY_ACCESS shl 14) or
    (45 shl 2) or METHOD_NEITHER;
  cMftIoctlScanSlop = 64;
  cNtfsRootFrn = UInt64(5);
  cUsnEnumBufferSize = 256 * 1024;
  SE_PRIVILEGE_ENABLED = $00000002;

  ATTR_STANDARD_INFORMATION = $10;
  ATTR_FILE_NAME = $30;
  ATTR_END = $FFFFFFFF;

  MFT_RECORD_IN_USE = $0001;
  MFT_RECORD_IS_DIRECTORY = $0002;
  FILE_NAME_POSIX = 0;
  FILE_NAME_WIN32 = 1;
  FILE_NAME_DOS = 2;
  FILE_NAME_WIN32_AND_DOS = 3;

  cMftReadChunk = 8 * 1024 * 1024;
  cFaDirectory = $00000010;
  cFaReparsePoint = $00000400;
  INVALID_SET_FILE_POINTER = DWORD(-1);

type
  TNTFS_VOLUME_DATA_BUFFER = packed record
    VolumeSerialNumber: Int64;
    NumberSectors: Int64;
    TotalClusters: Int64;
    FreeClusters: Int64;
    TotalReserved: Int64;
    BytesPerSector: DWORD;
    BytesPerCluster: DWORD;
    BytesPerFileRecordSegment: DWORD;
    ClustersPerFileRecordSegment: DWORD;
    MftValidDataLength: Int64;
    MftStartLcn: Int64;
    Mft2StartLcn: Int64;
    MftZoneStart: Int64;
    MftZoneEnd: Int64;
  end;

  TMftRecordHeader = packed record
    Signature: array[0..3] of AnsiChar;
    UsaOffset: Word;
    UsaCount: Word;
    Lsn: Int64;
    SeqNumber: Word;
    LinkCount: Word;
    FirstAttrOffset: Word;
    Flags: Word;
    BytesInUse: DWORD;
    BytesAllocated: DWORD;
    BaseFileRecord: Int64;
    NextAttributeId: Word;
    Padding: Word;
    MftRecordNumber: Word;
    Padding2: Word;
  end;
  PMftRecordHeader = ^TMftRecordHeader;

  TAttrRecord = packed record
    AttrType: DWORD;
    RecordLength: DWORD;
    Nonresident: Byte;
    NameLength: Byte;
    NameOffset: Word;
    Flags: Word;
    AttributeId: Word;
  end;
  PAttrRecord = ^TAttrRecord;

  TResidentAttr = packed record
    ValueLength: DWORD;
    ValueOffset: Word;
    Flags: Word;
  end;
  PResidentAttr = ^TResidentAttr;

  TFileNameAttr = packed record
    ParentDirectory: Int64;
    CreationTime: Int64;
    ChangeTime: Int64;
    LastWriteTime: Int64;
    LastAccessTime: Int64;
    AllocatedSize: Int64;
    RealSize: Int64;
    Flags: DWORD;
    EaLength: DWORD;
    FileNameLength: Byte;  // NTFS: character count at offset 0x40
    Namespace: Byte;       // NTFS: namespace id at offset 0x41
  end;
  PFileNameAttr = ^TFileNameAttr;

  TRawMftItem = record
    FRN: UInt64;
    ParentFRN: UInt64;
    NameOffset: Cardinal;
    DateModified: Cardinal;
    Attributes: Word;
    SizeLow: Cardinal;
    IsDirectory: Boolean;
    DriveIndex: Byte;
    Excluded: Boolean;
  end;

  TUsnRecordHeader = packed record
    RecordLength: DWORD;
    MajorVersion: Word;
    MinorVersion: Word;
    FileReferenceNumber: Int64;
    ParentFileReferenceNumber: Int64;
    Usn: Int64;
    TimeStamp: Int64;
    Reason: DWORD;
    SourceInfo: DWORD;
    SecurityId: DWORD;
    FileAttributes: DWORD;
    FileNameLength: Word;
    FileNameOffset: Word;
  end;
  PUsnRecordHeader = ^TUsnRecordHeader;

  TUsnTempItem = record
    FRN: UInt64;
    ParentFRN: UInt64;
    NamePoolOffset: Cardinal;
    DateModified: Cardinal;
    FileAttributes: DWORD;
    IsDirectory: Boolean;
    DriveIndex: Byte;
    Excluded: Boolean;
  end;

function IsSystemFolderName(const ANameUtf8: PAnsiChar): Boolean;
begin
  Result := (AnsiStrComp(ANameUtf8, '$Extend') = 0) or
    (AnsiStrComp(ANameUtf8, '$RECYCLE.BIN') = 0) or
    (AnsiStrComp(ANameUtf8, '$Recycle.Bin') = 0) or
    (AnsiStrComp(ANameUtf8, 'System Volume Information') = 0);
end;

function Win32ErrorText: string;
begin
  Result := 'Win32=' + IntToStr(GetLastError);
end;

function Win32ErrorTextFrom(const AErr: DWORD): string;
begin
  if AErr = 0 then
    Result := 'Win32=0（可能权限不足或 IOCTL 未返回错误码）'
  else
    Result := 'Win32=' + IntToStr(AErr);
end;

function DriveOpenFailHint(const ADriveLetter: Char): string;
var
  root: string;
  dt: UINT;
begin
  if MftIsSubstDrive(ADriveLetter) then
    Exit('SUBST 映射盘无法裸读（内容与源盘重复，已跳过）');
  root := ADriveLetter + ':\';
  dt := GetDriveType(PChar(root));
  case dt of
    DRIVE_REMOTE:
      Result := '网络映射盘无法裸读 $MFT';
    DRIVE_CDROM:
      Result := '光驱不支持裸卷读取';
    DRIVE_REMOVABLE:
      Result := '可移动设备未就绪或不支持裸读';
    DRIVE_NO_ROOT_DIR:
      Result := '驱动器不存在';
  else
    Result := '无法打开裸卷（需要管理员权限或卷被占用）';
  end;
end;

function OpenRawVolume(const ADriveLetter: Char): THandle;
var
  path: string;
begin
  path := '\\.\' + ADriveLetter + ':';
  Result := CreateFile(PChar(path), GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Result = INVALID_HANDLE_VALUE then
    Result := CreateFile(PChar(path), 0, FILE_SHARE_READ or FILE_SHARE_WRITE, nil,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
end;

function ResolveFileRecordSize(const AData: TNTFS_VOLUME_DATA_BUFFER): DWORD;
var
  clusters: Integer;
begin
  Result := AData.BytesPerFileRecordSegment;
  if Result >= 256 then
    Exit;
  clusters := Integer(AData.ClustersPerFileRecordSegment);
  if clusters > 0 then
    Result := DWORD(clusters) * AData.BytesPerCluster
  else if clusters < 0 then
    Result := DWORD(1) shl DWORD(-clusters)
  else
    Result := 1024;
end;

function ResolveMftScanSize(const AData: TNTFS_VOLUME_DATA_BUFFER; ARecordSize: DWORD): Int64;
begin
  Result := AData.MftValidDataLength;
  if Result <= 0 then
    Result := AData.TotalClusters * AData.BytesPerCluster;
  if Result <= 0 then
    Result := Int64(ARecordSize) * 1024 * 1024;
end;

function MftRecordSignatureValid(ARecord: PByte): Boolean;
var
  hdr: PMftRecordHeader;
begin
  Result := False;
  if ARecord = nil then
    Exit;
  hdr := PMftRecordHeader(ARecord);
  Result := (hdr.Signature[0] = 'F') and (hdr.Signature[1] = 'I') and
    (hdr.Signature[2] = 'L') and (hdr.Signature[3] = 'E');
end;

function ParseFileNameAttr(AValue: PByte; AValueLen: DWORD; ADriveIndex: Byte;
  var ADB: TEverythingDB; out AItem: TRawMftItem): Boolean; forward;
function ParseMftRecord(ARecord: PByte; ARecordSize, ASectorSize: DWORD; ARecordIndex: Int64;
  ADriveIndex: Byte; var ADB: TEverythingDB; out AItem: TRawMftItem): Boolean; forward;

function LocateMftRecordInBuffer(ABuf: PByte; ABufLen: DWORD): PByte;
var
  i: DWORD;
begin
  Result := nil;
  if (ABuf = nil) or (ABufLen < 4) then
    Exit;
  i := 0;
  while i + 4 <= ABufLen do
  begin
    if MftRecordSignatureValid(PByte(NativeUInt(ABuf) + i)) then
      Exit(PByte(NativeUInt(ABuf) + i));
    Inc(i);
  end;
end;

function TryParseMftRecordByIoctl(AHandle: THandle; ARecordIndex: Int64; ARecordSize,
  ASectorSize: DWORD; ADriveIndex: Byte; var ADB: TEverythingDB; out AItem: TRawMftItem;
  AFetchBuf: PByte; AFetchBufSize: DWORD): Boolean;
var
  frnIn: Int64;
  bytesReturned: DWORD;
  recPtr: PByte;
begin
  Result := False;
  FillChar(AItem, SizeOf(AItem), 0);
  if (AHandle = INVALID_HANDLE_VALUE) or (AFetchBuf = nil) or (ARecordSize = 0) then
    Exit;
  frnIn := ARecordIndex and Int64($0000FFFFFFFFFFFF);
  if not DeviceIoControl(AHandle, FSCTL_GET_NTFS_FILE_RECORD, @frnIn, SizeOf(frnIn),
    AFetchBuf, AFetchBufSize, bytesReturned, nil) then
    Exit;
  if bytesReturned <= SizeOf(DWORD) then
    Exit;
  recPtr := LocateMftRecordInBuffer(AFetchBuf, bytesReturned);
  if recPtr = nil then
    Exit;
  Result := ParseMftRecord(recPtr, ARecordSize, ASectorSize, ARecordIndex, ADriveIndex, ADB, AItem);
end;

function NtfsFrnNormalize(const AFrn: UInt64): UInt64; overload;
begin
  { NTFS FILE_REFERENCE：低 48 位为 MFT 记录号，高 16 位为序列号（与 $FILE_NAME.ParentDirectory 一致） }
  Result := AFrn and UInt64($0000FFFFFFFFFFFF);
end;

function NtfsFrnNormalize(const AFrn: Int64): UInt64; overload;
begin
  Result := NtfsFrnNormalize(UInt64(AFrn));
end;

function MftRecordFrn(ARecordIndex: Int64; hdr: PMftRecordHeader): UInt64;
var
  baseRef: Int64;
begin
  baseRef := hdr.BaseFileRecord;
  if baseRef <> 0 then
    Exit(UInt64(baseRef));
  Result := UInt64(ARecordIndex) or (UInt64(hdr.SeqNumber) shl 48);
end;

function NtfsFrnSegmentNumber(const AFrn: UInt64): UInt64;
begin
  { 父目录查找按 MFT 记录号匹配（忽略序列号），与 ParentDirectory 低 48 位对齐 }
  Result := NtfsFrnNormalize(AFrn);
end;

function NtfsFrnIsRoot(const AFrn: UInt64): Boolean;
begin
  Result := NtfsFrnNormalize(AFrn) = cNtfsRootFrn;
end;

function FrnMapKey(ADriveIndex: Byte; AFrn: UInt64): UInt64;
begin
  Result := (UInt64(ADriveIndex) shl 56) or NtfsFrnNormalize(AFrn);
end;

function FrnSegmentKey(ADriveIndex: Byte; AFrn: UInt64): UInt64;
begin
  Result := (UInt64(ADriveIndex) shl 56) or NtfsFrnSegmentNumber(AFrn);
end;

procedure BuildSegmentFolderMap(AFrnToFolder: TDictionary<UInt64, Cardinal>;
  ASegToFolder: TDictionary<UInt64, Cardinal>);
var
  pair: TPair<UInt64, Cardinal>;
  drive: Byte;
  frn: UInt64;
begin
  ASegToFolder.Clear;
  for pair in AFrnToFolder do
  begin
    drive := Byte(pair.Key shr 56);
    frn := pair.Key and UInt64($00FFFFFFFFFFFFFF);
    ASegToFolder.AddOrSetValue(FrnSegmentKey(drive, frn), pair.Value);
  end;
end;

procedure SetSegmentFolderEntry(ASegToFolder: TDictionary<UInt64, Cardinal>;
  ADriveIndex: Byte; AFrn: UInt64; AFolderOff: Cardinal);
begin
  if ASegToFolder = nil then
    Exit;
  ASegToFolder.AddOrSetValue(FrnSegmentKey(ADriveIndex, AFrn), AFolderOff);
end;

procedure RemoveSegmentFolderEntry(ASegToFolder: TDictionary<UInt64, Cardinal>;
  ADriveIndex: Byte; AFrn: UInt64);
begin
  if ASegToFolder = nil then
    Exit;
  ASegToFolder.Remove(FrnSegmentKey(ADriveIndex, AFrn));
end;

function ResolveParentFolderOffset(ADriveIndex: Byte; AParentFRN: UInt64;
  AFrnToFolder, ASegToFolder: TDictionary<UInt64, Cardinal>; out AParentOff: Cardinal): Boolean;
begin
  if NtfsFrnIsRoot(AParentFRN) then
  begin
    AParentOff := cRootParentOffset;
    Exit(True);
  end;
  if AFrnToFolder.TryGetValue(FrnMapKey(ADriveIndex, AParentFRN), AParentOff) then
    Exit(True);
  if (ASegToFolder <> nil) and
    ASegToFolder.TryGetValue(FrnSegmentKey(ADriveIndex, AParentFRN), AParentOff) then
    Exit(True);
  Result := False;
end;

function EnablePrivilege(const APrivilegeName: PChar): Boolean;
var
  hToken: THandle;
  tp: TTokenPrivileges;
  retLen: DWORD;
begin
  Result := False;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, hToken) then
    Exit;
  try
    if not LookupPrivilegeValue(nil, APrivilegeName, tp.Privileges[0].Luid) then
      Exit;
    tp.PrivilegeCount := 1;
    tp.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED;
    AdjustTokenPrivileges(hToken, False, tp, 0, nil, retLen);
    Result := (GetLastError = ERROR_SUCCESS) or (GetLastError = ERROR_NOT_ALL_ASSIGNED);
  finally
    CloseHandle(hToken);
  end;
end;

procedure EnableVolumeScanPrivileges;
begin
  EnablePrivilege('SeBackupPrivilege');
  EnablePrivilege('SeRestorePrivilege');
end;

function MftShouldMonitorDrive(const ADriveLetter: Char): Boolean;
var
  root: string;
begin
  if MftIsSubstDrive(ADriveLetter) then
    Exit(False);
  if not MftIsNtfsVolume(ADriveLetter) then
    Exit(False);
  root := ADriveLetter + ':\';
  Result := GetDriveType(PChar(root)) <> DRIVE_REMOTE;
end;

function IsSystemFolderNameWide(const AName: string): Boolean;
begin
  Result := SameText(AName, '$Extend') or SameText(AName, '$RECYCLE.BIN') or
    SameText(AName, '$Recycle.Bin') or SameText(AName, 'System Volume Information');
end;

function OpenVolumeHandle(const ADriveLetter: Char): THandle;
var
  path: string;
begin
  path := '\\.\' + ADriveLetter + ':';
  Result := CreateFile(PChar(path), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Result = INVALID_HANDLE_VALUE then
    Result := CreateFile(PChar(path), 0, FILE_SHARE_READ or FILE_SHARE_WRITE, nil,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
end;

function MftOpenVolumeForJournal(const ADriveLetter: Char): THandle;
var
  path: string;
begin
  path := '\\.\' + ADriveLetter + ':';
  Result := CreateFile(PChar(path), GENERIC_READ or GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
  if Result = INVALID_HANDLE_VALUE then
    Result := CreateFile(PChar(path), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
      nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Result = INVALID_HANDLE_VALUE then
    Result := OpenVolumeHandle(ADriveLetter);
end;

function SeekVolumeOffset(AHandle: THandle; AOffset: Int64): Boolean;
var
  seekHigh: LongInt;
  lowResult: DWORD;
begin
  seekHigh := LongInt(AOffset shr 32);
  lowResult := SetFilePointer(AHandle, LongInt(AOffset and $FFFFFFFF), @seekHigh, FILE_BEGIN);
  if lowResult = INVALID_SET_FILE_POINTER then
    Result := GetLastError = ERROR_SUCCESS
  else
    Result := True;
end;

function MftIsSubstDrive(const ADriveLetter: Char): Boolean;
var
  device: array[0..MAX_PATH] of Char;
  target: string;
  i: Integer;
begin
  Result := False;
  if QueryDosDeviceW(PWideChar(string(ADriveLetter) + ':'), device, MAX_PATH) = 0 then
    Exit;
  target := string(device);
  if not SameText(Copy(target, 1, 4), '\??\') then
    Exit;
  if Length(target) < 6 then
    Exit;
  i := 5;
  Result := CharInSet(target[i], ['A'..'Z', 'a'..'z']) and (target[i + 1] = ':');
end;

function MftIsNtfsVolume(const ADriveLetter: Char): Boolean;
var
  fsName: array[0..MAX_PATH] of Char;
  root: string;
  maxComp, fsFlags: DWORD;
  dt: UINT;
begin
  root := ADriveLetter + ':\';
  dt := GetDriveType(PChar(root));
  if (dt <> DRIVE_FIXED) and (dt <> DRIVE_REMOVABLE) then
    Exit(False);
  Result := GetVolumeInformation(PChar(root), nil, 0, nil, maxComp, fsFlags,
    PChar(@fsName[0]), DWORD(MAX_PATH)) and SameText(fsName, 'NTFS');
end;

procedure TryApplyUsaFixup(ARecord: PByte; ARecordSize, ASectorSize: DWORD);
var
  hdr: PMftRecordHeader;
  usaOffset, usaCount, sectorSize, i: Word;
  pUsa, pSector: PWord;
begin
  if (ARecord = nil) or (ASectorSize = 0) or not MftRecordSignatureValid(ARecord) then
    Exit;
  hdr := PMftRecordHeader(ARecord);
  usaOffset := hdr.UsaOffset;
  usaCount := hdr.UsaCount;
  if (usaCount < 2) or (Cardinal(usaOffset) >= ARecordSize) then
    Exit;
  sectorSize := ASectorSize;
  pUsa := PWord(PByte(ARecord) + usaOffset);
  for i := 1 to usaCount - 1 do
  begin
    if Cardinal((i - 1) * sectorSize + sectorSize) > ARecordSize then
      Break;
    pSector := PWord(PByte(ARecord) + (i - 1) * sectorSize + sectorSize - 2);
    pSector^ := PWord(NativeInt(pUsa) + i * SizeOf(Word))^;
  end;
end;

function FileNameNamespaceScore(ANamespace: Byte): Integer;
begin
  case ANamespace of
    FILE_NAME_WIN32:
      Result := 0;
    FILE_NAME_POSIX:
      Result := 1;
    FILE_NAME_WIN32_AND_DOS:
      Result := 2;
    FILE_NAME_DOS:
      Result := 3;
  else
    Result := 99;
  end;
end;

function ParseFileNameAttr(AValue: PByte; AValueLen: DWORD; ADriveIndex: Byte;
  var ADB: TEverythingDB; out AItem: TRawMftItem): Boolean;
var
  fn: PFileNameAttr;
  namePtr: PWideChar;
  nameLen: Integer;
  nameOff: Cardinal;
begin
  Result := False;
  FillChar(AItem, SizeOf(AItem), 0);
  if (AValue = nil) or (AValueLen < SizeOf(TFileNameAttr)) then
    Exit;
  fn := PFileNameAttr(AValue);
  if FileNameNamespaceScore(fn.Namespace) >= 99 then
    Exit;
  if fn.FileNameLength = 0 then
    Exit;
  nameLen := fn.FileNameLength;
  if Cardinal(SizeOf(TFileNameAttr) + nameLen * SizeOf(WideChar)) > AValueLen then
    Exit;
  namePtr := PWideChar(PByte(fn) + SizeOf(TFileNameAttr));
  nameOff := AppendWideName(ADB, namePtr, nameLen);
  if nameOff = 0 then
    Exit;
  AItem.ParentFRN := NtfsFrnNormalize(fn.ParentDirectory);
  AItem.NameOffset := nameOff;
  AItem.DateModified := FileTimeToUnixDate(fn.LastWriteTime);
  AItem.SizeLow := DWORD(fn.RealSize);
  AItem.DriveIndex := ADriveIndex;
  AItem.Excluded := IsSystemFolderName(PAnsiChar(@ADB.NamePool[nameOff]));
  Result := True;
end;

function ParseMftRecord(ARecord: PByte; ARecordSize, ASectorSize: DWORD; ARecordIndex: Int64;
  ADriveIndex: Byte; var ADB: TEverythingDB; out AItem: TRawMftItem): Boolean;
var
  hdr: PMftRecordHeader;
  attr: PAttrRecord;
  resident: PResidentAttr;
  valuePtr: PByte;
  offset: DWORD;
  bestItem: TRawMftItem;
  tempItem: TRawMftItem;
  hasName: Boolean;
  bestNameScore: Integer;
  nameScore: Integer;
  fn: PFileNameAttr;
begin
  Result := False;
  FillChar(AItem, SizeOf(AItem), 0);
  FillChar(bestItem, SizeOf(bestItem), 0);
  hasName := False;
  bestNameScore := 99;
  if not MftRecordSignatureValid(ARecord) then
    Exit;
  TryApplyUsaFixup(ARecord, ARecordSize, ASectorSize);
  hdr := PMftRecordHeader(ARecord);
  if (hdr.Flags and MFT_RECORD_IN_USE) = 0 then
    Exit;
  AItem.FRN := MftRecordFrn(ARecordIndex, hdr);
  AItem.IsDirectory := (hdr.Flags and MFT_RECORD_IS_DIRECTORY) <> 0;
  AItem.DriveIndex := ADriveIndex;
  offset := hdr.FirstAttrOffset;
  while offset + SizeOf(TAttrRecord) <= ARecordSize do
  begin
    attr := PAttrRecord(PByte(ARecord) + offset);
    if attr.AttrType = ATTR_END then
      Break;
    if (attr.RecordLength = 0) or (offset + attr.RecordLength > ARecordSize) then
      Break;
    if (attr.AttrType = ATTR_FILE_NAME) and (attr.Nonresident = 0) then
    begin
      resident := PResidentAttr(PByte(attr) + SizeOf(TAttrRecord));
      valuePtr := PByte(attr) + resident.ValueOffset;
      if ParseFileNameAttr(valuePtr, resident.ValueLength, ADriveIndex, ADB, tempItem) then
      begin
        tempItem.FRN := AItem.FRN;
        tempItem.IsDirectory := AItem.IsDirectory;
        fn := PFileNameAttr(valuePtr);
        nameScore := FileNameNamespaceScore(fn.Namespace);
        if (not hasName) or (nameScore < bestNameScore) then
        begin
          bestItem := tempItem;
          bestNameScore := nameScore;
          hasName := True;
        end;
      end;
    end;
    Inc(offset, attr.RecordLength);
  end;
  if not hasName then
    Exit;
  AItem := bestItem;
  Result := True;
end;

procedure MarkExcludedDescendants(var AItems: TArray<TRawMftItem>;
  AExcludedFrn: TDictionary<UInt64, Byte>);
var
  changed: Boolean;
  i: Integer;
  frnKey, parentKey: UInt64;
begin
  repeat
    changed := False;
    for i := 0 to High(AItems) do
    begin
      frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
      parentKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].ParentFRN);
      if AItems[i].Excluded then
      begin
        if AItems[i].IsDirectory then
          if not AExcludedFrn.ContainsKey(frnKey) then
            AExcludedFrn.Add(frnKey, 1);
        Continue;
      end;
      if AExcludedFrn.ContainsKey(parentKey) then
      begin
        AItems[i].Excluded := True;
        if AItems[i].IsDirectory then
          if not AExcludedFrn.ContainsKey(frnKey) then
            AExcludedFrn.Add(frnKey, 1);
        changed := True;
      end;
    end;
  until not changed;
end;

procedure CommitRawItems(var ADB: TEverythingDB; const AItems: TArray<TRawMftItem>;
  AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray);
var
  i: Integer;
  folder: TFolderEntry;
  fileRec: TFileEntry;
  folderOff, parentOff: Cardinal;
  frnKey: UInt64;
  segToFolder: TDictionary<UInt64, Cardinal>;
  nameUtf8: PAnsiChar;
  extPtr: PAnsiChar;
begin
  segToFolder := TDictionary<UInt64, Cardinal>.Create;
  try
  for i := 0 to High(AItems) do
  begin
    if (not AItems[i].IsDirectory) or AItems[i].Excluded then
      Continue;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if AFrnToFolder.ContainsKey(frnKey) then
      Continue;
    GrowFolders(ADB);
    folder.FRN := AItems[i].FRN;
    folder.NamePoolOffset := AItems[i].NameOffset;
    folder.DateModified := AItems[i].DateModified;
    folder.Attributes := AItems[i].Attributes;
    folder.DriveIndex := AItems[i].DriveIndex;
    folder.ParentOffset := cRootParentOffset;
    ADB.Folders[ADB.FolderCount] := folder;
    AFrnToFolder.Add(frnKey, Cardinal(ADB.FolderCount));
    Inc(ADB.FolderCount);
  end;

  BuildSegmentFolderMap(AFrnToFolder, segToFolder);

  for i := 0 to High(AItems) do
  begin
    if (not AItems[i].IsDirectory) or AItems[i].Excluded then
      Continue;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if not AFrnToFolder.TryGetValue(frnKey, folderOff) then
      Continue;
    if ResolveParentFolderOffset(AItems[i].DriveIndex, AItems[i].ParentFRN, AFrnToFolder,
      segToFolder, parentOff) then
      ADB.Folders[folderOff].ParentOffset := parentOff
    else
      ADB.Folders[folderOff].ParentOffset := cRootParentOffset;
  end;

  if ADB.VolumeBaseDate = 0 then
  begin
    for i := 0 to High(AItems) do
      if (not AItems[i].IsDirectory) and (not AItems[i].Excluded) and (AItems[i].DateModified > 0) then
      begin
        ADB.VolumeBaseDate := AItems[i].DateModified;
        Break;
      end;
  end;

  for i := 0 to High(AItems) do
  begin
    if AItems[i].IsDirectory or AItems[i].Excluded then
      Continue;
    if not ResolveParentFolderOffset(AItems[i].DriveIndex, AItems[i].ParentFRN, AFrnToFolder,
      segToFolder, parentOff) then
      parentOff := cRootParentOffset;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if (AFrnToFile <> nil) and AFrnToFile.ContainsKey(frnKey) then
      Continue;
    GrowFiles(ADB);
    fileRec.ParentOffset := parentOff;
    fileRec.NamePoolOffset := AItems[i].NameOffset;
    fileRec.SizeLow := AItems[i].SizeLow;
    fileRec.DateModifiedDelta := UnixDateToDelta(ADB.VolumeBaseDate, AItems[i].DateModified);
    nameUtf8 := PAnsiChar(@ADB.NamePool[AItems[i].NameOffset]);
    extPtr := ExtractExtUtf8(nameUtf8);
    fileRec.ExtID := FindOrAddExt(ADB, extPtr);
    ADB.Files[ADB.FileCount] := fileRec;
    if AFrnToFile <> nil then
      AFrnToFile.Add(frnKey, Cardinal(ADB.FileCount));
    if Length(AFileFrnKeys) <= ADB.FileCount then
      SetLength(AFileFrnKeys, ADB.FileCount + cGrowChunkFiles);
    AFileFrnKeys[ADB.FileCount] := frnKey;
    Inc(ADB.FileCount);
  end;
  finally
    segToFolder.Free;
  end;
end;

procedure MarkExcludedUsnItems(var AItems: TArray<TUsnTempItem>;
  AExcludedFrn: TDictionary<UInt64, Byte>);
var
  changed: Boolean;
  i: Integer;
  frnKey, parentKey: UInt64;
begin
  repeat
    changed := False;
    for i := 0 to High(AItems) do
    begin
      frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
      parentKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].ParentFRN);
      if AItems[i].Excluded then
      begin
        if AItems[i].IsDirectory then
          if not AExcludedFrn.ContainsKey(frnKey) then
            AExcludedFrn.Add(frnKey, 1);
        Continue;
      end;
      if AExcludedFrn.ContainsKey(parentKey) then
      begin
        AItems[i].Excluded := True;
        if AItems[i].IsDirectory then
          if not AExcludedFrn.ContainsKey(frnKey) then
            AExcludedFrn.Add(frnKey, 1);
        changed := True;
      end;
    end;
  until not changed;
end;

function EnumVolumeUsnItems(const ADriveLetter: Char; ADriveIndex: Byte; var ADB: TEverythingDB;
  out AItems: TArray<TUsnTempItem>; out AFailDetail: string): Boolean;
type
  TMftEnumData = packed record
    StartFileReferenceNumber: Int64;
    LowUsn: Int64;
    HighUsn: Int64;
  end;
var
  hVol: THandle;
  enumData: TMftEnumData;
  buffer: array of Byte;
  bytesReturned: DWORD;
  offset, recLen, nameChars, n: Integer;
  rec: PUsnRecordHeader;
  namePtr: PWideChar;
  fileName: string;
  item: TUsnTempItem;
  frn, parentFrn: UInt64;
  lastErr: DWORD;
  ioOk: Boolean;
begin
  Result := False;
  AFailDetail := '';
  SetLength(AItems, 0);
  EnableVolumeScanPrivileges;
  hVol := MftOpenVolumeForJournal(ADriveLetter);
  if hVol = INVALID_HANDLE_VALUE then
  begin
    AFailDetail := DriveOpenFailHint(ADriveLetter);
    Exit;
  end;
  try
    SetLength(buffer, cUsnEnumBufferSize);
    enumData.StartFileReferenceNumber := 0;
    enumData.LowUsn := 0;
    enumData.HighUsn := High(Int64);
    n := 0;
    lastErr := 0;
    repeat
      ioOk := DeviceIoControl(hVol, FSCTL_ENUM_USN_DATA, @enumData, SizeOf(enumData),
        @buffer[0], Length(buffer), bytesReturned, nil);
      if not ioOk then
      begin
        lastErr := GetLastError;
        Break;
      end;
      if bytesReturned < SizeOf(Int64) then
        Break;
      enumData.StartFileReferenceNumber := PInt64(@buffer[0])^;
      if bytesReturned > SizeOf(Int64) then
      begin
        offset := SizeOf(Int64);
        while offset < Integer(bytesReturned) do
        begin
          rec := PUsnRecordHeader(@buffer[offset]);
          recLen := rec.RecordLength;
          if (recLen <= 0) or (offset + recLen > Integer(bytesReturned)) then
            Break;
          if rec.FileNameLength > 0 then
          begin
            namePtr := PWideChar(NativeUInt(rec) + rec.FileNameOffset);
            nameChars := rec.FileNameLength div SizeOf(WideChar);
            if WideToUtf8(namePtr, nameChars) = '' then
              Continue;
            SetString(fileName, namePtr, nameChars);
            frn := UInt64(rec.FileReferenceNumber);
            parentFrn := UInt64(rec.ParentFileReferenceNumber);
            item.FRN := frn;
            item.ParentFRN := parentFrn;
            item.NamePoolOffset := AppendWideName(ADB, namePtr, nameChars);
            if item.NamePoolOffset = 0 then
              Continue;
            item.DateModified := FileTimeToUnixDate(rec.TimeStamp);
            item.FileAttributes := rec.FileAttributes;
            item.IsDirectory := (rec.FileAttributes and cFaDirectory) <> 0;
            item.DriveIndex := ADriveIndex;
            item.Excluded := IsSystemFolderNameWide(fileName);
            if Length(AItems) <= n then
              SetLength(AItems, n + 4096);
            AItems[n] := item;
            Inc(n);
          end;
          Inc(offset, recLen);
        end;
      end;
      if enumData.StartFileReferenceNumber = 0 then
        Break;
    until False;
    SetLength(AItems, n);
    if n > 0 then
      Exit(True);
    if lastErr <> 0 then
      AFailDetail := 'FSCTL_ENUM_USN_DATA 失败（' + Win32ErrorTextFrom(lastErr) + '）'
    else
      AFailDetail := 'FSCTL_ENUM_USN_DATA 未返回任何 USN 记录（' + Win32ErrorTextFrom(0) + '）';
  finally
    CloseHandle(hVol);
  end;
end;

procedure CommitUsnItems(var ADB: TEverythingDB; const AItems: TArray<TUsnTempItem>;
  AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray);
var
  i: Integer;
  folder: TFolderEntry;
  fileRec: TFileEntry;
  folderOff, parentOff: Cardinal;
  frnKey: UInt64;
  segToFolder: TDictionary<UInt64, Cardinal>;
  nameUtf8: PAnsiChar;
  extPtr: PAnsiChar;
begin
  segToFolder := TDictionary<UInt64, Cardinal>.Create;
  try
  for i := 0 to High(AItems) do
  begin
    if (not AItems[i].IsDirectory) or AItems[i].Excluded then
      Continue;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if AFrnToFolder.ContainsKey(frnKey) then
      Continue;
    GrowFolders(ADB);
    folder.FRN := AItems[i].FRN;
    folder.NamePoolOffset := AItems[i].NamePoolOffset;
    folder.DateModified := AItems[i].DateModified;
    folder.Attributes := Word(AItems[i].FileAttributes);
    folder.DriveIndex := AItems[i].DriveIndex;
    folder.ParentOffset := cRootParentOffset;
    ADB.Folders[ADB.FolderCount] := folder;
    AFrnToFolder.Add(frnKey, Cardinal(ADB.FolderCount));
    Inc(ADB.FolderCount);
  end;

  BuildSegmentFolderMap(AFrnToFolder, segToFolder);

  for i := 0 to High(AItems) do
  begin
    if (not AItems[i].IsDirectory) or AItems[i].Excluded then
      Continue;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if not AFrnToFolder.TryGetValue(frnKey, folderOff) then
      Continue;
    if ResolveParentFolderOffset(AItems[i].DriveIndex, AItems[i].ParentFRN, AFrnToFolder,
      segToFolder, parentOff) then
      ADB.Folders[folderOff].ParentOffset := parentOff
    else
      ADB.Folders[folderOff].ParentOffset := cRootParentOffset;
  end;

  if ADB.VolumeBaseDate = 0 then
  begin
    for i := 0 to High(AItems) do
      if (not AItems[i].IsDirectory) and (not AItems[i].Excluded) and (AItems[i].DateModified > 0) then
      begin
        ADB.VolumeBaseDate := AItems[i].DateModified;
        Break;
      end;
  end;

  for i := 0 to High(AItems) do
  begin
    if AItems[i].IsDirectory or AItems[i].Excluded then
      Continue;
    if not ResolveParentFolderOffset(AItems[i].DriveIndex, AItems[i].ParentFRN, AFrnToFolder,
      segToFolder, parentOff) then
      parentOff := cRootParentOffset;
    frnKey := FrnMapKey(AItems[i].DriveIndex, AItems[i].FRN);
    if (AFrnToFile <> nil) and AFrnToFile.ContainsKey(frnKey) then
    begin
      if (parentOff <> cRootParentOffset) and AFrnToFile.TryGetValue(frnKey, folderOff) then
        if ADB.Files[folderOff].ParentOffset = cRootParentOffset then
          ADB.Files[folderOff].ParentOffset := parentOff;
      Continue;
    end;
    GrowFiles(ADB);
    fileRec.ParentOffset := parentOff;
    fileRec.NamePoolOffset := AItems[i].NamePoolOffset;
    fileRec.SizeLow := 0;
    fileRec.DateModifiedDelta := UnixDateToDelta(ADB.VolumeBaseDate, AItems[i].DateModified);
    nameUtf8 := PAnsiChar(@ADB.NamePool[AItems[i].NamePoolOffset]);
    extPtr := ExtractExtUtf8(nameUtf8);
    fileRec.ExtID := FindOrAddExt(ADB, extPtr);
    ADB.Files[ADB.FileCount] := fileRec;
    if AFrnToFile <> nil then
      AFrnToFile.Add(frnKey, Cardinal(ADB.FileCount));
    if Length(AFileFrnKeys) <= ADB.FileCount then
      SetLength(AFileFrnKeys, ADB.FileCount + cGrowChunkFiles);
    AFileFrnKeys[ADB.FileCount] := frnKey;
    Inc(ADB.FileCount);
  end;
  finally
    segToFolder.Free;
  end;
end;

function UsnBuildFromDrive(const ADriveLetter: Char; ADriveIndex: Byte;
  var ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AExcludedFrn: TDictionary<UInt64, Byte>; const AOnProgress: TMftBuildProgressProc;
  out AFailReason: string): Boolean;
var
  items: TArray<TUsnTempItem>;
  i, filesBefore: Integer;
  enumDetail: string;
begin
  Result := False;
  AFailReason := '';
  filesBefore := ADB.FileCount;
  if Assigned(AOnProgress) then
    AOnProgress('正在 USN 枚举 ' + ADriveLetter + ':');
  if not EnumVolumeUsnItems(ADriveLetter, ADriveIndex, ADB, items, enumDetail) then
  begin
    AFailReason := enumDetail;
    Exit;
  end;
  for i := 0 to High(items) do
    if items[i].Excluded and items[i].IsDirectory then
      if not AExcludedFrn.ContainsKey(FrnMapKey(items[i].DriveIndex, items[i].FRN)) then
        AExcludedFrn.Add(FrnMapKey(items[i].DriveIndex, items[i].FRN), 1);
  MarkExcludedUsnItems(items, AExcludedFrn);
  CommitUsnItems(ADB, items, AFrnToFolder, AFrnToFile, AFileFrnKeys);
  if ADB.FileCount <= filesBefore then
  begin
    AFailReason := 'USN 枚举完成但未产生可索引文件';
    Exit;
  end;
  Result := True;
end;

function MftBuildFromDriveRaw(const ADriveLetter: Char; ADriveIndex: Byte;
  var ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AExcludedFrn: TDictionary<UInt64, Byte>; const AOnProgress: TMftBuildProgressProc;
  out AFailReason: string): Boolean;
var
  volHandle: THandle;
  volData: TNTFS_VOLUME_DATA_BUFFER;
  bytesReturned: DWORD;
  recordSize, bytesPerCluster, bytesPerSector: DWORD;
  recordSizeInt: Integer;
  mftStart, mftSize, fileOffset: Int64;
  chunkBuf, fetchBuf: PByte;
  chunkSize, fetchBufSize: Integer;
  recordIndex, recordCount: Int64;
  i, carryLen, workLen: Integer;
  readSize: DWORD;
  recPtr: PByte;
  item: TRawMftItem;
  rawItems: TArray<TRawMftItem>;
  rawCount, rawFileCount: Integer;
  driveStr: string;
  carry, workBuf: array of Byte;
  scanComplete: Boolean;

  procedure AppendRawItem(const AItem: TRawMftItem);
  begin
    if Length(rawItems) <= rawCount then
      SetLength(rawItems, rawCount + 4096);
    rawItems[rawCount] := AItem;
    if AItem.Excluded and AItem.IsDirectory then
      if not AExcludedFrn.ContainsKey(FrnMapKey(ADriveIndex, AItem.FRN)) then
        AExcludedFrn.Add(FrnMapKey(ADriveIndex, AItem.FRN), 1);
    Inc(rawCount);
  end;

begin
  Result := False;
  AFailReason := '';
  scanComplete := False;
  if not MftIsNtfsVolume(ADriveLetter) then
  begin
    AFailReason := '非 NTFS 卷';
    Exit;
  end;
  volHandle := OpenRawVolume(ADriveLetter);
  if volHandle = INVALID_HANDLE_VALUE then
  begin
    AFailReason := DriveOpenFailHint(ADriveLetter);
    Exit;
  end;
  try
    FillChar(volData, SizeOf(volData), 0);
    if not DeviceIoControl(volHandle, FSCTL_GET_NTFS_VOLUME_DATA, nil, 0,
      @volData, SizeOf(volData), bytesReturned, nil) then
    begin
      AFailReason := '无法读取 NTFS 卷数据（FSCTL_GET_NTFS_VOLUME_DATA 失败）';
      Exit;
    end;
    bytesPerCluster := volData.BytesPerCluster;
    bytesPerSector := volData.BytesPerSector;
    if bytesPerSector = 0 then
      bytesPerSector := 512;
    recordSize := ResolveFileRecordSize(volData);
    if (recordSize = 0) or (bytesPerCluster = 0) then
    begin
      AFailReason := 'NTFS 卷参数无效（记录大小或簇大小为 0）';
      Exit;
    end;
    recordSizeInt := Integer(recordSize);
    mftStart := volData.MftStartLcn * bytesPerCluster;
    mftSize := ResolveMftScanSize(volData, recordSize);
    chunkSize := cMftReadChunk;
    driveStr := ADriveLetter + ':';
    fetchBufSize := recordSizeInt + cMftIoctlScanSlop;
    GetMem(chunkBuf, chunkSize);
    GetMem(fetchBuf, fetchBufSize);
    try
      SetLength(rawItems, 0);
      SetLength(carry, 0);
      rawCount := 0;
      carryLen := 0;
      fileOffset := 0;
      while fileOffset < mftSize do
      begin
        if Assigned(AOnProgress) and ((fileOffset mod Int64(recordSizeInt * 4096)) = 0) then
          AOnProgress('正在索引 ' + driveStr);
        if not SeekVolumeOffset(volHandle, mftStart + fileOffset) then
        begin
          AFailReason := '无法定位 $MFT 偏移（' + Win32ErrorText + '）';
          Break;
        end;
        if Int64(chunkSize) < (mftSize - fileOffset) then
          readSize := chunkSize
        else
          readSize := DWORD(mftSize - fileOffset);
        if not ReadFile(volHandle, chunkBuf^, readSize, bytesReturned, nil) then
        begin
          AFailReason := '读取 $MFT 失败（' + Win32ErrorText + '）';
          Break;
        end;
        if bytesReturned = 0 then
        begin
          if rawCount = 0 then
            AFailReason := '读取 $MFT 未返回数据（需要管理员权限或卷被保护）';
          Break;
        end;
        workLen := carryLen + Integer(bytesReturned);
        SetLength(workBuf, workLen);
        if carryLen > 0 then
          Move(carry[0], workBuf[0], carryLen);
        Move(chunkBuf^, workBuf[carryLen], bytesReturned);
        recordCount := workLen div recordSizeInt;
        if recordCount = 0 then
        begin
          carryLen := workLen;
          SetLength(carry, carryLen);
          if carryLen > 0 then
            Move(workBuf[0], carry[0], carryLen);
          Inc(fileOffset, bytesReturned);
          Continue;
        end;
        for i := 0 to Integer(recordCount) - 1 do
        begin
          recPtr := PByte(@workBuf[i * recordSizeInt]);
          recordIndex := (fileOffset + Int64(i) * Int64(recordSizeInt)) div Int64(recordSizeInt);
          if ParseMftRecord(recPtr, recordSize, bytesPerSector, recordIndex, ADriveIndex, ADB, item) then
            AppendRawItem(item)
          else if TryParseMftRecordByIoctl(volHandle, recordIndex, recordSize, bytesPerSector,
            ADriveIndex, ADB, item, fetchBuf, fetchBufSize) then
            AppendRawItem(item);
        end;
        carryLen := workLen - Integer(recordCount) * recordSizeInt;
        SetLength(carry, carryLen);
        if carryLen > 0 then
          Move(workBuf[Integer(recordCount) * recordSizeInt], carry[0], carryLen);
        Inc(fileOffset, recordCount * Int64(recordSizeInt));
      end;
      scanComplete := (fileOffset >= mftSize) and (AFailReason = '');
      SetLength(rawItems, rawCount);
      if not scanComplete then
      begin
        if AFailReason = '' then
          AFailReason := '未完整读取 $MFT（已解析 ' + IntToStr(rawCount) + ' 条记录）';
        Exit;
      end;
      if rawCount = 0 then
      begin
        AFailReason := 'MFT 未解析到有效记录';
        Exit;
      end;
      rawFileCount := 0;
      for i := 0 to rawCount - 1 do
        if (not rawItems[i].IsDirectory) and (not rawItems[i].Excluded) then
          Inc(rawFileCount);
      if rawFileCount = 0 then
      begin
        AFailReason := 'MFT 仅解析到 ' + IntToStr(rawCount) + ' 条目录记录，未解析到文件';
        Exit;
      end;
      MarkExcludedDescendants(rawItems, AExcludedFrn);
      CommitRawItems(ADB, rawItems, AFrnToFolder, AFrnToFile, AFileFrnKeys);
      Result := True;
    finally
      FreeMem(fetchBuf);
      FreeMem(chunkBuf);
    end;
  finally
    CloseHandle(volHandle);
  end;
  if (not Result) and (AFailReason = '') then
    AFailReason := '读取或解析 $MFT 失败';
end;

function MftBuildFromDrive(const ADriveLetter: Char; ADriveIndex: Byte;
  var ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AExcludedFrn: TDictionary<UInt64, Byte>; const AOnProgress: TMftBuildProgressProc;
  out AFailReason: string): Boolean;
var
  usnReason, mftReason: string;
  filesBefore: Integer;
  mftOk: Boolean;
begin
  Result := False;
  AFailReason := '';
  if MftIsSubstDrive(ADriveLetter) then
  begin
    AFailReason := DriveOpenFailHint(ADriveLetter);
    Exit;
  end;
  EnableVolumeScanPrivileges;
  filesBefore := ADB.FileCount;
  mftOk := MftBuildFromDriveRaw(ADriveLetter, ADriveIndex, ADB, AFrnToFolder, AFrnToFile, AFileFrnKeys,
    AExcludedFrn, AOnProgress, mftReason);
  if mftOk and (ADB.FileCount <= filesBefore) then
  begin
    if mftReason <> '' then
      mftReason := '$MFT 已索引文件夹但未产生文件（' + mftReason + '）'
    else
      mftReason := '$MFT 已索引文件夹但未产生文件';
  end;
  { 线性 $MFT 扫描会漏掉已重定位的记录；USN 全量枚举可补齐 Desktop\CreateSession 等目录。 }
  UsnBuildFromDrive(ADriveLetter, ADriveIndex, ADB, AFrnToFolder, AFrnToFile, AFileFrnKeys,
    AExcludedFrn, AOnProgress, usnReason);
  if ADB.FileCount > filesBefore then
    Exit(True);
  AFailReason := mftReason;
  if usnReason <> '' then
  begin
    if AFailReason <> '' then
      AFailReason := AFailReason + '; ';
    AFailReason := AFailReason + 'USN: ' + usnReason;
  end;
end;

function IsUsnDirectory(AAttributes: DWORD): Boolean;
begin
  Result := (AAttributes and cFaDirectory) <> 0;
end;

function IsUsnRecordDirectory(AAttributes: DWORD; AFrnKey: UInt64;
  AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>): Boolean;
begin
  if (AFrnToFile <> nil) and AFrnToFile.ContainsKey(AFrnKey) then
    Exit(False);
  Result := IsUsnDirectory(AAttributes);
  if not Result and (AFrnToFolder <> nil) then
    Result := AFrnToFolder.ContainsKey(AFrnKey);
end;

function IsUsnRenameReason(AReason: DWORD): Boolean;
begin
  Result := (AReason and (USN_REASON_RENAME_OLD_NAME or USN_REASON_RENAME_NEW_NAME)) <> 0;
end;

function IsUsnDeleteOnlyReason(AReason: DWORD): Boolean;
begin
  Result := (AReason and USN_REASON_FILE_DELETE) <> 0;
  if not Result then
    Exit;
  Result := not IsUsnRenameReason(AReason);
end;

function IsUsnUpsertReason(AReason: DWORD): Boolean;
begin
  if IsUsnDeleteOnlyReason(AReason) then
    Exit(False);
  Result := (AReason and (USN_REASON_FILE_CREATE or USN_REASON_RENAME_NEW_NAME or
    USN_REASON_BASIC_INFO_CHANGE or USN_REASON_CLOSE)) <> 0;
end;

function FileLookupKey(AParentOff: Cardinal; const ANameUtf8: AnsiString): AnsiString;
var
  nameLen: Integer;
begin
  nameLen := Length(ANameUtf8);
  SetLength(Result, 4 + 1 + nameLen);
  Move(AParentOff, Result[1], 4);
  Result[5] := #1;
  if nameLen > 0 then
    Move(ANameUtf8[1], Result[6], nameLen);
end;

function FileLookupKeyWide(AParentOff: Cardinal; const AFileName: string): AnsiString;
begin
  Result := FileLookupKey(AParentOff, MftWideNameToUtf8Lower(AFileName));
end;

function FileLookupKeyFromPool(const ADB: TEverythingDB; AParentOff, ANameOff: Cardinal): AnsiString;
var
  src: PAnsiChar;
  i, nameLen: Integer;
  ch: AnsiChar;
begin
  Result := '';
  src := NamePoolPtrAt(ADB, ANameOff);
  if src = nil then
    Exit;
  nameLen := AnsiStrLen(src);
  SetLength(Result, 4 + 1 + nameLen);
  Move(AParentOff, Result[1], 4);
  Result[5] := #1;
  for i := 0 to nameLen - 1 do
  begin
    ch := src[i];
    if (ch >= 'A') and (ch <= 'Z') then
      Result[6 + i] := AnsiChar(Ord(ch) + 32)
    else
      Result[6 + i] := ch;
  end;
end;

function FindFileIndexByParentAndName(const ADB: TEverythingDB; AParentOff: Cardinal;
  const AFileName: string; AFileLookup: TDictionary<AnsiString, Integer>): Integer;
var
  i: Integer;
  nameUtf8: AnsiString;
  lookupKey: AnsiString;
begin
  Result := -1;
  if AFileLookup <> nil then
  begin
    lookupKey := FileLookupKeyWide(AParentOff, AFileName);
    if lookupKey = '' then
      Exit;
    if AFileLookup.TryGetValue(lookupKey, Result) then
      Exit;
    Exit(-1);
  end;
  nameUtf8 := MftWideNameToUtf8Lower(AFileName);
  if nameUtf8 = '' then
    Exit;
  for i := 0 to ADB.FileCount - 1 do
  begin
    if ADB.Files[i].ParentOffset <> AParentOff then
      Continue;
    if Utf8ToLowerAnsi(NamePoolPtrAt(ADB, ADB.Files[i].NamePoolOffset)) = nameUtf8 then
      Exit(i);
  end;
end;

procedure MftBuildFileParentNameMap(const ADB: TEverythingDB; AMap: TDictionary<AnsiString, Integer>);
var
  i: Integer;
begin
  AMap.Clear;
  for i := 0 to ADB.FileCount - 1 do
    AMap.AddOrSetValue(FileLookupKeyFromPool(ADB, ADB.Files[i].ParentOffset,
      ADB.Files[i].NamePoolOffset), i);
end;

function FindFolderIndexByParentAndName(const ADB: TEverythingDB; ADriveIndex: Byte;
  AParentOff: Cardinal; const AFolderName: string): Integer;
var
  i: Integer;
  nameUtf8: AnsiString;
begin
  Result := -1;
  nameUtf8 := MftWideNameToUtf8Lower(AFolderName);
  if nameUtf8 = '' then
    Exit;
  for i := 0 to ADB.FolderCount - 1 do
  begin
    if ADB.Folders[i].DriveIndex <> ADriveIndex then
      Continue;
    if ADB.Folders[i].ParentOffset <> AParentOff then
      Continue;
    if Utf8ToLowerAnsi(NamePoolPtrAt(ADB, ADB.Folders[i].NamePoolOffset)) = nameUtf8 then
      Exit(i);
  end;
end;

procedure MftRebuildFolderFrnMap(const ADB: TEverythingDB;
  AFrnToFolder: TDictionary<UInt64, Cardinal>);
var
  i: Integer;
  frnKey: UInt64;
begin
  AFrnToFolder.Clear;
  for i := 0 to ADB.FolderCount - 1 do
  begin
    frnKey := FrnMapKey(ADB.Folders[i].DriveIndex, ADB.Folders[i].FRN);
    AFrnToFolder.AddOrSetValue(frnKey, Cardinal(i));
  end;
end;

function MftRebuildFileFrnMapFromUsn(const ADriveLetter: Char; ADriveIndex: Byte;
  const ADB: TEverythingDB; AFrnToFolder: TDictionary<UInt64, Cardinal>;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray): Boolean;
var
  items: TArray<TUsnTempItem>;
  enumDetail: string;
  fileKeyMap: TDictionary<AnsiString, Integer>;
  parentOff: Cardinal;
  segToFolder: TDictionary<UInt64, Cardinal>;
  tempDb: TEverythingDB;
  i, fileIdx: Integer;
  frnKey: UInt64;
  lookupKey: AnsiString;
  nameUtf8: AnsiString;
begin
  Result := False;
  FillChar(tempDb, SizeOf(tempDb), 0);
  if not EnumVolumeUsnItems(ADriveLetter, ADriveIndex, tempDb, items, enumDetail) then
    Exit;
  fileKeyMap := TDictionary<AnsiString, Integer>.Create;
  segToFolder := TDictionary<UInt64, Cardinal>.Create;
  try
    BuildSegmentFolderMap(AFrnToFolder, segToFolder);
    for i := 0 to ADB.FileCount - 1 do
    begin
      parentOff := ADB.Files[i].ParentOffset;
      lookupKey := FileLookupKeyFromPool(ADB, parentOff, ADB.Files[i].NamePoolOffset);
      fileKeyMap.AddOrSetValue(lookupKey, i);
    end;
    SetLength(AFileFrnKeys, ADB.FileCount);
    FillChar(AFileFrnKeys[0], ADB.FileCount * SizeOf(UInt64), 0);
    AFrnToFile.Clear;
    for i := 0 to High(items) do
    begin
      if items[i].IsDirectory or items[i].Excluded or (items[i].DriveIndex <> ADriveIndex) then
        Continue;
      if not ResolveParentFolderOffset(ADriveIndex, items[i].ParentFRN, AFrnToFolder,
        segToFolder, parentOff) then
        parentOff := cRootParentOffset;
      nameUtf8 := NamePoolToAnsi(tempDb, items[i].NamePoolOffset);
      lookupKey := FileLookupKey(parentOff, nameUtf8);
      if not fileKeyMap.TryGetValue(lookupKey, fileIdx) then
        Continue;
      frnKey := FrnMapKey(ADriveIndex, items[i].FRN);
      AFrnToFile.AddOrSetValue(frnKey, Cardinal(fileIdx));
      AFileFrnKeys[fileIdx] := frnKey;
    end;
    Result := AFrnToFile.Count > 0;
  finally
    segToFolder.Free;
    fileKeyMap.Free;
  end;
end;

function FolderIndexToHitIndex(AFolderIndex: Integer): Integer;
begin
  Result := -(AFolderIndex + 1);
end;

procedure AppendIndexHitChange(var AChanges: TIndexHitChangeArray; AKind: TIndexHitChangeKind;
  AHitIndex, ANewHitIndex: Integer);
var
  n: Integer;
begin
  n := Length(AChanges);
  SetLength(AChanges, n + 1);
  AChanges[n].Kind := AKind;
  AChanges[n].HitIndex := AHitIndex;
  AChanges[n].NewHitIndex := ANewHitIndex;
end;

procedure RemoveFileAtIndex(var ADB: TEverythingDB; AIndex: Integer;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AFileLookup: TDictionary<AnsiString, Integer>; var AChanges: TIndexHitChangeArray);
var
  lastIdx: Integer;
  movedFrn: UInt64;
  lookupKey: AnsiString;
begin
  if (AIndex < 0) or (AIndex >= ADB.FileCount) then
    Exit;
  lastIdx := ADB.FileCount - 1;
  AppendIndexHitChange(AChanges, ihckFileRemoved, AIndex, 0);
  if AIndex < lastIdx then
    AppendIndexHitChange(AChanges, ihckFileRemapped, lastIdx, AIndex);
  if AFileLookup <> nil then
  begin
    lookupKey := FileLookupKeyFromPool(ADB, ADB.Files[AIndex].ParentOffset,
      ADB.Files[AIndex].NamePoolOffset);
    if lookupKey <> '' then
      AFileLookup.Remove(lookupKey);
  end;
  if AFrnToFile <> nil then
  begin
    if Length(AFileFrnKeys) > AIndex then
    begin
      movedFrn := AFileFrnKeys[AIndex];
      if movedFrn <> 0 then
        AFrnToFile.Remove(movedFrn);
    end;
  end;
  if AIndex < lastIdx then
  begin
    if AFileLookup <> nil then
    begin
      lookupKey := FileLookupKeyFromPool(ADB, ADB.Files[lastIdx].ParentOffset,
        ADB.Files[lastIdx].NamePoolOffset);
      if lookupKey <> '' then
        AFileLookup.Remove(lookupKey);
    end;
    ADB.Files[AIndex] := ADB.Files[lastIdx];
    if Length(AFileFrnKeys) > lastIdx then
    begin
      AFileFrnKeys[AIndex] := AFileFrnKeys[lastIdx];
      if (AFrnToFile <> nil) and (AFileFrnKeys[AIndex] <> 0) then
        AFrnToFile.AddOrSetValue(AFileFrnKeys[AIndex], Cardinal(AIndex));
    end;
    if AFileLookup <> nil then
      AFileLookup.AddOrSetValue(FileLookupKeyFromPool(ADB, ADB.Files[AIndex].ParentOffset,
        ADB.Files[AIndex].NamePoolOffset), AIndex);
  end;
  if Length(AFileFrnKeys) > lastIdx then
    AFileFrnKeys[lastIdx] := 0;
  Dec(ADB.FileCount);
end;

function FolderIsAncestor(const ADB: TEverythingDB; AAncestorOff, AFolderOff: Cardinal): Boolean;
var
  cur: Cardinal;
  guard: Integer;
begin
  Result := False;
  if (AAncestorOff = cRootParentOffset) or (AFolderOff = cRootParentOffset) then
    Exit;
  cur := AFolderOff;
  guard := 0;
  while (cur <> cRootParentOffset) and (Integer(cur) >= 0) and (Integer(cur) < ADB.FolderCount) do
  begin
    if cur = AAncestorOff then
      Exit(True);
    cur := ADB.Folders[cur].ParentOffset;
    Inc(guard);
    if guard > 256 then
      Break;
  end;
end;

procedure RemoveFilesUnderFolder(var ADB: TEverythingDB; AFolderOff: Cardinal;
  AFrnToFile: TDictionary<UInt64, Cardinal>; var AFileFrnKeys: TFileFrnKeyArray;
  AFileLookup: TDictionary<AnsiString, Integer>; var AChanges: TIndexHitChangeArray);
var
  i, parentOff: Integer;
begin
  i := ADB.FileCount - 1;
  while i >= 0 do
  begin
    parentOff := Integer(ADB.Files[i].ParentOffset);
    if (parentOff = Integer(AFolderOff)) or
      ((parentOff >= 0) and FolderIsAncestor(ADB, AFolderOff, Cardinal(parentOff))) then
      RemoveFileAtIndex(ADB, i, AFrnToFile, AFileFrnKeys, AFileLookup, AChanges);
    Dec(i);
  end;
end;

procedure UpsertFolderRecord(var ADB: TEverythingDB; ADriveIndex: Byte;
  const ARec: TUsnJournalRecord; AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>;
  AExcludedFrn: TDictionary<UInt64, Byte>; var AFileFrnKeys: TFileFrnKeyArray; ANameOff: Cardinal;
  const ARenameOldName: string; AFileLookup: TDictionary<AnsiString, Integer>;
  ASegToFolder: TDictionary<UInt64, Cardinal>; var AChanges: TIndexHitChangeArray);
var
  frnKey: UInt64;
  folderOff, parentOff: Cardinal;
  folder: TFolderEntry;
  excluded: Boolean;
  foundIdx: Integer;
  folderWasNew: Boolean;
begin
  folderWasNew := False;
  frnKey := FrnMapKey(ADriveIndex, ARec.FRN);
  excluded := IsSystemFolderNameWide(ARec.FileName);
  if excluded then
  begin
    if not AExcludedFrn.ContainsKey(frnKey) then
      AExcludedFrn.Add(frnKey, 1);
    if AFrnToFolder.TryGetValue(frnKey, folderOff) then
    begin
      AppendIndexHitChange(AChanges, ihckFolderRemoved, FolderIndexToHitIndex(folderOff), 0);
      AFrnToFolder.Remove(frnKey);
      RemoveSegmentFolderEntry(ASegToFolder, ADriveIndex, ARec.FRN);
      RemoveFilesUnderFolder(ADB, folderOff, AFrnToFile, AFileFrnKeys, AFileLookup, AChanges);
    end;
    Exit;
  end;
  folderOff := 0;
  if not AFrnToFolder.TryGetValue(frnKey, folderOff) then
  begin
    foundIdx := -1;
    if ARenameOldName <> '' then
    begin
      if ResolveParentFolderOffset(ADriveIndex, ARec.ParentFRN, AFrnToFolder, ASegToFolder, parentOff) then
        foundIdx := FindFolderIndexByParentAndName(ADB, ADriveIndex, parentOff, ARenameOldName);
    end;
    if foundIdx >= 0 then
    begin
      folderOff := Cardinal(foundIdx);
      ADB.Folders[folderOff].FRN := ARec.FRN;
      AFrnToFolder.AddOrSetValue(frnKey, folderOff);
      SetSegmentFolderEntry(ASegToFolder, ADriveIndex, ARec.FRN, folderOff);
    end
    else
    begin
      GrowFolders(ADB);
      folder.FRN := ARec.FRN;
      folder.NamePoolOffset := ANameOff;
      folder.DateModified := FileTimeToUnixDate(ARec.TimeStamp);
      folder.Attributes := Word(ARec.FileAttributes);
      folder.DriveIndex := ADriveIndex;
      folder.ParentOffset := cRootParentOffset;
      ADB.Folders[ADB.FolderCount] := folder;
      folderOff := Cardinal(ADB.FolderCount);
      AFrnToFolder.Add(frnKey, folderOff);
      SetSegmentFolderEntry(ASegToFolder, ADriveIndex, ARec.FRN, folderOff);
      Inc(ADB.FolderCount);
      folderWasNew := True;
    end;
  end;
  ADB.Folders[folderOff].NamePoolOffset := ANameOff;
  ADB.Folders[folderOff].DateModified := FileTimeToUnixDate(ARec.TimeStamp);
  if ARec.FileAttributes <> 0 then
    ADB.Folders[folderOff].Attributes := Word(ARec.FileAttributes);
  if ResolveParentFolderOffset(ADriveIndex, ARec.ParentFRN, AFrnToFolder, ASegToFolder, parentOff) then
    ADB.Folders[folderOff].ParentOffset := parentOff
  else
    ADB.Folders[folderOff].ParentOffset := cRootParentOffset;
  if folderWasNew then
    AppendIndexHitChange(AChanges, ihckFolderAdded, FolderIndexToHitIndex(folderOff), 0)
  else
    AppendIndexHitChange(AChanges, ihckFolderUpdated, FolderIndexToHitIndex(folderOff), 0);
end;

procedure RemoveFileByUsnRecord(var ADB: TEverythingDB; ADriveIndex: Byte;
  const ARec: TUsnJournalRecord; AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>;
  var AFileFrnKeys: TFileFrnKeyArray; AFileLookup: TDictionary<AnsiString, Integer>;
  ASegToFolder: TDictionary<UInt64, Cardinal>; var AStats: TMftApplyUsnStats;
  var AChanges: TIndexHitChangeArray);
var
  frnKey: UInt64;
  fileIdx, parentOff: Cardinal;
  foundIdx: Integer;
begin
  frnKey := FrnMapKey(ADriveIndex, ARec.FRN);
  if (AFrnToFile <> nil) and AFrnToFile.TryGetValue(frnKey, fileIdx) then
  begin
    RemoveFileAtIndex(ADB, Integer(fileIdx), AFrnToFile, AFileFrnKeys, AFileLookup, AChanges);
    Inc(AStats.FilesRemoved);
    Exit;
  end;
  if ARec.FileName = '' then
    Exit;
  if not ResolveParentFolderOffset(ADriveIndex, ARec.ParentFRN, AFrnToFolder,
    ASegToFolder, parentOff) then
    parentOff := cRootParentOffset;
  foundIdx := FindFileIndexByParentAndName(ADB, parentOff, ARec.FileName, AFileLookup);
  if foundIdx >= 0 then
  begin
    RemoveFileAtIndex(ADB, foundIdx, AFrnToFile, AFileFrnKeys, AFileLookup, AChanges);
    Inc(AStats.FilesRemoved);
  end;
end;

procedure UpsertFileRecord(var ADB: TEverythingDB; ADriveIndex: Byte;
  const ARec: TUsnJournalRecord; AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>;
  AExcludedFrn: TDictionary<UInt64, Byte>; var AFileFrnKeys: TFileFrnKeyArray; ANameOff: Cardinal;
  const ARenameOldName: string; AFileLookup: TDictionary<AnsiString, Integer>;
  ASegToFolder: TDictionary<UInt64, Cardinal>; var AStats: TMftApplyUsnStats;
  var AChanges: TIndexHitChangeArray);
var
  frnKey: UInt64;
  fileIdx: Cardinal;
  parentOff: Cardinal;
  fileRec: TFileEntry;
  nameUtf8: PAnsiChar;
  extPtr: PAnsiChar;
  parentKey: UInt64;
  foundIdx: Integer;
  lookupKey: AnsiString;
begin
  parentKey := FrnMapKey(ADriveIndex, ARec.ParentFRN);
  if (AExcludedFrn <> nil) and AExcludedFrn.ContainsKey(parentKey) then
    Exit;
  frnKey := FrnMapKey(ADriveIndex, ARec.FRN);
  if (AFrnToFolder <> nil) and AFrnToFolder.ContainsKey(frnKey) then
    Exit;
  if not ResolveParentFolderOffset(ADriveIndex, ARec.ParentFRN, AFrnToFolder, ASegToFolder, parentOff) then
    parentOff := cRootParentOffset;
  foundIdx := -1;
  if (AFrnToFile <> nil) and AFrnToFile.TryGetValue(frnKey, fileIdx) then
    foundIdx := Integer(fileIdx)
  else if ARenameOldName <> '' then
  begin
    foundIdx := FindFileIndexByParentAndName(ADB, parentOff, ARenameOldName, AFileLookup);
    if foundIdx >= 0 then
    begin
      if AFrnToFile <> nil then
        AFrnToFile.AddOrSetValue(frnKey, Cardinal(foundIdx));
      if Length(AFileFrnKeys) <= foundIdx then
        SetLength(AFileFrnKeys, foundIdx + cGrowChunkFiles);
      AFileFrnKeys[foundIdx] := frnKey;
    end;
  end;
  if foundIdx < 0 then
    foundIdx := FindFileIndexByParentAndName(ADB, parentOff, ARec.FileName, AFileLookup);
  if foundIdx >= 0 then
  begin
    if AFileLookup <> nil then
    begin
      lookupKey := FileLookupKeyFromPool(ADB, ADB.Files[foundIdx].ParentOffset,
        ADB.Files[foundIdx].NamePoolOffset);
      if lookupKey <> '' then
        AFileLookup.Remove(lookupKey);
    end;
    if AFrnToFile <> nil then
      AFrnToFile.AddOrSetValue(frnKey, Cardinal(foundIdx));
    if Length(AFileFrnKeys) <= foundIdx then
      SetLength(AFileFrnKeys, foundIdx + cGrowChunkFiles);
    AFileFrnKeys[foundIdx] := frnKey;
    ADB.Files[foundIdx].NamePoolOffset := ANameOff;
    ADB.Files[foundIdx].ParentOffset := parentOff;
    ADB.Files[foundIdx].DateModifiedDelta := UnixDateToDelta(ADB.VolumeBaseDate,
      FileTimeToUnixDate(ARec.TimeStamp));
    nameUtf8 := PAnsiChar(@ADB.NamePool[ANameOff]);
    extPtr := ExtractExtUtf8(nameUtf8);
    ADB.Files[foundIdx].ExtID := FindOrAddExt(ADB, extPtr);
    if AFileLookup <> nil then
      AFileLookup.AddOrSetValue(FileLookupKeyFromPool(ADB, parentOff, ANameOff), foundIdx);
    Inc(AStats.FilesUpdated);
    AppendIndexHitChange(AChanges, ihckFileUpdated, foundIdx, 0);
    Exit;
  end;
  if ADB.VolumeBaseDate = 0 then
    ADB.VolumeBaseDate := FileTimeToUnixDate(ARec.TimeStamp);
  GrowFiles(ADB);
  fileRec.ParentOffset := parentOff;
  fileRec.NamePoolOffset := ANameOff;
  fileRec.SizeLow := 0;
  fileRec.DateModifiedDelta := UnixDateToDelta(ADB.VolumeBaseDate, FileTimeToUnixDate(ARec.TimeStamp));
  nameUtf8 := PAnsiChar(@ADB.NamePool[ANameOff]);
  extPtr := ExtractExtUtf8(nameUtf8);
  fileRec.ExtID := FindOrAddExt(ADB, extPtr);
  ADB.Files[ADB.FileCount] := fileRec;
  if Length(AFileFrnKeys) <= ADB.FileCount then
    SetLength(AFileFrnKeys, ADB.FileCount + cGrowChunkFiles);
  AFileFrnKeys[ADB.FileCount] := frnKey;
  if AFrnToFile <> nil then
    AFrnToFile.Add(frnKey, Cardinal(ADB.FileCount));
  if AFileLookup <> nil then
    AFileLookup.AddOrSetValue(FileLookupKeyFromPool(ADB, parentOff, ANameOff), ADB.FileCount);
  AppendIndexHitChange(AChanges, ihckFileAdded, ADB.FileCount, 0);
  Inc(ADB.FileCount);
  Inc(AStats.FilesAdded);
end;

function MftApplyUsnRecords(var ADB: TEverythingDB; ADriveIndex: Byte;
  const ARecords: TUsnJournalRecordArray; AFrnToFolder, AFrnToFile: TDictionary<UInt64, Cardinal>;
  AExcludedFrn: TDictionary<UInt64, Byte>; var AFileFrnKeys: TFileFrnKeyArray;
  AFileLookup: TDictionary<AnsiString, Integer>; out AStats: TMftApplyUsnStats;
  var AChanges: TIndexHitChangeArray): Boolean;
var
  i: Integer;
  rec: TUsnJournalRecord;
  frnKey: UInt64;
  folderOff: Cardinal;
  nameOff: Integer;
  isDir: Boolean;
  renameOldNames: TDictionary<UInt64, string>;
  renameFrns: TDictionary<UInt64, Byte>;
  renameOldName: string;
  segToFolder: TDictionary<UInt64, Cardinal>;
begin
  FillChar(AStats, SizeOf(AStats), 0);
  Result := Length(ARecords) > 0;
  if not Result then
    Exit;
  if (AFileLookup <> nil) and (AFileLookup.Count = 0) then
    MftBuildFileParentNameMap(ADB, AFileLookup);
  segToFolder := TDictionary<UInt64, Cardinal>.Create;
  renameOldNames := TDictionary<UInt64, string>.Create;
  renameFrns := TDictionary<UInt64, Byte>.Create;
  try
    BuildSegmentFolderMap(AFrnToFolder, segToFolder);
    for i := 0 to High(ARecords) do
    begin
      rec := ARecords[i];
      frnKey := FrnMapKey(ADriveIndex, rec.FRN);
      if IsUsnRenameReason(rec.Reason) then
        renameFrns.AddOrSetValue(frnKey, 1);
      if rec.FileName = '' then
        Continue;
      if (rec.Reason and USN_REASON_RENAME_OLD_NAME) = 0 then
        Continue;
      renameOldNames.AddOrSetValue(frnKey, rec.FileName);
    end;
    for i := 0 to High(ARecords) do
    begin
      rec := ARecords[i];
      frnKey := FrnMapKey(ADriveIndex, rec.FRN);
      isDir := IsUsnRecordDirectory(rec.FileAttributes, frnKey, AFrnToFolder, AFrnToFile);
      if IsUsnDeleteOnlyReason(rec.Reason) then
      begin
        if renameFrns.ContainsKey(frnKey) then
          Continue;
        if isDir then
        begin
          if AFrnToFolder.TryGetValue(frnKey, folderOff) then
          begin
            AppendIndexHitChange(AChanges, ihckFolderRemoved, FolderIndexToHitIndex(folderOff), 0);
            RemoveFilesUnderFolder(ADB, folderOff, AFrnToFile, AFileFrnKeys, AFileLookup, AChanges);
            AFrnToFolder.Remove(frnKey);
            RemoveSegmentFolderEntry(segToFolder, ADriveIndex, rec.FRN);
          end;
          if IsSystemFolderNameWide(rec.FileName) then
            if not AExcludedFrn.ContainsKey(frnKey) then
              AExcludedFrn.Add(frnKey, 1);
        end
        else
          RemoveFileByUsnRecord(ADB, ADriveIndex, rec, AFrnToFolder, AFrnToFile, AFileFrnKeys,
            AFileLookup, segToFolder, AStats, AChanges);
        Continue;
      end;
      if rec.FileName = '' then
        Continue;
      if not IsUsnUpsertReason(rec.Reason) then
        Continue;
      nameOff := AppendWideName(ADB, PWideChar(Pointer(rec.FileName)), Length(rec.FileName));
      if nameOff = 0 then
        Continue;
      if isDir then
      begin
        renameOldName := '';
        if not renameOldNames.TryGetValue(frnKey, renameOldName) then
          renameOldName := '';
        UpsertFolderRecord(ADB, ADriveIndex, rec, AFrnToFolder, AFrnToFile, AExcludedFrn,
          AFileFrnKeys, nameOff, renameOldName, AFileLookup, segToFolder, AChanges);
      end
      else
      begin
        renameOldName := '';
        if not renameOldNames.TryGetValue(frnKey, renameOldName) then
          renameOldName := '';
        UpsertFileRecord(ADB, ADriveIndex, rec, AFrnToFolder, AFrnToFile, AExcludedFrn,
          AFileFrnKeys, nameOff, renameOldName, AFileLookup, segToFolder, AStats, AChanges);
      end;
    end;
  finally
    segToFolder.Free;
    renameOldNames.Free;
    renameFrns.Free;
  end;
end;

end.
