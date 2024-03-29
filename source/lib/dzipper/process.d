module dzipper.process;

import std.stdio : File, writeln;
import std.range : iota;
import std.file : remove, tempDir;
import std.bitmanip : append, Endian;
import std.array : appender, array;
import std.typecons : Nullable;
import std.conv : to;
import std.algorithm.comparison : min;
import std.path : chainPath;
import std.random : uniform;

import dzipper.model, dzipper.parser;

/// Metadata for a zip archive.
struct ZipArchiveMetadata
{
    Nullable!size_t zipStart;
    double totalCompressed;
    double totalUncompressed;
    uint[CompressionMethod] compressionMethodCount;
    CentralDirectory[] centralDirectories;
    LocalFileHeader[] localFileHeaders;
    EndOfCentralDirectory eocd;
}

/// Parse and collect all the Zip archive metadata.
///
/// Params:
///   bytes = zip archive source of bytes
///   eocd = end of central directory structure
/// Returns: the metadata for the zip archive.
ZipArchiveMetadata getArchiveMetadata(B)(ref B bytes, ref EndOfCentralDirectory eocd)
{
    Nullable!size_t zipStart;
    uint offset = eocd.startOfCentralDirectory;
    double totalCompressed = 0;
    double totalUncompressed = 0;
    uint[CompressionMethod] compressionCount;
    auto fileHeaders = new LocalFileHeader[eocd.diskCentralDirectoriesCount];
    auto centralDirs = new CentralDirectory[eocd.diskCentralDirectoriesCount];
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(cast(ubyte[]) bytes[offset .. $]);
        centralDirs[i] = cd;
        zipStart = zipStart.isNull
            ? cd.startOfLocalFileHeader
            : min(cd.startOfLocalFileHeader, zipStart.get);
        totalCompressed += cd.compressedSize;
        totalUncompressed += cd.uncompressedSize;
        offset += cd.length;
        compressionCount.require(cd.compressionMethod)++;
        auto lfh = parseLocalFileHeader(cast(ubyte[]) bytes[cd.startOfLocalFileHeader .. $]);
        fileHeaders[i] = lfh;
    }
    ZipArchiveMetadata result = {
        zipStart: zipStart,
        totalCompressed: totalCompressed,
        totalUncompressed: totalUncompressed,
        compressionMethodCount: compressionCount,
        centralDirectories: centralDirs,
        localFileHeaders: fileHeaders,
        eocd: eocd,
    };
    return result;
}

/// Prepend the contents of a file into the zip archive.
///
/// This function works by first copying the contents of `prependFile` into a temp file,
/// then writing the zip archive's contents into the temp file while shifting the zip metadata
/// entries' offsets as necessary.
///
/// Params:
///   bytes = zip archive source of bytes
///   prependFile = file to prepend
///   meta = the zip archive metadata
///   verbose = whether to log verbose output
/// Returns: the temp file the output is written to.
string prependFileToArchive(B)(ref B bytes, string prependFile, ZipArchiveMetadata meta, bool verbose = false)
{
    import std.range : lockstep;

    auto outfile = File(tempDir.chainPath("dzipper-" ~ uniform(0, uint.max).to!string).array, "wb");
    if (verbose)
    {
        writeln("Writing output to temp file: ", outfile.name);
    }

    {
        auto pf = File(prependFile);
        pf.copyFile(outfile);
    }

    if (meta.zipStart.isNull)
        return outfile.name.dup;

    auto archiveStart = cast(size_t) outfile.tell();

    // first, write all local file headers and the file contents
    foreach (ref lfh, cd; meta.localFileHeaders.lockstep(meta.centralDirectories))
    {
        if (verbose)
            writeln("Adding entry: ", lfh.fileName);
        outfile.rawWrite(lfh.toBytes);
        auto lfhEnd = cd.startOfLocalFileHeader + lfh.length;
        outfile.rawWrite(bytes[lfhEnd .. (lfhEnd + lfh.compressedSize)]);
    }

    const size_t shift = archiveStart - meta.zipStart.get;

    if (verbose)
        writeln("Shifting zip archive offsets by ", shift);

    // now, write all central directories
    foreach (cd; meta.centralDirectories)
    {
        cd.startOfLocalFileHeader += shift;
        outfile.rawWrite(cd.toBytes);
    }

    // write the end-of-central-directory
    auto eocd = meta.eocd;
    eocd.startOfCentralDirectory += shift;
    outfile.rawWrite(eocd.toBytes);

    return outfile.name.dup;
}

