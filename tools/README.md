# Maintainer tools

Python generators, independent Unicode-data verifiers, and benchmark utilities
live here. Generated Zig files remain checked in under `src/`, and pinned
Unicode inputs remain under `src/data/`. Library builds require only Zig.

Run the maintainer checks from the repository root:

```sh
make verify-tables test-tools
```

These checks require Python 3 and Zig on `PATH`. Scripts locate their inputs
relative to their own file paths rather than the current working directory.
For line-break generation details, see [line-break-machine.md](line-break-machine.md).

The Zig bidi dump program remains in `src/tools/`; comparison-specific tooling
remains with its benchmark project.
