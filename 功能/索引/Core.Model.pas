unit Core.Model;

interface

uses
  Windows;

const
  cRootParentOffset = Cardinal($FFFFFFFF);
  cMaxExtTable = 2048;
  cExtNameMaxLen = 15;

  USN_REASON_DATA_OVERWRITE = $00000001;
  USN_REASON_DATA_EXTEND = $00000002;
  USN_REASON_DATA_TRUNCATION = $00000004;
  USN_REASON_BASIC_INFO_CHANGE = $00000080;
  USN_REASON_FILE_CREATE = $00000100;
  USN_REASON_FILE_DELETE = $00000200;
  USN_REASON_RENAME_OLD_NAME = $00001000;
  USN_REASON_RENAME_NEW_NAME = $00002000;
  USN_REASON_CLOSE = $80000000;

  cUsnReasonMask = USN_REASON_FILE_CREATE or USN_REASON_FILE_DELETE or
    USN_REASON_RENAME_OLD_NAME or USN_REASON_RENAME_NEW_NAME or
    USN_REASON_BASIC_INFO_CHANGE or USN_REASON_DATA_OVERWRITE or
    USN_REASON_DATA_EXTEND or USN_REASON_DATA_TRUNCATION or USN_REASON_CLOSE;

type
  PExtEntry = ^TExtEntry;
  TExtEntry = packed record
    ExtID: Word;
    ExtName: array[0..cExtNameMaxLen] of AnsiChar;
  end;

  PFolderEntry = ^TFolderEntry;
  TFolderEntry = packed record
    FRN: UInt64;
    ParentOffset: Cardinal;
    NamePoolOffset: Cardinal;
    DateModified: Cardinal;
    Attributes: Word;
    DriveIndex: Byte;
    Padding: Byte;
  end;

  PFileEntry = ^TFileEntry;
  TFileEntry = packed record
    ParentOffset: Cardinal;
    NamePoolOffset: Cardinal;
    SizeLow: Cardinal;
    DateModifiedDelta: Word;
    ExtID: Word;
  end;

  TEverythingDB = record
    Folders: array of TFolderEntry;
    FolderCount: Integer;
    Files: array of TFileEntry;
    FileCount: Integer;
    NamePool: array of Byte;
    NamePoolUsed: Cardinal;
    ExtTable: array[0..cMaxExtTable - 1] of TExtEntry;
    ExtCount: Integer;
    VolumeBaseDate: Cardinal;
  end;

  TMftRawItem = record
    FRN: UInt64;
    ParentFRN: UInt64;
    NamePoolOffset: Cardinal;
    DateModified: Cardinal;
    Attributes: Word;
    SizeLow: Cardinal;
    IsDirectory: Boolean;
    DriveIndex: Byte;
    Excluded: Boolean;
  end;

  TUsnJournalRecord = record
    FRN: UInt64;
    ParentFRN: UInt64;
    Reason: DWORD;
    TimeStamp: Int64;
    FileAttributes: DWORD;
    FileName: string;
  end;

  TUsnJournalRecordArray = array of TUsnJournalRecord;

  TUsnCheckpoint = packed record
    JournalId: Int64;
    LastUsn: Int64;
  end;

  TUsnCheckpointArray = array[0..25] of TUsnCheckpoint;

  TDriveLetterMap = array[0..25] of Char;

  TFileFrnKeyArray = array of UInt64;

  TIndexHitChangeKind = (
    ihckFileRemoved,
    ihckFileRemapped,
    ihckFileAdded,
    ihckFileUpdated,
    ihckFolderRemoved,
    ihckFolderAdded,
    ihckFolderUpdated);

  TIndexHitChange = record
    Kind: TIndexHitChangeKind;
    HitIndex: Integer;
    NewHitIndex: Integer;
  end;

  TIndexHitChangeArray = array of TIndexHitChange;

  PIndexHitChangesMsg = ^TIndexHitChangesMsg;
  TIndexHitChangesMsg = record
    Changes: TIndexHitChangeArray;
  end;

implementation

end.
