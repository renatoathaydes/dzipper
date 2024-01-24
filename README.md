# dzipper

A D library and CLI utility for visualizing Zip archive metadata
and prepending other files to existing zip archives.

## Usage

```shell
dzipper [<options>] <zip-archive>
  -o <file>
  --output     Output file.
  -p <file>
  --prepend    Prepend a file to a zip archive.
  -V
  --verbose    Show verbose output. 
  -h
  --help       This help information.
```

If no output file or prepend file are provided, `dzipper` simply prints information about the archive.

With verbose output enabled, all of the zip archive metadata structures are printed out.

If an output file is provided, the zip archive is written to it without including any
unnecessary data that's not part of the zip data structure.

That means that `dzipper` can be used to _clean up_ an archive, as zip archives can contain many _unreachable_ entries, for example.

If the prepend file is given, then dzipper will prepend the contents of the file to the output file before writing out the archive.
If no output file was provided, then the archive itself is replaced.
