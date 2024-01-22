module test;

import std.zip : ZipArchive, ArchiveMember, CM = CompressionMethod;
import std.string : representation;
import std.random;
import std.range : iota, array;
import std.algorithm.iteration : map;
import std.file : remove, write, FileException;
import std.stdio : File;
import std.exception : collectException;

import tested;
import dshould;

import dzipper;

private ubyte[] randomBytes(size_t count)
{
    auto rand = Random(42);
    auto bytes = iota(0, ubyte.max).map!(b => cast(ubyte) b);
    return randomSample(bytes, 16, bytes.length, rand).array;
}

@name("can inspect real zip file")
unittest
{
    auto zip = new ZipArchive();
    auto member = new ArchiveMember();
    member.name = "hello.txt";
    member.expandedData("Hello Zip".dup.representation);
    member.compressionMethod = CM.deflate;
    zip.addMember(member);
    auto bytes = cast(const(ubyte[])) zip.build();

    auto eocd_index = findEocd(bytes);
    eocd_index.should.equal(105);

    auto eocd = parseEocd(bytes[eocd_index.get .. $]);
    eocd.centralDirectorySize.should.equal(55);
    eocd.totalCentralDirectoriesCount.should.equal(1);

    auto cd = parseCd(bytes[eocd.startOfCentralDirectory .. $]);

    cd.length.should.equal(55);
    cd.fileName.should.equal("hello.txt");
    cd.compressionMethod.should.equal(CompressionMethod.deflated);
    cd.versionMadeBy.should.equal(20); // D ZipArchive
}

@name("empty file is not a zip file")
unittest
{
    findEocd(cast(ubyte[]) []).isNull.should.equal(true);
}

@name("random bytes are not a zip file")
unittest
{
    findEocd(randomBytes(16)).isNull.should.equal(true);
    findEocd(randomBytes(256)).isNull.should.equal(true);
}

@name("random bytes are not a zip file even if containing EOCD bytes")
unittest
{
    auto bytes = randomBytes(256);
    bytes[0 .. 4] = EOCD_SIGNATURE;
    findEocd(bytes).isNull.should.equal(true);
}

@name("can prepend file to a zip archive")
unittest
{
    auto zip = new ZipArchive();
    auto member = new ArchiveMember();
    member.name = "hi.txt";
    member.expandedData("Hi".dup.representation);
    member.compressionMethod = CM.none;
    zip.addMember(member);
    auto bytes = cast(const(ubyte[])) zip.build();

    auto eocd_index = findEocd(bytes);
    eocd_index.should.equal(90);
    auto eocd = parseEocd(bytes[eocd_index.get .. $]);

    auto toPrepend = "__toPrepend";
    enum prepended = "PREFIX";
    scope (exit)
        toPrepend.remove;
    toPrepend.write(prepended);

    auto res = prependFileToArchive(bytes, toPrepend, eocd);
    scope (exit)
        res.name.remove.collectException!FileException;

    res.size.should.equal(bytes.length + prepended.length);
    auto buf = new ubyte[res.size];
    auto resultContents = res.rawRead(buf);

    resultContents[0 .. prepended.length].should.equal(prepended);
}
