# External consumer test

This directory is a separate DUB package that depends on the repository
checkout through a path dependency.

Its purpose is to verify the supported consumer surface from outside the
`geo-d` package using only:

```d
import geo;
```

The test checks that all 41 names recorded by the v1 public API freeze are
visible through the package module and compiles representative operations from
the major API families.

This is a repository-local external-consumer test. It does **not** replace the
v1 release verification that installs `geo-d` from the public DUB registry in
a clean environment.
