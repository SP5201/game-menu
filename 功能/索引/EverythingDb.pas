unit EverythingDb;

interface

uses
  SysUtils, Classes, Core.Model;

const
  cEverythingDbMagic = $45564944; // 'EVID'
  cEverythingDbVersion = 7;

function EverythingDbFilePath: string;
function EverythingDbSave(const ADB: TEverythingDB;
  const ADriveLetterMap: TDriveLetterMap; const AFileFrnKeys: TFileFrnKeyArray;
  const AUsnCheckpoints: TUsnCheckpointArray; const APath: string = ''): Boolean;
function EverythingDbLoad(var ADB: TEverythingDB; var ADriveLetterMap: TDriveLetterMap;
  out AFileFrnKeys: TFileFrnKeyArray; out AUsnCheckpoints: TUsnCheckpointArray;
  const APath: string = ''): Boolean;
procedure EverythingDbClear(var ADB: TEverythingDB);

implementation

uses
  Winapi.Windows, AppConfig;

type
  TEverythingDbHeader = packed record
    Magic: Cardinal;
    Version: Cardinal;
    FolderCount: Cardinal;
    FileCount: Cardinal;
    NamePoolUsed: Cardinal;
    ExtCount: Integer;
    VolumeBaseDate: Cardinal;
    DriveLetters: array[0..25] of AnsiChar;
  end;

function EverythingDbFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(TAppConfig.DataDirectory) + 'Everything.db';
end;

procedure EverythingDbClear(var ADB: TEverythingDB);
begin
  SetLength(ADB.Folders, 0);
  SetLength(ADB.Files, 0);
  SetLength(ADB.NamePool, 0);
  ADB.FolderCount := 0;
  ADB.FileCount := 0;
  ADB.NamePoolUsed := 0;
  ADB.ExtCount := 0;
  ADB.VolumeBaseDate := 0;
  FillChar(ADB.ExtTable, SizeOf(ADB.ExtTable), 0);
end;

function EverythingDbSave(const ADB: TEverythingDB;
  const ADriveLetterMap: TDriveLetterMap; const AFileFrnKeys: TFileFrnKeyArray;
  const AUsnCheckpoints: TUsnCheckpointArray; const APath: string): Boolean;
var
  path, tmpPath: string;
  fs: TFileStream;
  hdr: TEverythingDbHeader;
  folderBytes, fileBytes, poolBytes, extBytes, frnBytes, checkpointBytes: Integer;
  i: Integer;
begin
  Result := False;
  path := APath;
  if path = '' then
    path := EverythingDbFilePath;
  tmpPath := path + '.tmp';
  ForceDirectories(ExtractFilePath(path));
  fs := TFileStream.Create(tmpPath, fmCreate);
  try
    FillChar(hdr, SizeOf(hdr), 0);
    hdr.Magic := cEverythingDbMagic;
    hdr.Version := cEverythingDbVersion;
    hdr.FolderCount := Cardinal(ADB.FolderCount);
    hdr.FileCount := Cardinal(ADB.FileCount);
    hdr.NamePoolUsed := ADB.NamePoolUsed;
    hdr.ExtCount := ADB.ExtCount;
    hdr.VolumeBaseDate := ADB.VolumeBaseDate;
    for i := 0 to 25 do
      if ADriveLetterMap[i] <> #0 then
        hdr.DriveLetters[i] := AnsiChar(ADriveLetterMap[i]);
    fs.WriteBuffer(hdr, SizeOf(hdr));

    folderBytes := ADB.FolderCount * SizeOf(TFolderEntry);
    if folderBytes > 0 then
      fs.WriteBuffer(ADB.Folders[0], folderBytes);

    fileBytes := ADB.FileCount * SizeOf(TFileEntry);
    if fileBytes > 0 then
      fs.WriteBuffer(ADB.Files[0], fileBytes);

    poolBytes := ADB.NamePoolUsed;
    if poolBytes > 0 then
      fs.WriteBuffer(ADB.NamePool[0], poolBytes);

    extBytes := ADB.ExtCount * SizeOf(TExtEntry);
    if extBytes > 0 then
      fs.WriteBuffer(ADB.ExtTable[0], extBytes);

    frnBytes := ADB.FileCount * SizeOf(UInt64);
    if (frnBytes > 0) and (Length(AFileFrnKeys) >= ADB.FileCount) then
      fs.WriteBuffer(AFileFrnKeys[0], frnBytes);

    checkpointBytes := SizeOf(TUsnCheckpointArray);
    fs.WriteBuffer(AUsnCheckpoints[0], checkpointBytes);
  finally
    fs.Free;
  end;
  if FileExists(path) then
    SysUtils.DeleteFile(path);
  if SysUtils.RenameFile(tmpPath, path) then
    Result := True
  else
    SysUtils.DeleteFile(tmpPath);
