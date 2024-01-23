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
    findEocd(cast(ubyte[])[]).isNull.should.equal(true);
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
    auto cd = parseCd(bytes[eocd.startOfCentralDirectory .. $]);
    auto fh = parseLocalFileHeader(bytes[cd.startOfLocalFileHeader .. $]);

    auto toPrepend = "__toPrepend";
    enum prepended = "PREFIX";
    scope (exit)
        toPrepend.remove.collectException!FileException;
    toPrepend.write(prepended);

    auto res = prependFileToArchive(bytes, toPrepend, eocd);
    scope (exit)
        res.remove.collectException!FileException;

    auto resFile = File(res, "rb");
    resFile.size.should.equal(bytes.length + prepended.length);
    auto buf = new ubyte[resFile.size];
    auto resultContents = resFile.rawRead(buf);

    resultContents[0 .. prepended.length].should.equal(prepended);

    // parse the resulting bytes and ensure it's been shifted properly
    auto eocd_index2 = findEocd(resultContents);
    auto eocd2 = parseEocd(resultContents[eocd_index2.get .. $]);
    auto cd2 = parseCd(resultContents[eocd2.startOfCentralDirectory .. $]);
    auto fh2 = parseLocalFileHeader(resultContents[cd2.startOfLocalFileHeader .. $]);

    eocd_index2.should.equal(eocd_index.get + prepended.length);
    eocd2.startOfCentralDirectory.should.equal(eocd.startOfCentralDirectory + prepended.length);
    cd2.startOfLocalFileHeader.should.equal(cd.startOfLocalFileHeader + prepended.length);
    fh2.should.equal(fh);

    // the actual file contents should also be identical
    auto originalEntry = bytes[(cd.startOfLocalFileHeader + fh.length) .. $];
    auto newEntry = resultContents[(cd2.startOfLocalFileHeader + fh2.length) .. $];
    originalEntry[0 .. fh.compressedSize].should.equal(newEntry[0 .. fh2.compressedSize]);
    newEntry[0 .. fh.compressedSize].should.equal("Hi");
}
