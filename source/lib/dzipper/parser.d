module dzipper.parser;

import std.typecons : Nullable;
import std.algorithm.searching : find;
import std.exception : enforce, basicExceptionCtors;
import std.bitmanip : nativeToLittleEndian, littleEndianToNative, peek, Endian;
import std.range : retro, take, slide;
import std.conv : to;
import std.string : assumeUTF;
import std.datetime.systime : DosFileTimeToSysTime, SysTime;

import dzipper.model;
import std.string;

/** The End of Central Directory Signature. */
immutable(ubyte[]) EOCD_SIGNATURE = nativeToLittleEndian!uint(0x06054b50)[0 .. $];

/** The Central Directory Signature. */
immutable(ubyte[]) CD_SIGNATURE = nativeToLittleEndian!uint(0x02014b50)[0 .. $];

/** The Local File header Signature. */
immutable(ubyte[]) LOCAL_FILE_SIGNATURE = nativeToLittleEndian!uint(0x04034b50)[0 .. $];

/// Reason why a Zip Archive's metadata couldn't be parsed.
enum ZipParseError
{
    /// Invalid End of Central Directory.
    InvalidEocd,
    /// Invalid Central Directory.
    InvalidCd,
    /// Invalid Local File header.
    InvalidLocalFileHeader,
}

class ZipParseException : Exception
{
    ZipParseError error;
    string msg;

    this(ZipParseError error, string msg, string file = __FILE__, size_t line = __LINE__,
        Throwable next = null) @nogc @safe pure nothrow
    {
        super(msg, file, line, next);
        this.error = error;
    }
}

private T peeks(T, size_t lo, size_t hi)(in ubyte[] bytes) if (T.sizeof == hi - lo) =>
    peek!(T, Endian.littleEndian)(bytes[lo .. hi]);

private ubyte[] extractField(inout ubyte[] bytes, size_t offset, size_t length,
    lazy ZipParseException exception) @safe
{
    ubyte[] result = [];
    if (bytes.length < offset + length)
    {
        throw exception();
    }
    if (length > 0)
    {
        result = bytes[offset .. offset + length].dup;
    }
    return result;
}

/** 
 * Parse the End of Central Directory record.
 *
 * Params:
 *   bytes = slice starting at the End of Central Directory position.
 * Returns: the End of Central Directory record.
 * See_Also: findEocd
 */
EndOfCentralDirectory parseEocd(in ubyte[] bytes) @safe
{
    if (bytes.length < 22)
    {
        throw new ZipParseException(ZipParseError.InvalidEocd, "too short to be EOCD");
    }
    if (bytes[0 .. 4] != EOCD_SIGNATURE)
    {
        throw new ZipParseException(ZipParseError.InvalidEocd, "no EOCD signature");
    }

    auto commentLen = peeks!(ushort, 20, 22)(bytes);
    auto comment = extractField(bytes, 22, commentLen,
        new ZipParseException(
            ZipParseError.InvalidEocd, "comment extends beyond buffer length"));

    EndOfCentralDirectory result = {
        diskNumber: peeks!(ushort, 4, 6)(bytes),
        centralDirectoryDiskNumber: peeks!(ushort, 6, 8)(bytes),
        diskCentralDirectoriesCount: peeks!(ushort, 8, 10)(bytes),
        totalCentralDirectoriesCount: peeks!(ushort, 10, 12)(bytes),
        centralDirectorySize: peeks!(uint, 12, 16)(bytes),
        startOfCentralDirectory: peeks!(uint, 16, 20)(bytes),
        commentLength: commentLen,
        comment: comment,
    };
    return result;
}

/** 
 * Parse a Central Directory header.
 *
 * Each entry in a Zip Archive is fully described by a Central Directory header.
 * Params:
 *   bytes = slice starting at the Central Directory position.
 * Returns: the Central Directory header.
 * See_Also: findEocd
 */
