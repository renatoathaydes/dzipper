module dzipper.main;

import std.stdio;
import std.mmfile;
import std.sumtype : match;
import std.range : empty;

import consolecolors;

import dzipper.model, dzipper.options, dzipper.parser, dzipper.process;

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
    catch (ZipParseException e)
    {
        stderr.cwriteln("<red>Error:</red> Problem parsing zip archive: ",
            e.error.toString, " - ", e.msg);
        return 7;
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
    outputFile = opts.outputFile,
    prependFile = opts.prependFile;
    string tempFile = "";

    // start memory-mapped zip file scope
    {
        auto mfile = new MmFile(zipFile);

        if (mfile.length < 22)
        {
            stderr.cwriteln("<yellow>Not a zip file (too short).</yellow>");
            return 1;
        }
        auto eocd_index = findEocd(cast(const(ubyte[])) mfile[]);
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
        auto meta = mfile.getArchiveMetadata(eocd);

        printSummary(eocd, meta, mfile.length, verbose);

        if (prependFile.empty)
        {
            if (outputFile.empty)
            {

            }
            else
            {
                // TODO 
                //mfile.writeArchive(eocd, verbose, outputFile);
            }
        }
        else
        {
            tempFile = mfile.prependFileToArchive(prependFile, eocd, verbose);
        }
    }

    // the memory file has been closed now, so we can move the tempFile into the zip archive.
    if (!tempFile.empty)
    {
        import std.file : remove, rename, FileException;
        import std.exception : collectException;

        scope (exit)
            tempFile.remove.collectException!FileException;

        tempFile.rename(outputFile.empty ? zipFile : outputFile);
    }

    return 0;
}

private void printSummary(in EndOfCentralDirectory eocd,
    in ZipArchiveMetadata meta,
    size_t fileLength,
    bool verbose)
{
    cwriteln("<green>File is a valid zip archive.</green>");
    cwritefln("File length: <blue>%,3d</blue>", fileLength);

    if (eocd.totalCentralDirectoriesCount == 0)
    {
        cwriteln("<yellow>Warning: empty zip file.</yellow>");
    }
    else
    {
        cwritefln("Number of entries: <blue>%d</blue>", eocd.totalCentralDirectoriesCount);
    }
    if (verbose)
    {
        cwriteln("<green>=== End of Central Directory:</green>");
        writeln(eocd);

        cwriteln("<green>=== Central Directory Entries:</green>");
        foreach (entry; meta.centralDirectories)
        {
            writeln(entry);
        }
        writeln("<green>=== Local file headers:</green>");
        foreach (lfh; meta.localFileHeaders)
        {
            writeln(lfh);
        }
    }

    if (!meta.zipStart.isNull)
        cwritefln("Start index: <blue>%d</blue>", meta.zipStart.get);

    cwritefln("Entries total compressed size: <blue>%,3.0f</blue>", meta.totalCompressed);
    cwritefln("Entries total uncompressed size: <blue>%,3.0f</blue>", meta.totalUncompressed);
    cwritefln("Compression rate: <blue>%.2f</blue>%%", (
            meta.totalCompressed / meta.totalUncompressed) * 100.0);
    writeln("Compression method count per entry:");

    foreach (cm, count; meta.compressionMethodCount)
    {
        cwritefln("  - %s: <blue>%d</blue>", cm, count);
    }
}
