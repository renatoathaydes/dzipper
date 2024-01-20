module dzipper.main;

import std.stdio;
import std.mmfile;
import std.sumtype : match;

import consolecolors;

import dzipper.model;
import dzipper.options;
import dzipper.parser;
import dzipper.process;

int main(string[] args)
{
    try
    {
        const opts = parseOpts(args);
        return opts.match!(
            (in Opts o) => run(o),
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

private int run(in Opts opts)
{
    const
    verbose = opts.verbose,
    zipFile = opts.zipFile,
    prependFile = opts.prependFile;
    File tempFile;

    // start memory-mapped zip file scope
    {
        auto mfile = new MmFile(zipFile);
        writefln("file length: %d", mfile.length);
        if (mfile.length < 22)
        {
            stderr.cwriteln("<yellow>Not a zip file (too short).</yellow>");
            return 1;
        }
        auto eocd_index = findEocdIn(mfile);
        if (eocd_index.isNull)
        {
            stderr.cwriteln("<yellow>Unable to locate zip metadata (EOCD).</yellow>");
            return 2;
        }
        if (verbose)
        {
            writeln("Found EOCD at offset ", eocd_index, ".");
        }
        auto eocd = parseEocd(cast(ubyte[]) mfile[eocd_index.get .. $]);

        if (verbose)
        {
            writeln(eocd);
        }

        cwriteln("<green>File appears to be a zip file.</green>");

        if (eocd.totalCentralDirectoriesCount == 0)
        {
            cwriteln("<yellow>Warning: empty zip file.</yellow>");
        }

        if (prependFile.length == 0)
        {
            mfile.printArchiveMetadata(eocd, verbose);
        }
        else
        {
            tempFile = mfile.prependFileToArchive(prependFile, eocd, verbose);
        }
    }

    // the memory file has been closed now, so we can move the tempFile into the zip archive.
    if (tempFile.isOpen)
    {
        tempFile.name = zipFile;
    }

    return 0;
}
