# ADR-0018: 1.x source compatibility and deprecation policy

**Status:** Accepted

**Date:** 2026-09-12

## Context

`geo-d` is preparing its first stable `v1.0.0` release.

The public API intended for that release has already been frozen and recorded
by the `api-freeze-v1.0.0` tag.

The supported package entry point is:

```d
import geo;
```

The frozen `v1.0.0` surface consists of the documented declarations reachable
through that package import together with the public members of the exported
types.

Before `v1.0.0`, geo-d needs an explicit policy for two related questions:

1. what source compatibility means during the `1.x` release series;
2. how public API can be deprecated and eventually removed.

D requires some care when defining compatibility.

Changes that may appear additive can still break existing source code.

Examples include:

- adding an enum member can break an exhaustive `final switch`;
- adding an overload can change overload resolution;
- changing template constraints can make previously valid instantiations
  fail or resolve differently;
- removing `@nogc`, `pure`, `nothrow`, or `@safe` can make calling code stop
  compiling;
- changing lifetime attributes can invalidate previously valid borrowing;
- changing `.init` semantics can alter valid default construction;
- changing an alias mapping such as `MetricScalar!T` can change public result
  types.

Consequently, geo-d needs a compatibility policy based on observable client
behaviour rather than only on symbol names.

## Decision

geo-d follows semantic versioning for the stable public API.

Within the `1.x` series, a previously valid use of the supported public API
should continue to compile and retain its documented observable contract.

The `v1.0.0` API freeze is the compatibility baseline for the `1.x` series.

Compatible public additions may be made in later `1.x` releases, but existing
public contracts may not be intentionally broken.

Intentional breaking changes require a new major version.

## Supported compatibility surface

The source-compatibility contract covers declarations supported through:

```d
import geo;
```

and the public members of the types exported through that package API.

This includes, where applicable:

- public symbol names;
- function and template signatures;
- overload resolution for previously valid calls;
- supported scalar domains;
- public result types and scalar mappings;
- enum members;
- public type invariants;
- `.init` semantics;
- documented preconditions;
- documented failure semantics;
- ownership and lifetime requirements;
- documented mutation behaviour;
- documented allocation guarantees;
- documented asymptotic complexity guarantees;
- documented numerical guarantees;
- documented non-finite-value behaviour;
- documented degenerate-geometry behaviour;
- public compile-time attributes whose removal could invalidate callers.

Examples of source-relevant attributes include:

```text
@safe
@nogc
pure
nothrow
scope
```

Removing or weakening such a guarantee in a way that makes previously valid
client source fail is a breaking change.

## Unsupported compatibility surface

The following are not part of the stable 1.x source-compatibility promise
unless separately documented:

- `geo.internal` declarations;
- package-private declarations;
- private declarations;
- undocumented implementation helpers;
- exact machine-code layout;
- object-file ABI;
- binary compatibility between separately compiled geo-d versions;
- raw struct byte representation;
- benchmark timing values;
- internal algorithm choice.

Consumers are expected to recompile against the geo-d version they use.

Direct imports of implementation modules under `geo.*` are not the supported
compatibility entry point merely because those modules are visible in the
source tree.

The stable package-level entry point is:

```d
import geo;
```

## Release categories

### Patch release

A `1.x.y` patch release may contain:

- bug fixes;
- documentation corrections;
- test improvements;
- performance improvements;
- internal refactoring;
- implementation changes that preserve the public contract.

A patch release must not intentionally require source changes from users of
the documented public API.

### Minor release

A `1.x.0` minor release may contain:

- backward-compatible new API;
- new supported functionality;
- new overloads proven not to alter existing overload resolution;
- widened support domains that preserve existing calls;
- public deprecations;
- compatible performance or implementation changes.

A minor release must preserve all previously supported public uses.

### Major release

A new major version is required for intentional breaking changes such as:

- removing a public declaration;
- renaming a public declaration;
- changing a public signature incompatibly;
- narrowing an existing supported scalar domain;
- changing an existing public result type;
- changing established `.init` semantics;
- weakening a documented numerical guarantee;
- weakening a documented allocation or complexity guarantee;
- changing failure semantics incompatibly;
- invalidating previously supported ownership or lifetime patterns;
- removing source-relevant function attributes;
- changing enum membership when that can invalidate exhaustive client code.

## Additive API changes

An API change is not considered compatible merely because it adds something.

Before adding a new public declaration or overload in a `1.x` release, geo-d
must consider whether existing source could change meaning or stop compiling.

### New top-level declarations

New top-level declarations may be added to `import geo;` in a minor release.

They must not intentionally replace or reinterpret an existing declaration.

Potential name conflicts created by broad unqualified imports should be
considered during API review.

