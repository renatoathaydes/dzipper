module dzipper.process;

import std.stdio : File, writeln;

import dzipper.model, dzipper.parser;

void printArchiveMetadata(in ubyte[] bytes, in EndOfCentralDirectory eocd, bool verbose)
{
    auto suffix = eocd.totalCentralDirectoriesCount == 1 ? " entry." : " entries.";
    writeln("Archive contains ", eocd.totalCentralDirectoriesCount, suffix);
    bytes.checkCentralDirectories(eocd, verbose);
}

private void checkCentralDirectories(in ubyte[] bytes,
    in EndOfCentralDirectory eocd, bool verbose)
{
    import std.range : iota;

    uint offset = eocd.startOfCentralDirectory;
    foreach (i; iota(0, eocd.diskCentralDirectoriesCount))
    {
        auto cd = parseCd(bytes[offset .. $]);
        if (verbose)
        {
            writeln(cd);
        }
        offset += cd.length;
        auto lfh = parseLocalFileHeader(bytes[cd.startOfLocalFileHeader .. $]);
        if (verbose)
        {
            writeln(lfh);
        }
    }
}

void prependFileToArchive(in ubyte[] bytes, string prependFile, string zipFile, in EndOfCentralDirectory eocd, bool verbose)
{
    // auto prepFile = File(prependFile);
    writeln("not able to prepend file yet!");

}
