module dzipper.parser;

import std.typecons : Nullable;
import std.algorithm.searching;
import std.stdio;
import std.exception : enforce;
import std.bitmanip : nativeToLittleEndian;
import std.range : retro, take, slide, iota;

immutable(ubyte[]) EOCD_SIGNATURE = nativeToLittleEndian!uint(0x06054b50)[0 .. $];

Nullable!size_t findEocd(size_t windowLen = 56)(in ubyte[] bytes) pure @nogc
        if (windowLen > 7)
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
            result = idx;
            return result;
        }
        idx -= step;
        i++;
    }
    return result;
}

version (unittest)
{

    import std.algorithm.iteration : map;
    import std.array : array;
    import std.conv : to;
    import tested;

    ubyte[] newBytes(size_t len)
    {
        return iota(0, len).map!(i => (i % 0xff).to!ubyte).array();
    }

    @name("single window, EOCD near the beginning")
    unittest
    {
        auto bytes = newBytes(16);
        bytes[1 .. 5] = EOCD_SIGNATURE;
        auto result = bytes.findEocd();
        assert(!result.isNull);
        assert(result.get == 1, "result was " ~ result.to!string);

        bytes = newBytes(16);
        bytes[4 .. 8] = EOCD_SIGNATURE;
        result = bytes.findEocd();
        assert(!result.isNull);
        assert(result.get == 4, "result was " ~ result.to!string);
    }

    @name("array spanning multiple windows, EOCD near the beginning")
    unittest
    {
        enum windowLen = 8;
        auto bytes = newBytes(16);
        bytes[1 .. 5] = EOCD_SIGNATURE;
        auto result = bytes.findEocd!(windowLen);
        assert(!result.isNull);
        assert(result.get == 1, "result was " ~ result.to!string);

        bytes[2 .. 6] = EOCD_SIGNATURE;
        result = bytes.findEocd!(windowLen);
        assert(!result.isNull);
        assert(result.get == 2, "result was " ~ result.to!string);
    }

    @name("large array spanning multiple windows, EOCD near the end")
    unittest
    {
        auto bytes = newBytes(4096);
        bytes[4092 .. 4096] = EOCD_SIGNATURE;
        auto result = bytes.findEocd();
        assert(!result.isNull);
        assert(result.get == 4092, "result was " ~ result.to!string);

        bytes = newBytes(4096);
        bytes[4090 .. 4094] = EOCD_SIGNATURE;
        result = bytes.findEocd();
        assert(!result.isNull);
        assert(result.get == 4090, "result was " ~ result.to!string);
    }

    @name("large array spanning multiple windows, EOCD exactly at beginning of last window")
    unittest
    {
        enum windowLen = 8;
        auto bytes = newBytes(4096);
        bytes[4088 .. 4092] = EOCD_SIGNATURE;
        auto result = bytes.findEocd!(windowLen);
        assert(!result.isNull);
        assert(result.get == 4088, "result was " ~ result.to!string);
    }

}
