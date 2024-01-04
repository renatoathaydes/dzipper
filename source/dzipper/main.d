module dzipper.main;

import std.stdio;
import std.mmfile;
import std.sumtype : match;

import consolecolors;

public import dzipper.options;
public import dzipper.parser;

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
        stderr.cwriteln("<yellow>Not a zip file (too short).</yellow>");
        return 1;
    }
    auto eocd_index = findEocd(bytes);
    if (eocd_index.isNull)
    {
        stderr.cwriteln("<yellow>Unable to locate zip metadata (EOCD).</yellow>");
        return 2;
    }
    if (verbose)
    {
        writeln("Found EOCD at offset ", eocd_index);
    }

    cwriteln("<green>File appears to be a zip file</green>");
    return 0;
}