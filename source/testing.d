import std;
void main() {
        auto zip = new ZipArchive();
    auto member = new ArchiveMember();
    member.name = "hi.txt";
    member.expandedData("Hi".dup.representation);
    member.compressionMethod = CompressionMethod.none;
    zip.addMember(member);
    auto bytes = cast(const(ubyte[])) zip.build();
    auto f = File("my-test.zip", "wb");
    f.rawWrite(bytes);
}