module dzipper.options;

import std.stdio;
import std.getopt;
import std.sumtype : SumType, match;
import consolecolors;

const USAGE = "
DZipper is a utiliy for displaying zip file metadata.

Usage:
dzipper [<options>] <zip-archive>
  -o <file>
  --output     Output file.
  -p <file>
  --prepend    Prepend a file to a zip archive.
  -V
  --verbose    Show verbose output. 
  -h
  --help       This help information.
";

struct Opts
{
    string zipFile;
    bool verbose;
    string prependFile;
    string outputFile;
}

alias OptsResult = SumType!(Opts, int);

OptsResult parseOpts(string[] args)
{
    OptsResult result;
    Opts opts;
    auto help = getopt(args,
        "verbose|V", &opts.verbose,
        "prepend|p", &opts.prependFile,
        "output|o", &opts.outputFile);
    if (help.helpWanted)
    {
        cwriteln("<blue>####### dzipper #######</blue>");
        defaultGetoptPrinter(USAGE, help.options);
        result = 0;
    }
    else if (args.length != 2)
    {
        cwriteln("<red>Error:</red> Please specify a zip file to read.");
        result = 3;
    }
    else
    {
        opts.zipFile = args[1];
        result = opts;
    }

    return result;
}
