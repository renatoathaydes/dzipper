module dzipper.process;

import std.stdio : File, writeln;

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
    import std.range : iota;

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

void prependFileToArchive(B)(ref B bytes, string prependFile, string zipFile, in EndOfCentralDirectory eocd, bool verbose)
{
    // auto prepFile = File(prependFile);
    writeln("not able to prepend file yet!");

}
