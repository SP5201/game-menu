unit SearchVM;

interface

uses
  Windows, SysUtils, LibraryStore, Core.Model, Core.Memory;

type
  TSearchCancelledFunc = reference to function: Boolean;
  TSearchHitIndexArray = array of Integer;

  TSearchTiming = record
    CompileMs: Cardinal;
    ScanFileMs: Cardinal;
    ScanFolderMs: Cardinal;
    SanitizeMs: Cardinal;
    SortMs: Cardinal;
  end;

function SearchVMExecute(const ADB: TEverythingDB; const AQueryText: string;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean;
  const AIsCancelled: TSearchCancelledFunc; out AHitIndices: TSearchHitIndexArray;
  out ATotalCount: Cardinal; var ATiming: TSearchTiming;
  ASkipSort: Boolean = True): Boolean;

procedure SortHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);

function SearchVMBuildLazyPath(const ADB: TEverythingDB; AParentOffset: Cardinal;
  ADriveLetter: Char): string;

function SearchVMBuildFilePath(const ADB: TEverythingDB; AFileIndex: Integer;
  ADriveLetter: Char): string;

function SearchVMBuildFolderPath(const ADB: TEverythingDB; AFolderIndex: Integer;
  ADriveLetter: Char): string;

function SearchVMBuildHitPath(const ADB: TEverythingDB; AHitIndex: Integer;
  ADriveLetter: Char): string;

procedure SearchVMPatchHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  const AQuery: string; const AChanges: TIndexHitChangeArray);

implementation

uses
  SafeLog, Generics.Collections, Generics.Defaults;

const
  cCancelCheckMask = 4095;
  cHitGrowChunk = 4096;
  cMaxPathDepth = 256;
  cInsertionSortThreshold = 32;

function ShouldCancel(const AIsCancelled: TSearchCancelledFunc; AProgress: Integer): Boolean;
begin
  if (AProgress and cCancelCheckMask) <> 0 then
    Exit(False);
  Result := Assigned(AIsCancelled) and AIsCancelled();
end;

type
  TCompiledSearchPattern = record
    Raw: AnsiString;
    Segments: array of AnsiString;
    HasWildcard: Boolean;
    AnchorStart: Boolean;
    AnchorEnd: Boolean;
  end;

function AnsiCharLower(ACh: AnsiChar): AnsiChar;
begin
  if (ACh >= 'A') and (ACh <= 'Z') then
    Result := AnsiChar(Ord(ACh) + 32)
  else
    Result := ACh;
end;

function AnsiCharsEqualCI(ALeft, ARight: AnsiChar): Boolean;
begin
  Result := AnsiCharLower(ALeft) = AnsiCharLower(ARight);
end;

