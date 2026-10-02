# Rejected inline dispatch experiment — 2026-10-02

Source `4354545676603c2ebb47f53badce67987bd1d839`, baseline `7deb69f074208ddabe2b18316820965b16cf2966`.
Decision: REJECT as final candidate. Restore the smaller XPS-qualified source
`95d9d844e7012868b364dd41960fbcd22c6b6bdc`; its residual acceptance concerns stay open.

This revision forces the small dispatcher inline and handles empty/degenerate
successful results directly. The original exact kernel body remains unchanged.
Both compilers pass all 54 unit modules and the unchanged independent public
BigInt verifier, 125,686 queries each. The consumer archive has all 63 files.

Eight clean-source AB/BA diagnostic runs, DMD 2.111.0 and LDC 1.41.0 LLVM 20.1.5,
CPU 0, safeonly release, three rounds at calibrated 5 ms. The complete 4,416
sample matrix/368 clipping pairs, snapshots, exact commit trees, child statuses,
preflights and consumed sinks pass audit. Per-round times/GC bytes and metadata
remain in this directory. Power/turbo/background controls are not attested;
these short cloud diagnostics are not XPS performance acceptance evidence.

DMD double empty improves 46.9%/36.5%, degenerate-interior improves 40.3%/28.7%.
LDC double empty improves 35.8%/43.6%, degenerate-interior improves 44.5%/56.6%.
But LDC long empty is 46.8%/159.8% slower and degenerate-interior 60.9%/154.0%
slower. DMD double dense-64 is 11.3%/16.4% slower. LDC double crossing is
49.5%/79.0% slower; other cases exhibit very large block-to-block variation.
These observations cannot establish a better general variant. They are retained
as negative evidence, not dismissed because the exact kernel body is unchanged.

The LDC double kernel symbol remains 24,302 bytes, the same as baseline;
caller control flow, layout and runtime environment remain possible contributors.
No profiler attribution is claimed. The previous delegated experiment documents
a more detailed four-scalar codegen comparison; it is a different executed source.

The final branch restores the previously audited XPS implementation. No blanket
nonregression or complete GEOS-parity claim follows from any of these records.
Continue investigation of repeated exact event construction/comparison and
workspace costs for crossing/dense queries. #82/#52/#57 and PR #88 acceptance
remain open. Repeating XPS for these rejected dispatch variants is not requested.