CentralDirectory parseCd(in ubyte[] bytes) @safe
{
    enum struct_len = 46;

    if (bytes.length < struct_len)
    {
        throw new ZipParseException(ZipParseError.InvalidCd, "too short to be CD");
    }
    if (bytes[0 .. 4] != CD_SIGNATURE)
    {
        throw new ZipParseException(ZipParseError.InvalidCd, "no CD signature");
    }
    auto fileNameLength = peeks!(ushort, 28, 30)(bytes);
    auto fileName = extractField(bytes, struct_len, fileNameLength,
        new ZipParseException(ZipParseError.InvalidCd, "file name extends beyond buffer length"))
        .assumeUTF;

    auto extraFieldLength = peeks!(ushort, 30, 32)(bytes);
    auto extraField = extractField(bytes, struct_len + fileNameLength, extraFieldLength,
        new ZipParseException(ZipParseError.InvalidCd, "extra field extends beyond buffer length"));

    auto commentLength = peeks!(ushort, 32, 34)(bytes);
    auto comment = extractField(bytes, struct_len + fileNameLength + extraFieldLength, commentLength,
        new ZipParseException(ZipParseError.InvalidCd, "comment extends beyond buffer length"));

    auto dateTime = toSysTime(peeks!(ushort, 14, 16)(bytes), peeks!(ushort, 12, 14)(bytes));

    CentralDirectory result = {
        versionMadeBy: peeks!(ushort, 4, 6)(bytes),
        versionRequired: peeks!(ushort, 6, 8)(bytes),
        generalPurposeBitFlag: peeks!(ushort, 8, 10)(bytes),
        compressionMethod: cast(CompressionMethod) peeks!(ushort, 10, 12)(bytes),
        lastModificationDateTime: dateTime,
        crc32: peeks!(uint, 16, 20)(bytes),
        compressedSize: peeks!(uint, 20, 24)(bytes),
        uncompressedSize: peeks!(uint, 24, 28)(bytes),
        fileNameLength: fileNameLength,
        extraFieldLength: extraFieldLength,
        commentLength: commentLength,
        diskNumber: peeks!(ushort, 34, 36)(bytes),
        internalFileAttributes: peeks!(ushort, 36, 38)(bytes),
        externalFileAttributes: peeks!(uint, 38, 42)(bytes),
        startOfLocalFileHeader: peeks!(uint, 42, 46)(bytes),
        fileName: fileName,
        extraField: extraField,
        comment: comment,
    };
    return result;
}

/** 
 * Parse a Local File header.
 *
 * Params:
 *   bytes = slice starting at the Local File header position.
 * Returns: the Local File header.
 */
LocalFileHeader parseLocalFileHeader(in ubyte[] bytes) @safe
{
    enum struct_len = 30;

    if (bytes.length < struct_len)
    {
        throw new ZipParseException(ZipParseError.InvalidLocalFileHeader, "too short to be Local File header");
    }
    if (bytes[0 .. 4] != LOCAL_FILE_SIGNATURE)
    {
        throw new ZipParseException(ZipParseError.InvalidLocalFileHeader, "no Local File header signature");
    }

    auto dateTime = toSysTime(peeks!(ushort, 12, 14)(bytes), peeks!(ushort, 10, 12)(bytes));

    auto fileNameLength = peeks!(ushort, 26, 28)(bytes);
    auto fileName = extractField(bytes, struct_len, fileNameLength,
        new ZipParseException(ZipParseError.InvalidCd, "file name extends beyond buffer length"))
        .assumeUTF;

    auto extraFieldLength = peeks!(ushort, 28, 30)(bytes);
    auto extraField = extractField(bytes, struct_len + fileNameLength, extraFieldLength,
        new ZipParseException(ZipParseError.InvalidCd, "extra field extends beyond buffer length"));

    LocalFileHeader result = {
        versionRequired: peeks!(ushort, 4, 6)(bytes),
        generalPurposeBitFlag: peeks!(ushort, 6, 8)(bytes),
        compressionMethod: cast(CompressionMethod) peeks!(ushort, 8, 10)(bytes),
        lastModificationDateTime: dateTime,
        crc32: peeks!(uint, 14, 18)(bytes),
        compressedSize: peeks!(uint, 18, 22)(bytes),
        uncompressedSize: peeks!(uint, 22, 26)(bytes),
        fileNameLength: fileNameLength,
        extraFieldLength: extraFieldLength,
        fileName: fileName,
        extraField: extraField,
    };
    return result;
}

/** 
 * Find the End of Central Directory (EOCD).
 *
 * This method can be used to identify whether a file is a Zip Archive because if the
 * EOCD cannot be found, then the file is not a Zip file (unless corrupted).
 *
 * Params:
 *   bytes = the bytes to inspect
 *   checkCdSignature = whether to check the Central Directory's signature.
 * Returns: index of the End of Central Directory if it can be found, null otherwise.
 * Standards: PKWARE Zip File Format Specification Version 6.3.10
 * See_Also: https://pkware.cachefly.net/webdocs/APPNOTE/APPNOTE-6.3.10.TXT
 */
Nullable!size_t findEocd(size_t windowLen = 56)(
    in ubyte[] bytes, bool checkCdSignature = true
) pure @nogc @safe if (windowLen > 7)
{
    Nullable!size_t result;

    if (bytes.length < 4)
        return result;

    // the EOCD can only appear in the last 65536 + 22 bytes
    auto endBytes = bytes.retro.take(65_535 + 22).retro;

    // windows overlap by 4 bytes so we can find the 4-byte marker even
    // if it's split with one element on a chunk and the rest on another.
    auto step = windowLen - 4;
    auto windows = endBytes.slide(windowLen, step).retro;
    auto idx = bytes.length;
    auto i = 0;
    foreach (window; windows)
    {
        auto foundRange = window.find(EOCD_SIGNATURE);
        if (foundRange.length > 0)
        {
            idx -= foundRange.length;
            if (!checkCdSignature || bytes.checkCdSignature(idx + 16))
            {
                result = idx;
                return result;
            }
        }
        idx -= step;
        i++;
    }
    return result;
}

