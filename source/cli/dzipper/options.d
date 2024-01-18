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
    string prependFile;
}

alias OptsResult = SumType!(Opts, int);

OptsResult parseOpts(in string[] args)
{
    OptsResult result;
    Opts opts;
    auto help = getopt(args,
        "verbose|V", &opts.verbose,
        "prepend|p", &opts.prependFile);
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