### New overloads

A new overload may be added only when existing valid calls continue to resolve
to the same semantic operation.

If an overload addition creates ambiguity or changes selection for a
previously valid call, the addition is breaking and requires redesign or a
major release.

### Template constraints

Widening a template constraint is compatible when existing instantiations
retain their previous meaning.

Narrowing a constraint so that a previously supported instantiation no longer
compiles is breaking.

A constraint change that causes an existing expression to resolve to a
different overload must be treated as a compatibility change rather than as a
mere implementation detail.

### Enums

Adding an enum member is potentially source-breaking in D because client code
may use exhaustive `final switch`.

Therefore enum expansion is not assumed to be a compatible minor-version
change.

It requires explicit compatibility analysis and, by default, is deferred to a
major release when exhaustive source can be invalidated.

## Behavioural compatibility

Source compatibility is not limited to compilation.

Documented observable semantics remain part of the stable public contract.

For example, a `1.x` release must not silently change:

- `Bounds2.init` from empty to non-empty;
- endpoint-order semantics of `Segment2`;
- ring closure semantics;
- failure output state of a `try...` function;
- exact-topology guarantees;
- correctly-rounded construction guarantees;
- allocation-free guarantees;
- caller-owned workspace requirements;
- asymptotic complexity classes.

A new implementation may produce different floating-point values when the
existing documented contract already permits that variation.

It may not weaken a stronger documented guarantee.

## Bug fixes

Behaviour that contradicts the documented public contract is a bug.

A fix that restores the documented contract is permitted within `1.x`, even
when some client code happened to depend on the defect.

Such fixes should receive regression coverage.

When the previous documentation is ambiguous and both behaviours are
reasonable interpretations, geo-d should prefer the compatibility-preserving
choice or introduce a new API rather than silently redefining the existing
operation.

## Performance changes

Absolute performance is not a source-compatibility guarantee.

However, documented resource contracts are public behaviour.

A `1.x` release must therefore preserve established guarantees such as:

```text
No allocation is performed.
```

and documented asymptotic complexity unless a compatible replacement design
is introduced.

A performance optimisation must not weaken numerical or semantic guarantees.

## Deprecation policy

Public API may be deprecated during the `1.x` series but is not removed during
that series.

Removal of a public declaration deprecated in `1.x` requires the next major
version.

### Deprecation mechanism

Where practical, deprecated D declarations use the language-level
`deprecated` attribute with a migration message.

Public Ddoc must also identify:

- that the declaration is deprecated;
- the preferred replacement;
- any relevant semantic difference;
- the release in which deprecation began.

A deprecation must not exist only as an undocumented compiler diagnostic.

### Migration path

A deprecated API should normally have a supported replacement before
deprecation is introduced.

If a concept is being retired without a direct replacement, the documentation
must explain that explicitly.

Migration instructions should be sufficient for callers to update without
reading implementation code.

### Deprecation lifetime

A declaration deprecated in any `1.x` release remains available for the rest
of the `1.x` series.

For example:

```text
1.2    API deprecated
1.3    still available
1.9    still available
2.0    may be removed
```

Deprecation therefore warns about future major-version change rather than
acting as an early removal mechanism.

### Semantic replacement

geo-d will not silently repurpose an existing public name for substantially
different semantics.

When semantics need to change incompatibly:

1. introduce a new API when practical;
2. deprecate the old API;
3. retain the old contract through `1.x`;
4. remove or repurpose only in a later major release.

## Compatibility verification

The external consumer under:

```text
tests/consumer/
```

is part of the compatibility evidence.

The `v1.0.0` consumer checks form a persistent baseline.

During the `1.x` series, existing baseline checks must not be deleted merely
because the implementation evolves.

Compatible new public API may add additional checks.

If an intentional future major release removes or changes the baseline API,
the consumer may then be revised as part of that major-version transition.

The public API freeze document and its corresponding tag remain the historical
reference for the initial stable `1.x` surface.

## Compiler support

Supported compiler versions are a separate toolchain-support policy rather
than part of the public source-API shape.

Changes to the minimum supported compiler version must nevertheless be
explicitly documented and must not occur accidentally through an
implementation change.

Compiler support does not permit weakening the documented geo-d public
contract on a compiler that remains supported.

## Consequences

The `1.x` series provides a conservative source-compatibility promise.

Users can adopt later `1.x` releases without expecting intentional public API
breakage.

geo-d retains freedom to:

- refactor internals;
- replace algorithms;
- improve performance;
- improve numerical behaviour within the documented contract;
- add compatible new functionality.

The cost is that questionable additive changes must receive compatibility
analysis rather than being assumed safe.

Public removals and intentional incompatible semantic changes are reserved for
a future major release.
