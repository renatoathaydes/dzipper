module dzipper.process;

import std.stdio : File, writeln;
import std.range : iota;
import std.file : remove;
import std.bitmanip : append, Endian;
import std.array : appender;
import std.typecons : Nullable;
import std.conv : to;
import std.algorithm.comparison : min;

import dzipper.model, dzipper.parser;

void printArchiveMetadata(B)(ref B bytes, in EndOfCentralDirectory eocd, bool verbose)
{
    auto suffix = eocd.totalCentralDirectoriesCount == 1 ? " entry." : " entries.";
    writeln("Archive contains ", eocd.totalCentralDirectoriesCount, suffix);
    bytes.checkCentralDirectories(eocd, verbose);
}

private void checkCentralDirectories(B)(ref B bytes,
    in EndOfCentralDirectory eocd, bool verbose)
{
    uint offset = eocd.startOfCentralDirectory;
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(cast(ubyte[]) bytes[offset .. $]);
        if (verbose)
        {
            writeln(cd);
        }
        offset += cd.length;
        auto lfh = parseLocalFileHeader(cast(ubyte[]) bytes[cd.startOfLocalFileHeader .. $]);
        if (verbose)
        {
            writeln(lfh);
        }
    }
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
///   eocd = end of central directory structure
///   verbose = whether to log verbose output
/// Returns: the temp file the output is written to.
File prependFileToArchive(B)(ref B bytes, string prependFile, in EndOfCentralDirectory eocd, bool verbose)
{
    auto outfile = File.tmpfile;
    File(prependFile).copyFile(outfile);
    long archiveStart = cast(long) outfile.tell();

    uint offset = eocd.startOfCentralDirectory;
    Nullable!long zipStart;

    // first, write all local file headers and the file contents
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(cast(ubyte[]) bytes[offset .. $]);
        auto lfh = parseLocalFileHeader(cast(ubyte[]) bytes[cd.startOfLocalFileHeader .. $]);
        zipStart = cast(long)(zipStart.isNull
                ? cd.startOfLocalFileHeader
                : min(cd.startOfLocalFileHeader, zipStart.get));

        if (verbose)
            writeln("Adding entry: ", lfh.fileName);
        auto lfhEnd = cd.startOfLocalFileHeader + lfh.length;
        outfile.rawWrite(bytes[cd.startOfLocalFileHeader .. lfhEnd]);
        outfile.rawWrite(bytes[lfhEnd .. lfhEnd + lfh.uncompressedSize]);
        offset += cd.length;
    }

    if (zipStart.isNull)
        return outfile;

    const long shift = archiveStart - zipStart.get;
    offset = eocd.startOfCentralDirectory;

    if (verbose)
        writeln("Shifting zip archive offsets by ", shift);

    // now, write all central directories
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(cast(ubyte[]) bytes[offset .. $]);
        cd.startOfLocalFileHeader = to!uint(cd.startOfLocalFileHeader + shift);
        outfile.rawWrite(cd.toBytes);
        offset += cd.length;
    }

    // write the end-of-central-directory
    auto shiftEocd = eocd;
    shiftEocd.startOfCentralDirectory = to!uint(eocd.startOfCentralDirectory + shift);
    outfile.rawWrite(shiftEocd.toBytes);

    return outfile;
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
    import std.datetime : SysTimeToDosFileTime;

    auto bytes = new ubyte[cd.length];
    auto ap = appender(&bytes);
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

private void copyFile(scope ref File from, scope ref File to)
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

    @name("can copy file contents")
    unittest
    {
        scope (exit)
            "temp__".remove;
        scope (exit)
            "temp__2".remove;

        // write some file
        {
            auto temp = File("temp__", "wb");

            temp.rawWrite([1, 2, 3]);
        }

        // copy to other file then add more stuff to it
        {
            auto from = File("temp__", "rb");
            auto to = File("temp__2", "wb");
            from.copyFile(to);
            to.rawWrite([4, 5]);
        }

        auto res = File("temp__2");
        ubyte[6] buf;
        auto bytes = res.rawRead(buf);
        bytes.should.equal([1, 2, 3, 4, 5]);
    }
}