private void appends(T, R)(R range, immutable T value)
{
    append!(T, Endian.littleEndian, R)(range, value);
}

/// Create a byte array representing a Central Directory.
///
/// The bytes are returned as they would appear in a zip archive,
/// i.e. using little endian representation.
/// 
/// Params:
///   cd = the central directory
/// Returns: byte array in little endian
ubyte[] toBytes(in CentralDirectory cd)
{
    import std.datetime.systime : SysTimeToDosFileTime;

    auto bytes = new ubyte[cd.length];
    auto ap = appender(&bytes);
    ap.shrinkTo(0);
    ap.appends(CD_SIGNATURE_UINT);
    ap.appends(cd.versionMadeBy);
    ap.appends(cd.versionRequired);
    ap.appends(cd.generalPurposeBitFlag);
    ap.appends(cd.compressionMethod);
    const dosTime = SysTimeToDosFileTime(cd.lastModificationDateTime);
    // time is on the lo bytes
    ap.appends(cast(ushort)(dosTime & 0xFFFF));
    // date is on the hi bytes
    ap.appends(cast(ushort)((dosTime >> 16) & 0xFFFF));
    ap.appends(cd.crc32);
    ap.appends(cd.compressedSize);
    ap.appends(cd.uncompressedSize);
    ap.appends(cd.fileNameLength);
    ap.appends(cd.extraFieldLength);
    ap.appends(cd.commentLength);
    ap.appends(cd.diskNumber);
    ap.appends(cd.internalFileAttributes);
    ap.appends(cd.externalFileAttributes);
    ap.appends(cd.startOfLocalFileHeader);
    ap.put(cast(const(ubyte)[])(cd.fileName));
    ap.put(cd.extraField);
    ap.put(cd.comment);
    return bytes;
}

/// Create a byte array representing a Local File Header.
///
/// The bytes are returned as they would appear in a zip archive,
/// i.e. using little endian representation.
/// 
/// Params:
///   cd = the local file header
/// Returns: byte array in little endian
ubyte[] toBytes(in LocalFileHeader lfh)
{
    import std.datetime.systime : SysTimeToDosFileTime;

    auto bytes = new ubyte[lfh.length];
    auto ap = appender(&bytes);
    ap.shrinkTo(0);
    ap.appends(LOCAL_FILE_SIGNATURE_UINT);
    ap.appends(lfh.versionRequired);
    ap.appends(lfh.generalPurposeBitFlag);
    ap.appends(lfh.compressionMethod);
    const dosTime = SysTimeToDosFileTime(lfh.lastModificationDateTime);
    // time is on the lo bytes
    ap.appends(cast(ushort)(dosTime & 0xFFFF));
    // date is on the hi bytes
    ap.appends(cast(ushort)((dosTime >> 16) & 0xFFFF));
    ap.appends(lfh.crc32);
    ap.appends(lfh.compressedSize);
    ap.appends(lfh.uncompressedSize);
    ap.appends(lfh.fileNameLength);
    ap.appends(lfh.extraFieldLength);
    ap.put(cast(const(ubyte)[])(lfh.fileName));
    ap.put(lfh.extraField);
    return bytes;
}

