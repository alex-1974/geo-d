/** Independent BigInt cross-product oracle for the shared exact comparator. */
module exact_coordinate_compare_probe;

import geo.internal.exact_coordinate : SignedExactCoordinateNumerator,
    compareExactCoordinates;
import geo.internal.dyadic : DyadicProductMagnitude;
import geo.internal.fixed_uint : UIntFixed;
import std.bigint : BigInt;
import std.stdio : writeln;

private uint word(ref uint state) pure nothrow @safe @nogc
{
    state = cast(uint)(cast(ulong) state * 1664525 + 1013904223);
    return state;
}

private BigInt integer(size_t N)(ref const UIntFixed!N value)
{
    BigInt result;
    foreach_reverse (v; value.limb)
    {
        result <<= 32;
        result += v;
    }
    return result;
}

void main()
{
    uint state = 0x82e19a73;
    enum queries = 2048;
    foreach (i; 0 .. queries)
    {
        SignedExactCoordinateNumerator a, b;
        DyadicProductMagnitude da, db;
        a.sign = i % 3 == 0 ? -1 : 1;
        b.sign = i % 5 == 0 ? -1 : 1;
        foreach (ref v; a.magnitude.limb) v = word(state);
        foreach (ref v; b.magnitude.limb) v = word(state);
        foreach (ref v; da.limb) v = word(state);
        foreach (ref v; db.limb) v = word(state);
        if (i % 2 == 0) db = da;
        if (i % 11 == 0) a = SignedExactCoordinateNumerator.init;
        if (i % 17 == 0) b = a;
        BigInt lhs = integer(a.magnitude) * integer(db) * a.sign;
        BigInt rhs = integer(b.magnitude) * integer(da) * b.sign;
        const expected = lhs < rhs ? -1 : lhs > rhs ? 1 : 0;
        assert(compareExactCoordinates(a, da, b, db) == expected);
        assert(compareExactCoordinates(b, db, a, da) == -expected);
    }
    writeln("EXACT COORDINATE BIGINT COMPARE PASS: ", queries,
        " inputs, ", queries * 2, " directed comparisons; seed 0x82e19a73");
}
