import std.stdio: writeln, stderr;

void log(T...)(bool verbose, T message)
{
    if (verbose)
    {
        stderr.writeln(message);
    }
}
