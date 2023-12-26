# dzipper

A CLI utility to edit zip files as a locally mounted directory.

## Usage

```shell
dzipper [<options>] <zip-file> <mount-dir>
  -V --verbose 
  -h    --help This help information.
```

> Please ensure that the `<mount-dir>` is empty or does not exist before running this.

For example, to edit the file `hi.zip` in the local directory `hi-out`:

```shell
dzipper hi.zip hi-out
```

As you change `hi-out/`'s contents, those changes will be immediately reflected in the zip file.

## Implementation Notice

Currently, the whole zip archive is recreated on every edit.
However, if the zip contains non-archive data before the archive data starts,
then only the archive data gets replaced.

This allows dzipper to be used for editing mixed-purpose zip files like the
[redbean](https://redbean.dev/)
[αcτµαlly pδrταblε εxεcµταblε](https://justine.lol/ape.html) web server.
