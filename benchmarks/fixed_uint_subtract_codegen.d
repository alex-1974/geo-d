module geo.internal.fixed_uint_subtract_codegen;

import core.stdc.stdio : printf;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;

import geo.internal.fixed_uint :
    compareUnsigned,
    subtractUnsigned;

pragma(inline, false)
extern(C) int probe_compare_66(
    ref const DyadicCoordinateMagnitude lhs,
    ref const DyadicCoordinateMagnitude rhs
)
{
    return compareUnsigned(lhs, rhs);
}

pragma(inline, false)
extern(C) void probe_subtract_66(
    ref DyadicCoordinateMagnitude output,
    ref const DyadicCoordinateMagnitude lhs,
    ref const DyadicCoordinateMagnitude rhs
)
{
    output = subtractUnsigned(lhs, rhs);
}

pragma(inline, false)
extern(C) void probe_compare_then_subtract_66(
    ref DyadicCoordinateMagnitude output,
    ref const DyadicCoordinateMagnitude lhs,
    ref const DyadicCoordinateMagnitude rhs
)
{
    const int comparison = compareUnsigned(lhs, rhs);

    if (comparison > 0)
        output = subtractUnsigned(lhs, rhs);
    else if (comparison < 0)
        output = subtractUnsigned(rhs, lhs);
    else
        output = DyadicCoordinateMagnitude.init;
}

pragma(inline, false)
extern(C) void probe_same_sign_coordinate(
    ref SignedDyadicDifference output,
    ref const SignedDyadicCoordinate lhs,
    ref const SignedDyadicCoordinate rhs
)
{
    output = subtractDyadicCoordinates(lhs, rhs);
}

private ulong fingerprint(ref const DyadicCoordinateMagnitude value)
{
    ulong hash = 0xcbf29ce484222325UL;

    foreach (limb; value.limb)
        hash = (hash * 0x100000001b3UL) ^ limb;

    return hash;
}

void main()
{
    auto lhs = decodeDyadicCoordinate(11.0);
    auto rhs = decodeDyadicCoordinate(1.0);

    assert(lhs.sign == rhs.sign);
    assert(probe_compare_66(lhs.magnitude, rhs.magnitude) > 0);

    DyadicCoordinateMagnitude direct;
    probe_subtract_66(direct, lhs.magnitude, rhs.magnitude);

    DyadicCoordinateMagnitude combined;
    probe_compare_then_subtract_66(
        combined, lhs.magnitude, rhs.magnitude);

    SignedDyadicDifference coordinate;
    probe_same_sign_coordinate(coordinate, lhs, rhs);

    assert(direct.limb == combined.limb);
    assert(coordinate.sign == 1);
    assert(coordinate.magnitude.limb == direct.limb);

    printf("oracle: bit-identical\n");
    printf("checksum=%llu\n", cast(ulong) fingerprint(direct));
}
