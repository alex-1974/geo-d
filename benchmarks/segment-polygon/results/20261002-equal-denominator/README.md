# Equal-denominator exact comparison candidate — 2026-10-02

Source `4828889625ff2dd25b44dc545a5e9addb27310ef`, baseline
`7deb69f074208ddabe2b18316820965b16cf2966`. Status: correctness PASS,
performance acceptance OPEN; independent of the envelope PR #88.

For equal positive rational denominators, compare the signed integer numerators
directly. Denominators cancel exactly; no tolerance, conversion, allocation or
weaker geometry semantics are introduced. Distinct denominators retain the
original two exact 330-limb cross-products. All attributes and CTFE remain.
The shared helper serves clipping, intersections and polygon union; all ordinary
54-module suites pass on DMD 2.111.0 and LDC 1.41.0.

## Corrected independent validation

The public verifier uses assert. Earlier invocations with -release executed its
corpus but disabled the comparisons, so their claimed independent qualification
was incorrect. Six superseding runs omit -release and retain active assertions:
baseline, envelope candidate b47bac9 and this candidate, DMD and LDC, each
125,686 queries. All PASS. Same-flags assertion-side-effect probes additionally
confirm assertion execution. See assert-enabled-verification.json and six logs.
The archived verifier is unchanged, SHA256 ca012d85cc70e0fc56f914678a36971a25657a970a9a45a239df0bfa75f6ab3d.
This correction does not invalidate ordinary unit tests or release-active
benchmark preflights. Rejected dispatcher variants are not independently
qualified by their earlier release-disabled verifier runs.

The new BigInt comparator probe adds 2,048 deterministic full-width numerator/
denominator inputs and 4,096 directed comparisons per compiler, using independent
BigInt cross-products, fixed seed 0x82e19a73, equal/distinct denominators, signs
and zero. Runtime assertions are active. CTFE/runtime laws additionally cover
high limb positions, order reversal and equivalent rational representations.

## Mechanism profile

DMD -profile optimized release instrumentation on the shared preflighted double
corpus. Setup and two-direction semantic preflight remain in the trace; values
below are function call counts, not wall-time or C++ performance claims.

| 198x132-limb products | baseline profile | candidate profile |
|---|---:|---:|
| crossing, 1,000 calls | 13,026 | 5,010 |
| sparse-64, 1,000 calls | 13,026 | 5,010 |
| dense-64, 100 calls | 531,624 | 16,728 |

The initial profiler baseline is b47bac9 (envelope candidate), while the latency
baseline is develop 7deb69f. They must not be conflated. All profile inputs and
sinks match. The dense product count drops 96.9%. Instrumentation affects
inlining and runtime; self-time rankings identify investigation leads only.
Repeat with benchmarks/profile_segment_polygon.py, recording exact source and
compiler; raw traces, driver and provenance are retained under profiling/.

## Consumer release diagnostics

Eight clean AB/BA runs, 92 fixtures, three rounds/5 ms, CPU 0, safeonly bounds
checks, DMD 2.111.0 and LDC 1.41.0 LLVM 20.1.5. All 4,416 samples/368 clipping
pairs and preflight/source/hash/commit/round matrices pass audit. Exact commands,
environment and every clipping round/time/GC byte are retained. Power/turbo/
background controls are not attested. Short cloud measurements do not qualify
XPS latency or compiler-wide nonregression.

LDC double crossing is 4.8%/10.9% faster, dense-4 27.5%/12.8% faster,
dense-64 5.5%/17.3% faster. dense-16 shows an unusually large 80.6% improvement
in BA and should not be treated as a stable effect. DMD is mixed: double dense-4
is 21.4%/3.1% slower, sparse-64 11.0%/8.0% slower; dense-16 is 22.6%/18.3% faster.
These regressions are retained and acceptance stays open. GC allocation is not
reduced by arithmetic cancellation. No full GEOS parity is claimed.

The XPS script pins both immutable sources, both compilers, seven rounds/20 ms
and AB/BA order, and emits geo-equal-denominator-xps.tar.gz. Use it to qualify
this specific candidate; no merge or benchmark-freeze declaration follows from
these diagnostics. #82/#52/#57 remain open.
