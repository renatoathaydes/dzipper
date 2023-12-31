module dzipper.model;

import std.traits : FieldNameTuple;
import std.format : FormatSpec;
import std.array : appender;
import std.conv : to;
import std.range : put;
import std.datetime.systime : SysTime;

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

/// Zip Archive compression methods.
enum CompressionMethod : ushort
{
    stored,
    shrunk,
    reduced_1,
    reduced_2,
    reduced_3,
    reduced_4,
    implodded,
    reserved_for_tokenizing,
    deflated,
    deflate_64,
    pkware_imploding,
    reserved_pkware_1,
    bzip_2,
    reserved_pkware_2,
    lzma,
    reserved_pkware_3,
    cmpsc,
    reserved_pkware_4,
    ibm_terse_new,
    ibm_lz_77,
    deprecated_zstd,
    zstd = 93,
    mp3,
    xz,
    jpeg,
    wavpack,
    ppmd_version_1,
    ae_x_enc,
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
    CompressionMethod compressionMethod;
    SysTime lastModificationDateTime;
    uint crc32;
    uint compressedSize;
    uint uncompressedSize;
    ushort fileNameLength;
    ushort extraFieldLength;
    char[] fileName;
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

    /// The length of the header in bytes (notice that the struct
    /// does not include the local file header signature).
    size_t length()
    {
        return 30 + fileName.length + extraField.length;
    }

}
