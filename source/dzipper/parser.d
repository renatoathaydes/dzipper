module dzipper.parser;

import std.typecons : Nullable;
import std.algorithm.searching : find;
import std.exception : enforce, basicExceptionCtors;
import std.bitmanip : nativeToLittleEndian, littleEndianToNative, peek, Endian;
import std.range : retro, take, slide;

import model;
import std.string;

/** The End of Central Directory Signature. */
immutable(ubyte[]) EOCD_SIGNATURE = nativeToLittleEndian!uint(0x06054b50)[0 .. $];

/** The Central Directory Signature. */
immutable(ubyte[]) CD_SIGNATURE = nativeToLittleEndian!uint(0x02014b50)[0 .. $];

enum ZipParseError
{
    InvalidEocd,
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

private T peeks(T)(in ubyte[] bytes) =>
    peek!(T, Endian.littleEndian)(bytes);

EndOfCentralDirectory parseEocd(in ubyte[] bytes)
{
    // assert(bytes[0 .. 4] == EOCD_SIGNATURE);
    if (bytes.length < 22)
        throw new ZipParseException(ZipParseError.InvalidEocd, "too short to be EOCD");
    auto commentLen = peeks!ushort(bytes[20 .. 22]);
    if (bytes.length < 22 + commentLen)
        throw new ZipParseException(ZipParseError.InvalidEocd, "comment extends beyond buffer length");
    ubyte[] comment = [];
    if (commentLen)
    {
        comment = bytes[22 .. 22 + commentLen].dup;
    }
    EndOfCentralDirectory result = {
        diskNumber: peeks!ushort(bytes[4 .. 6]),
        centralDirectoryDiskNumber: peeks!ushort(bytes[6 .. 8]),
        diskCentralDirectoriesCount: peeks!ushort(bytes[8 .. 10]),
        totalCentralDirectoriesCount: peeks!ushort(bytes[10 .. 12]),
        centralDirectorySize: peeks!uint(bytes[12 .. 16]),
        startOfCentralDirectory: peeks!uint(bytes[16 .. 20]),
        commentLength: commentLen,
        comment: comment,
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
) pure @nogc if (windowLen > 7)
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

private bool checkCdSignature(in ubyte[] bytes, size_t idx) pure @nogc
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

version (unittest)
{
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.conv : to;
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
}
