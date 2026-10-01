# Consumer archive gate

Run from a committed candidate (uncommitted files are intentionally ignored):

```sh
python3 tools/verify-consumer-archive.py
```

The gate generates a real `git archive`. The manifest is loaded from the
selected commit, independently of `.gitattributes`. Every tracked file under
`source/` and every explicitly approved consumer file must appear with its
original content and executable mode. All other files are rejected. Archive
links, duplicate paths and non-canonical paths also fail. New consumer resources
require an explicit manifest update; new source modules are included automatically.

Retained documentation covers installation, API conventions and compiler
support. Maintainer tooling, audits, ADRs, freeze records, editor planning,
benchmarking policy, tests, CI and research remain in the repository.
Internal implementation modules under `source/geo/internal/` are production
dependencies and must remain in the package.

To inspect a downloaded source archive for the same commit:

```sh
python3 tools/verify-consumer-archive.py --ref COMMIT \
    --archive /path/to/geo-d.tar.gz --prefix geo-d-COMMIT/
```

Use the archive's actual prefix. This does not qualify DUB registry publication
or imply that a downloaded GitHub archive was tested when only `git archive`
was tested locally. The CI consumer build separately exercises the extracted
archive with the existing external consumer fixture and released dependencies.
