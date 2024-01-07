module dzipper.main;

import std.stdio;
import std.mmfile;
import std.sumtype : match;

import consolecolors;

import dzipper.model;
import dzipper.options;
import dzipper.parser;

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
    auto bytes = cast(ubyte[])(file[0 .. $]);
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
        writeln("Found EOCD at offset ", eocd_index, ".");
    }
    auto eocd = parseEocd(bytes[eocd_index.get .. $]);

    if (verbose)
    {
        writeln(eocd);
    }

    cwriteln("<green>File appears to be a zip file.</green>");

    if (eocd.totalCentralDirectoriesCount == 0)
    {
        cwriteln("<yellow>Warning: empty zip file.</yellow>");
    }
    else
    {
        auto suffix = eocd.totalCentralDirectoriesCount == 1 ? " entry." : " entries.";
        writeln("Archive contains ", eocd.totalCentralDirectoriesCount, suffix);
        bytes.checkCentralDirectories(eocd, verbose);
    }

    return 0;
}

private void checkCentralDirectories(in ubyte[] bytes,
    in EndOfCentralDirectory eocd, bool verbose)
{
    import std.range : iota;
    uint offset = eocd.startOfCentralDirectory;
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(bytes[offset .. $]);
        if (verbose) {
            writeln(cd);
        }
        offset += cd.length();
    }
}
