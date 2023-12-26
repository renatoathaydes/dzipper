import std.file : getTimes, dirEntries, DirEntry, FileException, SpanMode;
import std.conv : to;
import std.typecons : Tuple, tuple, Nullable, nullable;
import core.time : seconds;
import std.algorithm;
import core.thread : Thread;
import std.datetime.systime;
import std.exception;
import std.array;

import logging;

enum FsChange
{
    added,
    removed,
    edited,
}

enum FsKind
{
    file,
    dir
}

private struct FsInfo
{
    FsKind kind;
    Nullable!FsChange change;
    ulong mod;
}

alias Handler = void delegate(FsChange change, FsKind kind, string path);

void startFswatcher(string[] dirs, bool verbose, Handler handler)
{
    DirWatcher[] watchers;
    foreach (dir; dirs)
    {
        watchers ~= new DirWatcher(dir, verbose, handler);
        watchers[$ - 1].run();
    }
    string[] newDirs;
    while (true)
    {
        foreach_reverse (i, w; watchers)
        {
            auto result = w.run();
            auto keepDir = result[0];
            newDirs ~= result[1];
            if (!keepDir)
            {
                watchers.remove(i);
            }
        }
        foreach (dir; newDirs)
            watchers ~= new DirWatcher(dir, verbose, handler);
        newDirs = newDirs[0 .. 0];
        Thread.sleep(2.seconds);
    }
}

private class DirWatcher
{
    const string dir;
    const bool verbose;
    const Handler handler;
    SysTime mod, acc;
    FsInfo[string] entries;
    ulong lastMod = 0;

    this(string dir, bool verbose, Handler handler)
    {
        this.dir = dir;
        this.verbose = verbose;
        this.handler = handler;
    }

    Tuple!(bool, string[]) run()
    {
        string[] newDirs;
        try
        {
            dir.getTimes(acc, mod);
        }
        catch (FileException fe)
        {
            log(verbose, "Stopped watching '", dir, "' due to ", fe);
            return tuple(false, newDirs);
        }
        if (lastMod != 0 && mod.stdTime == lastMod)
        {
            return tuple(true, newDirs);
        }
        // mark all entries as removed, if they're not found in the directory
        // entries, they will be correctly identified as being removed.
        entries.each!((ref e) => e.change = FsChange.removed);
        lastMod = mod.stdTime;
        foreach (DirEntry dirEntry; dir.dirEntries(SpanMode.shallow))
        {
            FsKind kind;
            if (dirEntry.isFile)
                kind = FsKind.file;
            else if (dirEntry.isDir)
                kind = FsKind.dir;
            else
                continue;
            if (auto info = dirEntry.name in entries)
            {
                if (kind == info.kind)
                {
                    dirEntry.getTimes(acc, mod);
                    if (info.mod == mod.stdTime)
                    {
                        info.change.nullify();
                    }
                    else
                    {
                        info.change = FsChange.edited;
                    }
                }
                else
                {
                    handler(FsChange.removed, kind, dirEntry.name);
                    info.change = FsChange.added;
                }
                if (!info.change.isNull)
                {
                    info.mod = mod.stdTime;
                    const change = info.change.get;
                    log(verbose, "Change ", change, ": ", dirEntry.name);
                    handler(change, kind, dirEntry.name);
                    if (change == FsChange.added && kind == FsKind.dir)
                    {
                        newDirs ~= dirEntry.name;
                    }
                }
            }
            else
            {
                dirEntry.getTimes(acc, mod);
                auto info = new FsInfo(kind, nullable(FsChange.added), mod.stdTime);
                entries[dirEntry.name] = *info;
                log(verbose, "Added new entry: ", dirEntry.name);
                handler(FsChange.added, kind, dirEntry.name);
                if (dirEntry.isDir)
                {
                    newDirs ~= dirEntry.name;
                }
            }
        }

        lastMod = mod.stdTime;
        string[] removedKeys;
        foreach (e; entries.byKeyValue.filter!(e => e.value.change == FsChange.removed))
        {
            log(verbose, "Removed entry: ", e.key);
            handler(FsChange.removed, e.value.kind, e.key);
            removedKeys ~= e.key;
        }
        removedKeys.each!(k => entries.remove(k));
        return tuple(true, newDirs);
    }
}
