## Verification correction — 2026-10-02

Earlier public BigInt verifier invocations used `-release`, which disabled its
runtime `assert` comparisons. Their independent PASS claims below are withdrawn.
Superseding runs without `-release` pass all 125,686 queries for develop 7deb69f
and the retained envelope source b47bac9 with each of DMD 2.111.0 and LDC 1.41.0.
Same-flags assertion-side-effect probes confirm active assertions. Rejected
98e0e7 and 4354545 variants remain independently unqualified by the old runs.
Unit tests and release-active benchmark preflights are unaffected. Raw timings
remain valid within their stated measurement limits. See the adjacent
`../assert-enabled-verification-20261002.json` for flags and provenance.

# Rejected delegated dispatch experiment — 2026-10-02

Source `98e0e706c5946740f1e5fae281aacf79e96f13eb`, baseline `7deb69f074208ddabe2b18316820965b16cf2966`.
Decision: REJECT as final candidate. Large trivial-case regressions require a
corrected dispatch; the next revision returns empty/degenerate results directly.

Both compilers pass 54 unit modules and the unchanged independent public BigInt
verifier (125,686 queries each). The exact kernel body equals baseline source
SHA256 `fa847b3b4c19e01d2b614820f64353fcb774b9aa4f48b0beb399e926ca18eee2`.

Eight clean-source AB/BA runs, DMD 2.111.0, LDC 1.41.0 LLVM 20.1.5, CPU 0,
safeonly release, seven rounds at calibrated 10 ms; all 10,304 samples/368 clipping
pairs and snapshots/commit trees pass audit. Per-round times/bytes and full
commands/environment remain in CSV/metadata. Cloud power/turbo/background
controls are not attested. Medians vary materially between order blocks.

A separate small dispatcher avoids changing the original exact kernel body.
LDC kernel sizes return to baseline: int 7,412, long 26,724, float 7,687,
double 24,302 bytes. `nm -S --size-sort` and `objdump -d --disassemble=SYMBOL`
inspect the recorded release benchmark executables. After normalizing addresses
and RIP-relative displacements, all instruction-text differences are immediate
arguments before bounds/OOM failure calls (path lengths/source line numbers).
The retained codegen summary states this limited comparison; it does not claim
whole-binary equality or runtime nonregression.

Although the exterior is fast and allocation-free, the extra dispatcher forwards
empty/degenerate inputs to the original large kernel. Repeated regressions are
substantial: LDC double degenerate-interior +79.1%/+76.1%; DMD long
 degenerate-interior +84.9%/+79.3%; DMD long empty +78.1%/+71.2%.
These are not accepted as noise. Nontrivial cases also contain residual concerns:
LDC long dense-1 +9.8%/+9.0%, long hole +10.9%/+9.8% and long concave-u
+9.6%/+8.5%. See all cases; do not select only favorable exterior/double results.

The next source revision forces inlining of the small dispatcher and handles
empty/degenerate success directly without entering exact workspace code. That
revision must pass its own correctness and measurements; this record does not
transfer acceptance. #82/#52/#57 remain open.
