module dzipper.options;

import std.stdio;
import std.getopt;
import std.sumtype : SumType, match;
import consolecolors;

const USAGE = "
DZipper is a utiliy for displaying zip file metadata.

Usage:
  dzipper [<options>] <zip-file>";

struct Opts
{
    string zipFile;
    bool verbose;
}

alias OptsResult = SumType!(Opts, int);

OptsResult parseOpts(string[] args)
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
    else if (args.length != 2)
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
