module test;

import std.zip;
import std.stdio : writefln;
import std.string : representation;

import tested;

import dzipper : findEocd;
import dshould;

@name("can inspect real zip file")
unittest
{
    auto zip = new ZipArchive();
    auto member = new ArchiveMember();
    member.name = "hello.txt";
    member.expandedData("Hello Zip".dup.representation);
    member.compressionMethod = CompressionMethod.deflate;
    zip.addMember(member);
    zip.build();

    auto bytes = zip.data();
    auto eocd_index = findEocd(bytes);
    eocd_index.should.equal(105);
}
