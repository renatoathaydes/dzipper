import std.zip;
import fswatcher;
import std.stdio;
import p = std.path;
import std.file : read, write, getSize;
import std.stdio : File;
import std.string : startsWith;
import logging;

struct ZipWriter
{
    private ZipArchive zip;
    private const string zipFile;
    private const string outDir;
    private const ulong zipStartIndex;

    this(ZipArchive zipArchive, string zipFile, string outDir)
    {
        this.zip = zipArchive;
        this.zipFile = zipFile;
        this.outDir = outDir;
        this.zipStartIndex = computeZipStartIndex();
    }

    private ulong computeZipStartIndex()
    {
        const len = zip.data.length;
        const fileLen = zipFile.getSize;
        assert(fileLen >= len);
        return fileLen - len;
    }

    void onChange(FsChange change, FsKind kind, string path)
    {
        bool update;
        final switch (kind)
        {
        case FsKind.dir:
            update = changedDir(change, path);
            break;
        case FsKind.file:
            update = changedFile(change, path);
        }
        if (update)
        {
            updateZip();
        }
    }

    private void updateZip()
    {
        auto file = File(zipFile, "wb");
        file.seek(zipStartIndex);
        file.rawWrite(zip.build());
    }

    private bool changedDir(FsChange change, string path)
    {
        final switch (change)
        {
        case FsChange.added:
            addDir(path);
            return true;
        case FsChange.edited:
            return false;
        case FsChange.removed:
            removeDir(path);
            return true;
        }
    }

    private bool changedFile(FsChange change, string path)
    {
        final switch (change)
        {
        case FsChange.added:
            addFile(path);
            break;
        case FsChange.edited:
            updateFile(path);
            break;
        case FsChange.removed:
            removeFile(path);
        }
        return true;
    }

    private ArchiveMember createArchiveMember(string path, FsKind kind)
    {
        assert(path.startsWith(outDir));
        const zipPath = path[outDir.length + 1 .. $];
        auto member = new ArchiveMember();
        member.name = zipPath;
        if (kind == FsKind.dir)
        {
            member.name ~= "/";
        }
        return member;

    }

    private void addDir(string path)
    {
        auto member = createArchiveMember(path, FsKind.dir);
        zip.addMember(member);
    }

    private void removeDir(string path)
    {
        auto member = createArchiveMember(path, FsKind.dir);
        zip.deleteMember(member);
    }

    private void addFile(string path)
    {
        auto member = createArchiveMember(path, FsKind.file);
        member.expandedData(cast(ubyte[]) read(path));
        zip.addMember(member);

    }

    private void updateFile(string path)
    {
        auto member = createArchiveMember(path, FsKind.file);
        zip.deleteMember(member);
        member.expandedData(cast(ubyte[]) read(path));
        zip.addMember(member);
    }

    private void removeFile(string path)
    {
        auto member = createArchiveMember(path, FsKind.file);
        zip.deleteMember(member);
    }
}