private bool checkCdSignature(in ubyte[] bytes, size_t idx) pure @nogc @safe
{
    if (idx + 4 >= bytes.length)
        return false;
    ubyte[4] startOfCd_bytes;
    startOfCd_bytes = bytes[idx .. idx + 4];
    auto startOfCd = littleEndianToNative!uint(startOfCd_bytes);
    if (startOfCd >= idx)
        return false;
    return bytes[startOfCd .. startOfCd + 4] == CD_SIGNATURE;
}

private SysTime toSysTime(ushort date, ushort time) @safe
{
    uint datetime = (date << 16) + time;
    return DosFileTimeToSysTime(datetime);
}

version (unittest)
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.range : iota;
    import std.conv : octal, hexString;
    import std.bitmanip : swapEndian;
    import std.algorithm.iteration : map;
    import tested;
    import dshould;

    ubyte[] newBytes(size_t len)
    {
        return iota(0, len).map!(i => (i % 0xff).to!ubyte).array();
    }

    @name("single window, EOCD near the beginning")
    unittest
    {
        auto bytes = newBytes(16);
        bytes[1 .. 5] = EOCD_SIGNATURE;
        auto result = bytes.findEocd(false);
        assert(!result.isNull);
        assert(result.get == 1, "result was " ~ result.to!string);

        bytes = newBytes(16);
        bytes[4 .. 8] = EOCD_SIGNATURE;
        result = bytes.findEocd(false);
        assert(!result.isNull);
        assert(result.get == 4, "result was " ~ result.to!string);
    }

    @name("array spanning multiple windows, EOCD near the beginning")
    unittest
    {
        enum windowLen = 8;
        auto bytes = newBytes(16);
        bytes[1 .. 5] = EOCD_SIGNATURE;
        auto result = bytes.findEocd!(windowLen)(false);
        assert(!result.isNull);
        assert(result.get == 1, "result was " ~ result.to!string);

        bytes[2 .. 6] = EOCD_SIGNATURE;
        result = bytes.findEocd!(windowLen)(false);
        assert(!result.isNull);
        assert(result.get == 2, "result was " ~ result.to!string);
    }

    @name("large array spanning multiple windows, EOCD near the end")
    unittest
    {
        auto bytes = newBytes(4096);
        bytes[4092 .. 4096] = EOCD_SIGNATURE;
        auto result = bytes.findEocd(false);
        assert(!result.isNull);
        assert(result.get == 4092, "result was " ~ result.to!string);

        bytes = newBytes(4096);
        bytes[4090 .. 4094] = EOCD_SIGNATURE;
        result = bytes.findEocd(false);
        assert(!result.isNull);
        assert(result.get == 4090, "result was " ~ result.to!string);
    }

    @name("large array spanning multiple windows, EOCD exactly at beginning of last window")
    unittest
    {
        enum windowLen = 8;
        auto bytes = newBytes(4096);
        bytes[4088 .. 4092] = EOCD_SIGNATURE;
        auto result = bytes.findEocd!(windowLen)(false);
        assert(!result.isNull);
        assert(result.get == 4088, "result was " ~ result.to!string);
    }

    @name("cannot parse empty EOCD")
    unittest
    {
        parseEocd([]).should.throwA!ZipParseException
            .where.error.should.equal(ZipParseError.InvalidEocd);
    }

    @name("cannot parse too short EOCD")
    unittest
    {
        parseEocd(EOCD_SIGNATURE).should.throwA!ZipParseException
            .where.error.should.equal(ZipParseError.InvalidEocd);
    }

    @name("can parse valid EOCD")
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
        parseEocd(eocdData).should.equal(eocd);
    }

    @name("can parse valid CD")
    unittest
    {
        ubyte[] cdData = cast(ubyte[]) hexString!"504b0102 0100 0200 0300 0400 2EA6
            2458 07000000 08000000 09000000 0200 0300 0000 0A00 0B00 0C000000 0D000000 4142 1A2B3C";
        cdData.length.should.equal(46 + 2 + 3);
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
        cd.length().should.equal(46 + 2 + 3);
        parseCd(cdData).should.equal(cd);
    }

    @name("can parse valid Local File header")
    unittest
    {
        ubyte[] lfhData = cast(ubyte[]) hexString!"504b0304 0200 0300 0400 2EA6
            2458 07000000 08000000 09000000 0200 0300 4344 1A2B3C";
        lfhData.length.should.equal(30 + 2 + 3);
        auto dateTime = toSysTime(22_564, 42_542);
        LocalFileHeader lfh = {
            versionRequired: 2,
            generalPurposeBitFlag: 3,
            compressionMethod: CompressionMethod.reduced_3, // 4,
            lastModificationDateTime: dateTime,
            crc32: 7,
            compressedSize: 8,
            uncompressedSize: 9,
            fileNameLength: 2,
            extraFieldLength: 3,
            fileName: "CD".dup,
            extraField: [0x1A, 0x2B, 0x3C],
        };
        lfh.length().should.equal(30 + 2 + 3);
        parseLocalFileHeader(lfhData).should.equal(lfh);
    }
}
