module dzipper.model;

import std.traits : FieldNameTuple;
import std.format : FormatSpec;
import std.array : appender;
import std.conv : to;
import std.range : put;

private mixin template StructToString(S)
{
    void toString(scope void delegate(const(char)[]) sink,
        FormatSpec!char fmt)
    {
        put(sink, typeid(S).toString);
        put(sink, "(\n");
        foreach (index, name; FieldNameTuple!S)
        {
            put(sink, "  ");
            put(sink, name);
            put(sink, ": ");
            put(sink, this.tupleof[index].to!string);
            put(sink, ",\n");
        }
        put(sink, ")");
    }
}

/// End of central directory record.
struct EndOfCentralDirectory
{
    ushort diskNumber;
    ushort centralDirectoryDiskNumber;
    ushort diskCentralDirectoriesCount;
    ushort totalCentralDirectoriesCount;
    uint centralDirectorySize;
    uint startOfCentralDirectory;
    ushort commentLength;
    ubyte[] comment;
    mixin StructToString!EndOfCentralDirectory;
}

private mixin template FileInformation()
{
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

/// Central directory header.
struct CentralDirectory
{
    mixin FileInformation;
    ushort versionMadeBy;
    ushort commentLength;
    ushort diskNumber;
    ushort internalFileAttributes;
    uint externalFileAttributes;
    uint startOfLocalFileHeader;
    ubyte[] comment;
    mixin StructToString!CentralDirectory;

    /// The length of the CD in bytes (notice that the struct
    /// does not include the CD signature).
    size_t length()
    {
        return 46 + fileName.length + extraField.length + comment.length;
    }
}

/// Local file header.
struct LocalFileHeader
{
    mixin FileInformation;
    mixin StructToString!LocalFileHeader;
}
