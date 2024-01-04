module model;

struct EndOfCentralDirectory {
    ushort diskNumber;
    ushort centralDirectoryDiskNumber;
    ushort diskCentralDirectoriesCount;
    ushort totalCentralDirectoriesCount;
    uint centralDirectorySize;
    uint startOfCentralDirectory;
    ushort commentLength;
    ubyte[] comment;
}

private mixin template FileInformation() {
    ushort versionRequired;
    ushort generalPurposeBitFlag;
    ushort compressionMethod;
    ushort lastModificationTime;
    ushort lastModificationDate;
    uint crc32;
    uint compressedSize;
    uint uncompressedSize;
    ushort fileNameLength;
    ushort extraFieldLength;
    ubyte[] fileName;
    ubyte[] extraField;
}

struct CentralDirectory {
    mixin FileInformation;
    ushort versionMadeBy;
    ushort commentLength;
    ushort diskNumber;
    ushort internalFileAttributes;
    uint externalFileAttributes;
    uint startOfLocalFileHeader;
    ubyte[] comment;
}

struct LocalFileHeader {
    mixin FileInformation;
}