end;

function EverythingDbLoad(var ADB: TEverythingDB; var ADriveLetterMap: TDriveLetterMap;
  out AFileFrnKeys: TFileFrnKeyArray; out AUsnCheckpoints: TUsnCheckpointArray;
  const APath: string): Boolean;
var
  path: string;
  fs: TFileStream;
  hdr: TEverythingDbHeader;
  folderBytes, fileBytes, poolBytes, extBytes, frnBytes, checkpointBytes: Integer;
  minSize: Int64;
  i: Integer;
begin
  Result := False;
  EverythingDbClear(ADB);
  SetLength(AFileFrnKeys, 0);
  FillChar(ADriveLetterMap, SizeOf(TDriveLetterMap), 0);
  FillChar(AUsnCheckpoints, SizeOf(AUsnCheckpoints), 0);
  path := APath;
  if path = '' then
    path := EverythingDbFilePath;
  if not FileExists(path) then
    Exit;
  fs := TFileStream.Create(path, fmOpenRead or fmShareDenyWrite);
  try
    if fs.Size < SizeOf(hdr) then
      Exit;
    fs.ReadBuffer(hdr, SizeOf(hdr));
    if hdr.Magic <> cEverythingDbMagic then
      Exit;
    if hdr.Version <> cEverythingDbVersion then
      Exit;

    folderBytes := Integer(hdr.FolderCount) * SizeOf(TFolderEntry);
    fileBytes := Integer(hdr.FileCount) * SizeOf(TFileEntry);
    poolBytes := Integer(hdr.NamePoolUsed);
    extBytes := hdr.ExtCount * SizeOf(TExtEntry);
    frnBytes := Integer(hdr.FileCount) * SizeOf(UInt64);
    checkpointBytes := SizeOf(TUsnCheckpointArray);
    minSize := Int64(SizeOf(hdr) + folderBytes + fileBytes + poolBytes + extBytes +
      frnBytes + checkpointBytes);
    if fs.Size < minSize then
      Exit;

    ADB.FolderCount := Integer(hdr.FolderCount);
    ADB.FileCount := Integer(hdr.FileCount);
    ADB.NamePoolUsed := hdr.NamePoolUsed;
    ADB.ExtCount := hdr.ExtCount;
    ADB.VolumeBaseDate := hdr.VolumeBaseDate;
    for i := 0 to 25 do
      if hdr.DriveLetters[i] <> #0 then
        ADriveLetterMap[i] := Char(hdr.DriveLetters[i]);

    if folderBytes > 0 then
    begin
      SetLength(ADB.Folders, ADB.FolderCount);
      fs.ReadBuffer(ADB.Folders[0], folderBytes);
    end;
    if fileBytes > 0 then
    begin
      SetLength(ADB.Files, ADB.FileCount);
      fs.ReadBuffer(ADB.Files[0], fileBytes);
    end;
    if poolBytes > 0 then
    begin
      SetLength(ADB.NamePool, poolBytes);
      fs.ReadBuffer(ADB.NamePool[0], poolBytes);
    end;
    if extBytes > 0 then
      fs.ReadBuffer(ADB.ExtTable[0], extBytes);
    if frnBytes > 0 then
    begin
      SetLength(AFileFrnKeys, ADB.FileCount);
      fs.ReadBuffer(AFileFrnKeys[0], frnBytes);
    end;
    fs.ReadBuffer(AUsnCheckpoints[0], checkpointBytes);
    Result := True;
  finally
    fs.Free;
  end;
end;

end.
