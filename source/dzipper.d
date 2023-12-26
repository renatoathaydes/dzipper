import std.getopt;
import std.file : read, write, mkdirRecurse;
import std.path : buildPath;
import std.zip;
import std.stdio : writeln, stderr;
import std.sumtype;
import consolecolors;

import fswatcher;
import zip_writer;
import logging;

const USAGE = "
dzipper mounts a zip file on a local directory and then keeps track of changes
to files in that directory, reflecting that back in the zip archive.

Usage:
  dzipper [<options>] <zip-file> <mount-dir>";

struct Opts
{
    string zipFile;
    string outDir;
    bool verbose;
}

alias OptsResult = SumType!(Opts, int);

int main(string[] args)
{
    try
    {
        const opts = parseOpts(args);
        return opts.match!(
                (Opts o) {
                run(o); return 0;
            },
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
        opts.zipFile = args[1], opts.outDir = args[2];
        result = opts;
    }

    return result;
}

private void run(Opts opts)
{
    const
    verbose = opts.verbose,
    zipFile = opts.zipFile,
    outDir = opts.outDir;

    log(verbose, "Reading zip file: ", zipFile);
    auto zip = new ZipArchive(read(zipFile));

    auto writer = ZipWriter(zip, zipFile, outDir);
    auto dirs = outDir.mountDir(zip, verbose);
    startFswatcher(dirs, verbose, &writer.onChange);
}

private string[] mountDir(string outDir, ZipArchive zip, bool verbose)
{
    string[] dirs;
    dirs ~= outDir;
    foreach (name, am; zip.directory)
    {
        if (name.isDir)
        {
            const p = buildPath(outDir, name);
            log(verbose, "Creating directory: ", p);
            mkdirRecurse(p);
            dirs ~= p;
        }
    }
    foreach (name, am; zip.directory)
    {
        if (!name.isDir)
        {
            const p = buildPath(outDir, name);
            log(verbose, "Creating file: ", p);
            const contents = zip.expand(am);
            write(p, contents);
        }
    }
    return dirs;
}

private bool isDir(string path) pure
{
    return path[$ - 1] == '/';
}
