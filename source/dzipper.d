import std.getopt;
import std.stdio;
import std.exception : enforce;
import std.mmfile;
import std.algorithm.searching;
import std.bitmanip : nativeToLittleEndian;
import std.range : retro, take, slide, iota;
import std.typecons : Nullable;
import std.sumtype : SumType, match;

import consolecolors;

immutable(ubyte[]) EOCD_SIGNATURE = nativeToLittleEndian!uint(0x06064b50)[0 .. $];

const USAGE = "
dzipper mounts a zip file on a local directory and then keeps track of changes
to files in that directory, reflecting that back in the zip archive.

Usage:
  dzipper [<options>] <zip-file> <mount-dir>";

struct Opts
{
    string zipFile;
    bool verbose;
}

alias OptsResult = SumType!(Opts, int);

version (unittest)
{
}
else
{

    int main(string[] args)
    {
        try
        {
            const opts = parseOpts(args);
            return opts.match!(
                (Opts o) => run(o),
                (int code) => code
            );
        }
        catch (Exception e)
        {
            version (assert)
            {
                stderr.writeln("Unexpected error: ", e);
            }
            else
            {
                stderr.writeln("Unexpected error: ", e.msg);
            }

            return 1;
        }
    }
}

private OptsResult parseOpts(string[] args)
{
    OptsResult result;
    Opts opts;
    auto help = getopt(args,
        "verbose|V", &opts.verbose);
    if (help.helpWanted)
    {
        cwriteln("<blue>####### dzipper #######</blue>");
        defaultGetoptPrinter(USAGE, help.options);
        result = 0;
    }
    else if (args.length != 3)
    {
        cwrite("<red>Error:</red> Please provide the required arguments: ");
        writeln("<zip-file> <out-dir>.");
        result = 3;
    }
    else
    {
        opts.zipFile = args[1];
        result = opts;
    }

    return result;
}

private int run(Opts opts)
{
    const
    verbose = opts.verbose,
    zipFile = opts.zipFile;

    auto file = new MmFile(zipFile);
    writefln("file length: %d", file.length);
    ubyte[] bytes = cast(ubyte[])(file[0 .. $]);
    if (bytes.length < 22)
    {
        stderr.writeln("not a zip file");
        return 1;
    }
    auto eocd_index = findEocd(bytes);
    if (eocd_index.isNull)
    {
        stderr.writeln("Unable to locate zip metadata");
        return 1;
    }
    writeln(eocd_index);
    return 0;
}

private Nullable!size_t findEocd(size_t windowLen = 56)(in ubyte[] bytes) pure
if (windowLen > 7)
{
    Nullable!size_t result;

    if (bytes.length < 4)
        return result;

    // the EOCD can only appear in the last 65536 + 22 bytes
    auto endBytes = bytes.retro.take(65_535 + 22).retro;

    // windows overlap by 3 bytes so we can find the 4-byte marker even
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
