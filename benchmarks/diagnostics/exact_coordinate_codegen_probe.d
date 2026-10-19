/** Microbenchmark exact-coordinate comparator source shapes without changing production code. */
module exact_coordinate_codegen_probe;

import core.volatile : volatileLoad;
import geo.internal.dyadic : DyadicProductMagnitude;
import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator,
    compareExactCoordinates;
import geo.internal.fixed_uint : compareUnsigned, multiplyUnsigned;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

__gshared ulong sink;

pragma(inline, false)
private int baselineCross(
    ref const SignedExactCoordinateNumerator lhsNumerator,
    ref const DyadicProductMagnitude lhsDenominator,
    ref const SignedExactCoordinateNumerator rhsNumerator,
    ref const DyadicProductMagnitude rhsDenominator)
    pure nothrow @safe @nogc
{
    const int lhsSign = lhsNumerator.magnitude.isZero ? 0 : lhsNumerator.sign;
    const int rhsSign = rhsNumerator.magnitude.isZero ? 0 : rhsNumerator.sign;
    if (lhsSign < rhsSign) return -1;
    if (lhsSign > rhsSign) return 1;
    if (lhsSign == 0) return 0;
    const auto lhsScaled = multiplyUnsigned(lhsNumerator.magnitude, rhsDenominator);
    const auto rhsScaled = multiplyUnsigned(rhsNumerator.magnitude, lhsDenominator);
    const comparison = compareUnsigned(lhsScaled, rhsScaled);
    return lhsSign > 0 ? comparison : -comparison;
}

pragma(inline, false)
private int arrayEqualFast(
    ref const SignedExactCoordinateNumerator lhsNumerator,
    ref const DyadicProductMagnitude lhsDenominator,
    ref const SignedExactCoordinateNumerator rhsNumerator,
    ref const DyadicProductMagnitude rhsDenominator)
    pure nothrow @safe @nogc
{
    const int lhsSign = lhsNumerator.magnitude.isZero ? 0 : lhsNumerator.sign;
    const int rhsSign = rhsNumerator.magnitude.isZero ? 0 : rhsNumerator.sign;
    if (lhsSign < rhsSign) return -1;
    if (lhsSign > rhsSign) return 1;
    if (lhsSign == 0) return 0;
    if (lhsDenominator.limb == rhsDenominator.limb)
    {
        const comparison = compareUnsigned(lhsNumerator.magnitude, rhsNumerator.magnitude);
        return lhsSign > 0 ? comparison : -comparison;
    }
    const auto lhsScaled = multiplyUnsigned(lhsNumerator.magnitude, rhsDenominator);
    const auto rhsScaled = multiplyUnsigned(rhsNumerator.magnitude, lhsDenominator);
    const comparison = compareUnsigned(lhsScaled, rhsScaled);
    return lhsSign > 0 ? comparison : -comparison;
}

pragma(inline, false)
private int compareEqualFast(
    ref const SignedExactCoordinateNumerator lhsNumerator,
    ref const DyadicProductMagnitude lhsDenominator,
    ref const SignedExactCoordinateNumerator rhsNumerator,
    ref const DyadicProductMagnitude rhsDenominator)
    pure nothrow @safe @nogc
{
    const int lhsSign = lhsNumerator.magnitude.isZero ? 0 : lhsNumerator.sign;
    const int rhsSign = rhsNumerator.magnitude.isZero ? 0 : rhsNumerator.sign;
    if (lhsSign < rhsSign) return -1;
    if (lhsSign > rhsSign) return 1;
    if (lhsSign == 0) return 0;
    if (compareUnsigned(lhsDenominator, rhsDenominator) == 0)
    {
        const comparison = compareUnsigned(lhsNumerator.magnitude, rhsNumerator.magnitude);
        return lhsSign > 0 ? comparison : -comparison;
    }
    const auto lhsScaled = multiplyUnsigned(lhsNumerator.magnitude, rhsDenominator);
    const auto rhsScaled = multiplyUnsigned(rhsNumerator.magnitude, lhsDenominator);
    const comparison = compareUnsigned(lhsScaled, rhsScaled);
    return lhsSign > 0 ? comparison : -comparison;
}