function AnsiStrLCompCI(const AText: PAnsiChar; const ASub: PAnsiChar; ALen: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (AText = nil) or (ASub = nil) or (ALen <= 0) then
    Exit;
  for i := 0 to ALen - 1 do
    if not AnsiCharsEqualCI(AText[i], ASub[i]) then
      Exit;
  Result := True;
end;

function AnsiStrPosCI(const AText, ASub: PAnsiChar): PAnsiChar;
var
  scanPtr, textPtr, subPtr, matchPtr: PAnsiChar;
begin
  Result := nil;
  if (AText = nil) or (AText^ = #0) then
    Exit;
  if (ASub = nil) or (ASub^ = #0) then
    Exit(AText);
  scanPtr := AText;
  while scanPtr^ <> #0 do
  begin
    textPtr := scanPtr;
    subPtr := ASub;
    matchPtr := scanPtr;
    while (subPtr^ <> #0) and (textPtr^ <> #0) and AnsiCharsEqualCI(textPtr^, subPtr^) do
    begin
      Inc(textPtr);
      Inc(subPtr);
    end;
    if subPtr^ = #0 then
      Exit(matchPtr);
    Inc(scanPtr);
  end;
end;

function QueryToUtf8Pattern(const AQuery: string): AnsiString;
var
  trimmed: string;
  wlen, n: Integer;
begin
  trimmed := Trim(AQuery);
  if trimmed = '' then
    Exit('');
  wlen := Length(trimmed);
  n := WideCharToMultiByte(CP_UTF8, 0, PWideChar(trimmed), wlen, nil, 0, nil, nil);
  SetLength(Result, n);
  if n > 0 then
    WideCharToMultiByte(CP_UTF8, 0, PWideChar(trimmed), wlen, PAnsiChar(Result), n, nil, nil);
  for n := 1 to Length(Result) do
    if (Result[n] >= 'A') and (Result[n] <= 'Z') then
      Result[n] := AnsiChar(Ord(Result[n]) + 32);
end;

function CompileSearchPattern(const AQuery: string): TCompiledSearchPattern;
var
  raw: AnsiString;
  i, start, segCount: Integer;
  part: AnsiString;
begin
  FillChar(Result, SizeOf(Result), 0);
  raw := QueryToUtf8Pattern(AQuery);
  Result.Raw := raw;
  if raw = '' then
    Exit;
  Result.HasWildcard := Pos('*', string(raw)) > 0;
  if not Result.HasWildcard then
    Exit;
  Result.AnchorStart := raw[1] <> '*';
  Result.AnchorEnd := raw[Length(raw)] <> '*';
  SetLength(Result.Segments, 0);
  start := 1;
  for i := 1 to Length(raw) do
  begin
    if raw[i] <> '*' then
      Continue;
    if i > start then
    begin
      part := Copy(raw, start, i - start);
      segCount := Length(Result.Segments);
      SetLength(Result.Segments, segCount + 1);
      Result.Segments[segCount] := part;
    end;
    start := i + 1;
  end;
  if start <= Length(raw) then
  begin
    part := Copy(raw, start, MaxInt);
    segCount := Length(Result.Segments);
    SetLength(Result.Segments, segCount + 1);
    Result.Segments[segCount] := part;
  end;
end;

function AnsiWildcardMatchCI(const AText: PAnsiChar; const APattern: TCompiledSearchPattern): Boolean;
var
  segCount, i, segLen, textLen, searchPos, endPos: Integer;
  foundPtr, partPtr: PAnsiChar;
begin
  Result := False;
  if (AText = nil) or (AText^ = #0) then
    Exit(Length(APattern.Segments) = 0);
  segCount := Length(APattern.Segments);
  if segCount = 0 then
    Exit(True);
  textLen := StrLen(AText);
  if segCount = 1 then
  begin
    partPtr := PAnsiChar(APattern.Segments[0]);
    segLen := Length(APattern.Segments[0]);
    if APattern.AnchorStart and APattern.AnchorEnd then
      Exit((segLen = textLen) and AnsiStrLCompCI(AText, partPtr, segLen));
    if APattern.AnchorStart then
      Exit((segLen <= textLen) and AnsiStrLCompCI(AText, partPtr, segLen));
    if APattern.AnchorEnd then
      Exit((segLen <= textLen) and AnsiStrLCompCI(AText + textLen - segLen, partPtr, segLen));
    Exit(AnsiStrPosCI(AText, partPtr) <> nil);
  end;
  if APattern.AnchorStart then
  begin
    partPtr := PAnsiChar(APattern.Segments[0]);
    segLen := Length(APattern.Segments[0]);
    if (segLen > textLen) or not AnsiStrLCompCI(AText, partPtr, segLen) then
      Exit;
    searchPos := segLen;
    i := 1;
  end
  else
  begin
    foundPtr := AnsiStrPosCI(AText, PAnsiChar(APattern.Segments[0]));
    if foundPtr = nil then
      Exit;
    searchPos := (foundPtr - AText) + Length(APattern.Segments[0]);
    i := 1;
  end;
  while i < segCount - 1 do
  begin
    foundPtr := AnsiStrPosCI(AText + searchPos, PAnsiChar(APattern.Segments[i]));
    if foundPtr = nil then
      Exit;
    searchPos := searchPos + (foundPtr - (AText + searchPos)) + Length(APattern.Segments[i]);
    Inc(i);
  end;
  partPtr := PAnsiChar(APattern.Segments[segCount - 1]);
  segLen := Length(APattern.Segments[segCount - 1]);
  if APattern.AnchorEnd then
  begin
    if segLen > textLen then
      Exit;
    endPos := textLen - segLen;
    if searchPos > endPos then
      Exit;
    Exit(AnsiStrLCompCI(AText + endPos, partPtr, segLen));
  end;
  Result := AnsiStrPosCI(AText + searchPos, partPtr) <> nil;
end;

function NamePoolContainsPattern(const ADB: TEverythingDB; ANameOffset: Cardinal;
  const APattern: TCompiledSearchPattern): Boolean;
var
  namePtr: PAnsiChar;
begin
  Result := False;
  if APattern.Raw = '' then
    Exit(True);
  if not NamePoolOffsetIsValid(ADB, ANameOffset) then
    Exit;
  namePtr := PAnsiChar(@ADB.NamePool[ANameOffset]);
  if namePtr^ = #0 then
    Exit;
  if not APattern.HasWildcard then
    Result := AnsiStrPosCI(namePtr, PAnsiChar(APattern.Raw)) <> nil
  else
    Result := AnsiWildcardMatchCI(namePtr, APattern);
end;

function NameMatchesPattern(const ADB: TEverythingDB; ANameOffset: Cardinal;
  const APattern: TCompiledSearchPattern): Boolean;
begin
  Result := NamePoolContainsPattern(ADB, ANameOffset, APattern);
end;

function FolderOffsetIsValid(const ADB: TEverythingDB; AOffset: Cardinal): Boolean;
begin
  if (AOffset = cRootParentOffset) or (Integer(AOffset) < 0) then
    Exit(False);
  Result := (Integer(AOffset) < ADB.FolderCount) and (Integer(AOffset) < Length(ADB.Folders));
end;

function FileMatchesPattern(const ADB: TEverythingDB; AFileIndex: Integer;
  const APattern: TCompiledSearchPattern): Boolean;
begin
  Result := False;
  if (AFileIndex < 0) or (AFileIndex >= ADB.FileCount) or (AFileIndex >= Length(ADB.Files)) then
    Exit;
  Result := NameMatchesPattern(ADB, ADB.Files[AFileIndex].NamePoolOffset, APattern);
end;

function FolderMatchesPattern(const ADB: TEverythingDB; AFolderIndex: Integer;
  const APattern: TCompiledSearchPattern): Boolean;
begin
  Result := False;
  if (AFolderIndex < 0) or (AFolderIndex >= ADB.FolderCount) or
    (AFolderIndex >= Length(ADB.Folders)) then
    Exit;
  Result := NameMatchesPattern(ADB, ADB.Folders[AFolderIndex].NamePoolOffset, APattern);
end;

function HitIsFolder(const AHitIndex: Integer): Boolean;
begin
  Result := AHitIndex < 0;
end;

function HitFolderIndex(const AHitIndex: Integer): Integer;
begin
  Result := -(AHitIndex + 1);
end;

function HitIndexIsValid(const ADB: TEverythingDB; AIndex: Integer): Boolean;
var
  folderIdx: Integer;
begin
  if AIndex >= 0 then
    Result := (AIndex < ADB.FileCount) and (AIndex < Length(ADB.Files))
  else
  begin
    folderIdx := HitFolderIndex(AIndex);
    Result := (folderIdx >= 0) and (folderIdx < ADB.FolderCount) and (folderIdx < Length(ADB.Folders));
  end;
end;

function HitNamePoolOffset(const ADB: TEverythingDB; AHitIndex: Integer): Cardinal;
begin
  if HitIsFolder(AHitIndex) then
    Result := ADB.Folders[HitFolderIndex(AHitIndex)].NamePoolOffset
  else
    Result := ADB.Files[AHitIndex].NamePoolOffset;
end;

function HitIndexHasResolvableName(const ADB: TEverythingDB; AIndex: Integer): Boolean;
var
  nameOffset: Cardinal;
  namePtr: PAnsiChar;
begin
  Result := False;
  if not HitIndexIsValid(ADB, AIndex) then
    Exit;
  nameOffset := HitNamePoolOffset(ADB, AIndex);
  namePtr := NamePoolPtrAt(ADB, nameOffset);
  Result := (namePtr <> nil) and (namePtr^ <> #0);
end;

procedure SanitizeHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB);
var
  i, n, valid: Integer;
begin
  n := Length(AHits);
  valid := 0;
  for i := 0 to n - 1 do
    if HitIndexHasResolvableName(ADB, AHits[i]) then
    begin
      if valid <> i then
        AHits[valid] := AHits[i];
      Inc(valid);
    end;
  SetLength(AHits, valid);
end;

function CompareHitIndices(const ADB: TEverythingDB; const ALeft, ARight: Integer;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean): Integer;
var
  leftFile, rightFile: TFileEntry;
  leftFolder, rightFolder: TFolderEntry;
  leftTime, rightTime: Integer;
  leftExtPtr, rightExtPtr: PAnsiChar;
begin
  if not HitIndexIsValid(ADB, ALeft) then
  begin
    if HitIndexIsValid(ADB, ARight) then
      Exit(-1);
    Exit(0);
  end;
  if not HitIndexIsValid(ADB, ARight) then
    Exit(1);
  case ASortKind of
    llskFileType:
      begin
        if HitIsFolder(ALeft) then
          leftExtPtr := nil
        else
        begin
          leftFile := ADB.Files[ALeft];
          if (leftFile.ExtID > 0) and (leftFile.ExtID <= ADB.ExtCount) then
            leftExtPtr := @ADB.ExtTable[leftFile.ExtID - 1].ExtName[0]
          else
            leftExtPtr := nil;
        end;
        if HitIsFolder(ARight) then
          rightExtPtr := nil
        else
        begin
          rightFile := ADB.Files[ARight];
          if (rightFile.ExtID > 0) and (rightFile.ExtID <= ADB.ExtCount) then
            rightExtPtr := @ADB.ExtTable[rightFile.ExtID - 1].ExtName[0]
          else
            rightExtPtr := nil;
        end;
        Result := CompareAnsiPtrTextCI(leftExtPtr, rightExtPtr);
      end;
    llskAddTime:
      begin
        if HitIsFolder(ALeft) then
        begin
          leftFolder := ADB.Folders[HitFolderIndex(ALeft)];
          leftTime := Integer(leftFolder.DateModified);
        end
        else
        begin
          leftFile := ADB.Files[ALeft];
          leftTime := Integer(leftFile.DateModifiedDelta);
        end;
        if HitIsFolder(ARight) then
        begin
          rightFolder := ADB.Folders[HitFolderIndex(ARight)];
          rightTime := Integer(rightFolder.DateModified);
        end
        else
        begin
          rightFile := ADB.Files[ARight];
          rightTime := Integer(rightFile.DateModifiedDelta);
        end;
        Result := leftTime - rightTime;
      end;
  else
    Result := NamePoolCompareText(ADB, HitNamePoolOffset(ADB, ALeft),
      HitNamePoolOffset(ADB, ARight));
  end;
  if not ASortAsc then
    Result := -Result;
end;

procedure InsertionSortHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
var
  i, j, n, tmp: Integer;
begin
  n := Length(AHits);
  if n < 2 then
    Exit;
  for i := 1 to n - 1 do
  begin
    tmp := AHits[i];
    j := i - 1;
    while (j >= 0) and (CompareHitIndices(ADB, AHits[j], tmp, ASortKind, ASortAsc) > 0) do
    begin
      AHits[j + 1] := AHits[j];
      Dec(j);
    end;
    AHits[j + 1] := tmp;
  end;
end;

type
  THitSortSlot = record
    Hit: Integer;
    KeyTime: Integer;
    NamePtr: PAnsiChar;
    ExtPtr: PAnsiChar;
  end;

  THitSortSlotComparer = class(TComparer<THitSortSlot>)
  private
    FSortKind: TLibraryListSortKind;
    FSortAsc: Boolean;
  public
    constructor Create(ASortKind: TLibraryListSortKind; ASortAsc: Boolean);
    function Compare(const Left, Right: THitSortSlot): Integer; override;
  end;

constructor THitSortSlotComparer.Create(ASortKind: TLibraryListSortKind; ASortAsc: Boolean);
begin
  inherited Create;
  FSortKind := ASortKind;
  FSortAsc := ASortAsc;
end;

function THitSortSlotComparer.Compare(const Left, Right: THitSortSlot): Integer;
begin
  case FSortKind of
    llskFileType:
      Result := CompareAnsiPtrTextCI(Left.ExtPtr, Right.ExtPtr);
    llskAddTime:
      Result := Left.KeyTime - Right.KeyTime;
  else
    Result := CompareAnsiPtrTextCI(Left.NamePtr, Right.NamePtr);
  end;
  if not FSortAsc then
    Result := -Result;
end;

procedure FillHitSortSlots(const AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  var ASlots: array of THitSortSlot);
var
  i, hit, folderIdx: Integer;
  fileEntry: TFileEntry;
begin
  for i := 0 to High(AHits) do
  begin
    hit := AHits[i];
    ASlots[i].Hit := hit;
    ASlots[i].NamePtr := NamePoolPtrAt(ADB, HitNamePoolOffset(ADB, hit));
    ASlots[i].KeyTime := 0;
    ASlots[i].ExtPtr := nil;
    if HitIsFolder(hit) then
    begin
      folderIdx := HitFolderIndex(hit);
      if (folderIdx >= 0) and (folderIdx < ADB.FolderCount) then
        ASlots[i].KeyTime := Integer(ADB.Folders[folderIdx].DateModified);
      Continue;
    end;
    if (hit < 0) or (hit >= ADB.FileCount) then
      Continue;
    fileEntry := ADB.Files[hit];
    ASlots[i].KeyTime := Integer(fileEntry.DateModifiedDelta);
    if (fileEntry.ExtID > 0) and (fileEntry.ExtID <= ADB.ExtCount) then
      ASlots[i].ExtPtr := @ADB.ExtTable[fileEntry.ExtID - 1].ExtName[0];
  end;
end;

procedure SortHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
var
  n, i: Integer;
  slots: array of THitSortSlot;
  comparer: THitSortSlotComparer;
begin
  n := Length(AHits);
  if n < 2 then
    Exit;
  if n <= cInsertionSortThreshold then
  begin
    InsertionSortHitIndices(AHits, ADB, ASortKind, ASortAsc);
    Exit;
  end;
  SetLength(slots, n);
  FillHitSortSlots(AHits, ADB, slots);
  comparer := THitSortSlotComparer.Create(ASortKind, ASortAsc);
  try
    TArray.Sort<THitSortSlot>(slots, comparer);
  finally
    comparer.Free;
  end;
  for i := 0 to n - 1 do
    AHits[i] := slots[i].Hit;
end;

function SearchVMBuildLazyPath(const ADB: TEverythingDB; AParentOffset: Cardinal;
  ADriveLetter: Char): string;
var
  parts: array of string;
  off, nextOff: Cardinal;
  partCount, i, depth: Integer;
  folder: TFolderEntry;
  folderName: string;
begin
  Result := ADriveLetter + ':\';
  if (Length(ADB.Folders) = 0) or (ADB.FolderCount <= 0) then
    Exit;
  SetLength(parts, 0);
  off := AParentOffset;
  depth := 0;
  while (off <> cRootParentOffset) and (depth < cMaxPathDepth) do
  begin
    if not FolderOffsetIsValid(ADB, off) then
      Break;
    folder := ADB.Folders[off];
    if not NamePoolOffsetIsValid(ADB, folder.NamePoolOffset) then
      Break;
    folderName := NamePoolToString(ADB, folder.NamePoolOffset);
    if folderName <> '' then
    begin
      partCount := Length(parts);
      SetLength(parts, partCount + 1);
      parts[partCount] := folderName;
    end;
    nextOff := folder.ParentOffset;
    if (nextOff = off) or (nextOff = cRootParentOffset) then
      Break;
    if not FolderOffsetIsValid(ADB, nextOff) then
      Break;
    off := nextOff;
    Inc(depth);
  end;
  if Length(parts) > 0 then
    for i := High(parts) downto 0 do
      Result := Result + parts[i] + '\';
end;

function SearchVMBuildFilePath(const ADB: TEverythingDB; AFileIndex: Integer;
  ADriveLetter: Char): string;
var
  parent: Cardinal;
  fileEntry: TFileEntry;
  fileName: string;
begin
  Result := '';
  if (AFileIndex < 0) or (AFileIndex >= ADB.FileCount) or (AFileIndex >= Length(ADB.Files)) then
    Exit;
  fileEntry := ADB.Files[AFileIndex];
  if not NamePoolOffsetIsValid(ADB, fileEntry.NamePoolOffset) then
    Exit;
  parent := fileEntry.ParentOffset;
  fileName := NamePoolToString(ADB, fileEntry.NamePoolOffset);
  if fileName = '' then
    Exit;
  Result := SearchVMBuildLazyPath(ADB, parent, ADriveLetter) + fileName;
end;

function SearchVMBuildFolderPath(const ADB: TEverythingDB; AFolderIndex: Integer;
  ADriveLetter: Char): string;
var
  folder: TFolderEntry;
  folderName: string;
begin
  Result := '';
  if (AFolderIndex < 0) or (AFolderIndex >= ADB.FolderCount) or (AFolderIndex >= Length(ADB.Folders)) then
    Exit;
  folder := ADB.Folders[AFolderIndex];
  if not NamePoolOffsetIsValid(ADB, folder.NamePoolOffset) then
    Exit;
  folderName := NamePoolToString(ADB, folder.NamePoolOffset);
  if folderName = '' then
    Exit;
  Result := SearchVMBuildLazyPath(ADB, folder.ParentOffset, ADriveLetter) + folderName + '\';
end;

function SearchVMBuildHitPath(const ADB: TEverythingDB; AHitIndex: Integer;
  ADriveLetter: Char): string;
begin
  Result := '';
  if not HitIndexIsValid(ADB, AHitIndex) then
    Exit;
  if HitIsFolder(AHitIndex) then
    Result := SearchVMBuildFolderPath(ADB, HitFolderIndex(AHitIndex), ADriveLetter)
  else
    Result := SearchVMBuildFilePath(ADB, AHitIndex, ADriveLetter);
end;

function SearchVMExecute(const ADB: TEverythingDB; const AQueryText: string;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean;
  const AIsCancelled: TSearchCancelledFunc; out AHitIndices: TSearchHitIndexArray;
  out ATotalCount: Cardinal; var ATiming: TSearchTiming; ASkipSort: Boolean): Boolean;
var
  pattern: TCompiledSearchPattern;
  i, hitCap, hitCount, totalMatched: Integer;
  phaseStart: Cardinal;
begin
  Result := False;
  SetLength(AHitIndices, 0);
  ATotalCount := 0;
  FillChar(ATiming, SizeOf(TSearchTiming), 0);
  if (ADB.FileCount <= 0) and (ADB.FolderCount <= 0) then
    Exit(True);
  phaseStart := GetTickCount;
  pattern := CompileSearchPattern(AQueryText);
  ATiming.CompileMs := GetTickCount - phaseStart;
  hitCap := 0;
  hitCount := 0;
  totalMatched := 0;
  phaseStart := GetTickCount;
  for i := 0 to ADB.FileCount - 1 do
  begin
    if ShouldCancel(AIsCancelled, i) then
      Exit;
    if not FileMatchesPattern(ADB, i, pattern) then
      Continue;
    Inc(totalMatched);
    if hitCount >= hitCap then
    begin
      Inc(hitCap, cHitGrowChunk);
      SetLength(AHitIndices, hitCap);
    end;
    AHitIndices[hitCount] := i;
    Inc(hitCount);
  end;
  ATiming.ScanFileMs := GetTickCount - phaseStart;
  phaseStart := GetTickCount;
  for i := 0 to ADB.FolderCount - 1 do
  begin
    if ShouldCancel(AIsCancelled, ADB.FileCount + i) then
      Exit;
    if not FolderMatchesPattern(ADB, i, pattern) then
      Continue;
    Inc(totalMatched);
    if hitCount >= hitCap then
    begin
      Inc(hitCap, cHitGrowChunk);
      SetLength(AHitIndices, hitCap);
    end;
    AHitIndices[hitCount] := -(i + 1);
    Inc(hitCount);
  end;
  ATiming.ScanFolderMs := GetTickCount - phaseStart;
  SetLength(AHitIndices, hitCount);
  phaseStart := GetTickCount;
  SanitizeHitIndices(AHitIndices, ADB);
  ATiming.SanitizeMs := GetTickCount - phaseStart;
  ATotalCount := Cardinal(totalMatched);
  if (not ASkipSort) and (Length(AHitIndices) > 1) then
  begin
    phaseStart := GetTickCount;
    SortHitIndices(AHitIndices, ADB, ASortKind, ASortAsc);
    ATiming.SortMs := GetTickCount - phaseStart;
  end;
  Result := True;
end;

function HitMatchesPattern(const ADB: TEverythingDB; AHitIndex: Integer;
  const APattern: TCompiledSearchPattern): Boolean;
begin
  if HitIsFolder(AHitIndex) then
    Result := FolderMatchesPattern(ADB, HitFolderIndex(AHitIndex), APattern)
  else
    Result := FileMatchesPattern(ADB, AHitIndex, APattern);
end;

procedure RemapHitIndex(var AHits: TSearchHitIndexArray; AOldIndex, ANewIndex: Integer);
var
  i: Integer;
begin
  for i := 0 to High(AHits) do
    if AHits[i] = AOldIndex then
      AHits[i] := ANewIndex;
end;

procedure RemoveHitIndex(var AHits: TSearchHitIndexArray; AHitIndex: Integer);
var
  i, n, w: Integer;
begin
  n := Length(AHits);
  w := 0;
  for i := 0 to n - 1 do
    if AHits[i] <> AHitIndex then
    begin
      AHits[w] := AHits[i];
      Inc(w);
    end;
  SetLength(AHits, w);
end;

function ContainsHitIndex(const AHits: TSearchHitIndexArray; AHitIndex: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(AHits) do
    if AHits[i] = AHitIndex then
      Exit(True);
  Result := False;
end;

procedure AppendHitIndex(var AHits: TSearchHitIndexArray; AHitIndex: Integer);
var
  n: Integer;
begin
  if ContainsHitIndex(AHits, AHitIndex) then
    Exit;
  n := Length(AHits);
  SetLength(AHits, n + 1);
  AHits[n] := AHitIndex;
end;

procedure PatchUpdatedHit(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  AHitIndex: Integer; const APattern: TCompiledSearchPattern);
begin
  if ContainsHitIndex(AHits, AHitIndex) then
  begin
    if not HitMatchesPattern(ADB, AHitIndex, APattern) then
      RemoveHitIndex(AHits, AHitIndex);
  end
  else if HitMatchesPattern(ADB, AHitIndex, APattern) then
    AppendHitIndex(AHits, AHitIndex);
end;

procedure SearchVMPatchHitIndices(var AHits: TSearchHitIndexArray; const ADB: TEverythingDB;
  const AQuery: string; const AChanges: TIndexHitChangeArray);
var
  i: Integer;
  pattern: TCompiledSearchPattern;
  ch: TIndexHitChange;
begin
  if (Length(AChanges) = 0) or (Trim(AQuery) = '') then
    Exit;
  pattern := CompileSearchPattern(AQuery);
  for i := 0 to High(AChanges) do
  begin
    ch := AChanges[i];
    case ch.Kind of
      ihckFileRemapped:
        RemapHitIndex(AHits, ch.HitIndex, ch.NewHitIndex);
      ihckFileRemoved, ihckFolderRemoved:
        RemoveHitIndex(AHits, ch.HitIndex);
      ihckFileUpdated, ihckFolderUpdated:
        PatchUpdatedHit(AHits, ADB, ch.HitIndex, pattern);
      ihckFileAdded, ihckFolderAdded:
        if HitMatchesPattern(ADB, ch.HitIndex, pattern) then
          AppendHitIndex(AHits, ch.HitIndex);
    end;
  end;
  SanitizeHitIndices(AHits, ADB);
end;

end.
