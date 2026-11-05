# External consumer test

This directory is a separate DUB package that depends on the repository
checkout through a path dependency.

Its purpose is to verify the supported consumer surface from outside the
`geo-d` package using only:

```d
import geo;
```

The test checks that the historical 41 v1 names remain visible, that the v2
family additions remain available, and that representative v3 line,
relationship, clipping, and owning-result operations compile and run through
the package module.

This is a repository-local external-consumer test. It does **not** replace the
v1 release verification that installs `geo-d` from the public DUB registry in
a clean environment.