private uint nextWord(ref uint state)
    pure nothrow @safe @nogc
{
    state = cast(uint)(cast(ulong) state * 1664525 + 1013904223);
    return state | 1;
}

private void fill(ref SignedExactCoordinateNumerator value, uint seed)
    pure nothrow @safe @nogc
{
    value.sign = 1;
    uint state = seed;
    // Exact dyadic construction values occupy sparse spans in the large
    // fixed-width carrier. Exercise low/middle/high positions without turning
    // this into an unrelated dense-BigInt multiplication benchmark.
    value.magnitude.limb[0] = nextWord(state);
    value.magnitude.limb[64] = nextWord(state);
    value.magnitude.limb[197] = nextWord(state);
}

private void fill(ref DyadicProductMagnitude value, uint seed)
    pure nothrow @safe @nogc
{
    uint state = seed;
    value.limb[0] = nextWord(state);
    value.limb[65] = nextWord(state);
    value.limb[131] = nextWord(state);
}

private void measure(alias comparator)(
    string name, string denominatorCase, size_t iterations,
    ref SignedExactCoordinateNumerator[2] lhs,
    ref SignedExactCoordinateNumerator[2] rhs,
    ref DyadicProductMagnitude[2] lhsDen,
    ref DyadicProductMagnitude[2] rhsDen)
{
    ulong local = 1;
    foreach (i; 0 .. iterations / 20 + 1)
    {
        const j = volatileLoad(&i) & 1;
        local = local * 1_000_003UL +
            cast(uint)(comparator(lhs[j], lhsDen[j], rhs[j], rhsDen[j]) + 1);
    }
    StopWatch watch;
    watch.start();
    foreach (i; 0 .. iterations)
    {
        const j = volatileLoad(&i) & 1;
        local = local * 1_000_003UL +
            cast(uint)(comparator(lhs[j], lhsDen[j], rhs[j], rhsDen[j]) + 1);
    }
    watch.stop();
    sink = sink * 1_000_033UL + local;
    writefln("sample,%s,%s,%s,%.3f,%s", name, denominatorCase, iterations,
        cast(double) watch.peek.total!"nsecs" / iterations, sink);
}

void main(string[] args)
{
    const iterations = args.length > 1 ? args[1].to!size_t : 20_000;
    SignedExactCoordinateNumerator[2] lhs, rhs;
    DyadicProductMagnitude[2] lhsDen, rhsDen;
    fill(lhs[0], 0x10203040); fill(lhs[1], 0x50607080);
    fill(rhs[0], 0x90a0b0c0); fill(rhs[1], 0xd0e0f001);
    fill(lhsDen[0], 0x13579bdf); fill(lhsDen[1], 0x2468ace0);

    foreach (denominatorCase; ["equal", "distinct"])
    {
        rhsDen = lhsDen;
        if (denominatorCase == "distinct")
        {
            rhsDen[0].limb[0] ^= 1;
            rhsDen[1].limb[64] ^= 1;
        }

        foreach (_; 0 .. 9)
        {
            measure!baselineCross("baseline-cross", denominatorCase, iterations,
                lhs, rhs, lhsDen, rhsDen);
            measure!arrayEqualFast("array-equal-fast", denominatorCase, iterations,
                lhs, rhs, lhsDen, rhsDen);
            measure!compareEqualFast("compare-equal-fast", denominatorCase, iterations,
                lhs, rhs, lhsDen, rhsDen);
            measure!compareExactCoordinates("production", denominatorCase, iterations,
                lhs, rhs, lhsDen, rhsDen);
        }
    }
}
