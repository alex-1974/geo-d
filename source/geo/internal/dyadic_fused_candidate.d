module geo.internal.dyadic_fused_candidate;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicDifference;

import geo.internal.fixed_uint :
    addUnsigned;


/*
 * RESEARCH ONLY.
 *
 * Candidate source shape for the same-sign coordinate subtraction path.
 * It is intentionally not wired into subtractDyadicCoordinates().
 *
 * The scan determines the unsigned comparison and both active ranges in
 * one complete high-to-low pass. The selected subtraction then writes
 * directly into the caller-owned result carrier.
 */
private struct ScanResult
{
    int comparison;

    size_t lhsFirst;
    size_t lhsEnd;

    size_t rhsFirst;
    size_t rhsEnd;
}


private ScanResult scanComparisonAndRanges(
    ref const DyadicCoordinateMagnitude lhs,
    ref const DyadicCoordinateMagnitude rhs
)
    pure nothrow @safe @nogc
{
    ScanResult result;

    result.lhsFirst = lhs.limb.length;
    result.rhsFirst = rhs.limb.length;

    for (size_t i = lhs.limb.length; i != 0; --i)
    {
        const size_t index = i - 1;

        const uint lhsWord = lhs.limb[index];
        const uint rhsWord = rhs.limb[index];

        if (lhsWord != 0)
        {
            if (result.lhsEnd == 0)
                result.lhsEnd = i;

            result.lhsFirst = index;
        }

        if (rhsWord != 0)
        {
            if (result.rhsEnd == 0)
                result.rhsEnd = i;

            result.rhsFirst = index;
        }

        if (result.comparison == 0)
        {
            if (lhsWord < rhsWord)
                result.comparison = -1;
            else if (lhsWord > rhsWord)
                result.comparison = 1;
        }
    }

    return result;
}


private void subtractKnownRangeInto(
    ref DyadicCoordinateMagnitude output,
    ref const DyadicCoordinateMagnitude larger,
    ref const DyadicCoordinateMagnitude smaller,
    size_t smallerFirst,
    size_t smallerEnd
)
    pure nothrow @safe @nogc
{
    /*
     * The caller provides distinct output storage.
     *
     * Below the smaller operand's first non-zero limb no borrow can
     * exist, so copy directly from the larger operand.
     */
    foreach (index; 0 .. smallerFirst)
        output.limb[index] = larger.limb[index];

    ulong borrow = 0;

    foreach (index; smallerFirst .. smallerEnd)
    {
        const ulong lhsValue =
            cast(ulong) larger.limb[index];

        const ulong rhsValue =
            cast(ulong) smaller.limb[index] +
            borrow;

        if (lhsValue >= rhsValue)
        {
            output.limb[index] =
                cast(uint)(lhsValue - rhsValue);

            borrow = 0;
        }
        else
        {
            output.limb[index] =
                cast(uint)(
                    0x1_0000_0000UL +
                    lhsValue -
                    rhsValue
                );

            borrow = 1;
        }
    }

    size_t index = smallerEnd;

    while (borrow != 0)
    {
        assert(index < output.limb.length);

        const uint value = larger.limb[index];

        if (value != 0)
        {
            output.limb[index] = value - 1;
            borrow = 0;
            ++index;
            break;
        }

        output.limb[index] = uint.max;
        ++index;
    }

    foreach (tail; index .. output.limb.length)
        output.limb[tail] = larger.limb[tail];
}


/*
 * Research candidate for subtractDyadicCoordinates().
 *
 * The zero and opposite-sign paths intentionally preserve the existing
 * implementation shape. Only the same-sign path uses the fused scan.
 */
SignedDyadicDifference subtractDyadicCoordinatesFusedCandidate(
    ref const SignedDyadicCoordinate lhs,
    ref const SignedDyadicCoordinate rhs
)
    pure nothrow @safe @nogc
{
    SignedDyadicDifference result;

    if (lhs.sign == 0)
    {
        result.sign = -rhs.sign;
        result.magnitude = rhs.magnitude;
        return result;
    }

    if (rhs.sign == 0)
    {
        result.sign = lhs.sign;
        result.magnitude = lhs.magnitude;
        return result;
    }

    if (lhs.sign != rhs.sign)
    {
        result.sign = lhs.sign;
        result.magnitude =
            addUnsigned(lhs.magnitude, rhs.magnitude);
        return result;
    }

    const scan =
        scanComparisonAndRanges(
            lhs.magnitude,
            rhs.magnitude
        );

    if (scan.comparison == 0)
    {
        result.sign = 0;
        return result;
    }

    if (scan.comparison > 0)
    {
        result.sign = lhs.sign;

        subtractKnownRangeInto(
            result.magnitude,
            lhs.magnitude,
            rhs.magnitude,
            scan.rhsFirst,
            scan.rhsEnd
        );
    }
    else
    {
        result.sign = -lhs.sign;

        subtractKnownRangeInto(
            result.magnitude,
            rhs.magnitude,
            lhs.magnitude,
            scan.lhsFirst,
            scan.lhsEnd
        );
    }

    return result;
}
