module test;

import std.zip : ZipArchive, ArchiveMember, CM = CompressionMethod;
import std.string : representation;

import tested;

import dzipper;
import dshould;

import std.random;
import std.range : iota, array;
import std.algorithm.iteration : map;

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
    zip.build();

    auto bytes = zip.data();
    auto eocd_index = findEocd(bytes);
    eocd_index.should.equal(105);
}

@name("empty file is not a zip file")
unittest
{
    findEocd([]).isNull.should.equal(true);
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