/// Create a byte array representing a End of Central Directory structure.
///
/// The bytes are returned as they would appear in a zip archive,
/// i.e. using little endian representation.
/// 
/// Params:
///   cd = the end of central directory
/// Returns: byte array in little endian
ubyte[] toBytes(in EndOfCentralDirectory eocd)
{
    auto bytes = new ubyte[eocd.length];
    auto ap = appender(&bytes);
    ap.shrinkTo(0);
    ap.appends(EOCD_SIGNATURE_UINT);
    ap.appends(eocd.diskNumber);
    ap.appends(eocd.centralDirectoryDiskNumber);
    ap.appends(eocd.diskCentralDirectoriesCount);
    ap.appends(eocd.totalCentralDirectoriesCount);
    ap.appends(eocd.centralDirectorySize);
    ap.appends(eocd.startOfCentralDirectory);
    ap.appends(eocd.commentLength);
    ap.put(eocd.comment);
    return bytes;
}

private void copyFile(ref File from, ref File to)
{
    ubyte[4096] buf;
    ubyte[] data;
    do
    {
        data = from.rawRead(buf);
        to.rawWrite(data);
    }
    while (data.length > 0);
}

version (unittest)
{
    import tested;
    import dshould;
    import std.conv : hexString;
    import std.datetime.systime : DosFileTimeToSysTime, SysTime;

    @name("can copy file contents then add bytes to destination")
    unittest
    {
        scope (exit)
            "temp__".remove;
        scope (exit)
            "temp__2".remove;

        // write some file
        {
            auto temp = File("temp__", "wb");
            ubyte[3] b = [1, 2, 3];
            temp.rawWrite(b);
        }

        // copy to other file then add more stuff to it
        {
            auto from = File("temp__", "rb");
            auto to = File("temp__2", "wb");
            from.copyFile(to);
            ubyte[2] b = [4, 5];
            to.rawWrite(b);
        }

        auto res = File("temp__2");
        ubyte[6] buf;
        auto bytes = res.rawRead(buf);
        ubyte[5] b = [1, 2, 3, 4, 5];
        bytes.should.equal(b);
    }

    @name("EOCD can be serialized")
    unittest
    {
        ubyte[] eocdData = cast(ubyte[]) hexString!"504b0506 0100 0200 0300 0400 05000000 06000000 0000";
        EndOfCentralDirectory eocd = {
            diskNumber: 1,
            centralDirectoryDiskNumber: 2,
            diskCentralDirectoriesCount: 3,
            totalCentralDirectoriesCount: 4,
            centralDirectorySize: 5,
            startOfCentralDirectory: 6,
            commentLength: 0,
            comment: [],
        };
        eocd.toBytes().should.equal(eocdData);
    }

    private SysTime toSysTime(ushort date, ushort time) @safe
    {
        uint datetime = (date << 16) + time;
        return DosFileTimeToSysTime(datetime);
    }

    @name("CD can be serialized")
    unittest
    {
        ubyte[] cdData = cast(ubyte[]) hexString!"504b0102 0100 0200 0300 0400 2EA6
            2458 07000000 08000000 09000000 0200 0300 0000 0A00 0B00 0C000000 0D000000 4142 1A2B3C";
        auto dateTime = toSysTime(22_564, 42_542);
        CentralDirectory cd = {
            versionMadeBy: 1,
            versionRequired: 2,
            generalPurposeBitFlag: 3,
            compressionMethod: cast(CompressionMethod) 4,
            lastModificationDateTime: dateTime,
            crc32: 7,
            compressedSize: 8,
            uncompressedSize: 9,
            fileNameLength: 2,
            extraFieldLength: 3,
            commentLength: 0,
            diskNumber: 10,
            internalFileAttributes: 11,
            externalFileAttributes: 12,
            startOfLocalFileHeader: 13,
            fileName: "AB".dup,
            extraField: [0x1A, 0x2B, 0x3C],
            comment: [],
        };
        cd.toBytes().should.equal(cdData);
    }
}
