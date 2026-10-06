module geo.internal.dyadic_compact_research;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicProduct;


/*
 * RESEARCH-ONLY MODULE.
 *
 * Compact limb-window representation for exact dyadic orientation work.
 *
 * This is not production API. It exists only to qualify a possible fast path
 * for exact segment-intersection construction. The complete fixed-width dyadic
 * backend remains the fallback and semantic oracle.
 */

enum size_t compactCoordinateLimbs = 4;
enum size_t compactProductLimbs = 8;


private struct CompactDyadic(size_t Limbs)
{
    int sign;
    ushort offset;
    ubyte used;
    uint[Limbs] limb;
}


private alias CompactCoordinate =
    CompactDyadic!compactCoordinateLimbs;

private alias CompactDifference =
    CompactDyadic!compactCoordinateLimbs;

private alias CompactProduct =
    CompactDyadic!compactProductLimbs;


private void canonicalize(size_t Limbs)(
    ref CompactDyadic!Limbs value
)
    pure nothrow @safe @nogc
{
    size_t used = value.used;

    while (
        used > 0 &&
        value.limb[used - 1] == 0
    )
    {
        --used;
    }

    if (used == 0)
    {
        value =
            CompactDyadic!Limbs.init;

        return;
    }

    size_t first;

    while (
        first < used &&
        value.limb[first] == 0
    )
    {
        ++first;
    }

    if (first != 0)
    {
        foreach (i; 0 .. used - first)
        {
            value.limb[i] =
                value.limb[i + first];
        }

        foreach (i; used - first .. Limbs)
        {
            value.limb[i] = 0;
        }

        value.offset =
            cast(ushort)(
                cast(size_t) value.offset +
                first
            );

        used -= first;
    }

    value.used =
        cast(ubyte) used;
}


private bool compactCoordinate(
    ref const SignedDyadicCoordinate source,
    out CompactCoordinate result
)
    pure nothrow @safe @nogc
{
    result =
        CompactCoordinate.init;

    result.sign =
        source.sign;

    if (source.sign == 0)
        return true;

    size_t first;

    while (
        first <
            source.magnitude.limb.length &&
        source.magnitude.limb[first] == 0
    )
    {
        ++first;
    }

    size_t end =
        source.magnitude.limb.length;

    while (
        end > first &&
        source.magnitude.limb[end - 1] == 0
    )
    {
        --end;
    }

    const size_t used =
        end - first;

    if (
        used >
        compactCoordinateLimbs
    )
    {
        return false;
    }

    result.offset =
        cast(ushort) first;

    result.used =
        cast(ubyte) used;

    foreach (i; 0 .. used)
    {
        result.limb[i] =
            source.magnitude.limb[
                first + i
            ];
    }

    return true;
}


private uint limbAt(size_t Limbs)(
    ref const CompactDyadic!Limbs value,
    size_t absoluteIndex
)
    pure nothrow @safe @nogc
{
    if (value.sign == 0)
        return 0;

    if (
        absoluteIndex <
        value.offset
    )
    {
        return 0;
    }

    const size_t relative =
        absoluteIndex -
        cast(size_t) value.offset;

    if (relative >= value.used)
        return 0;

    return value.limb[relative];
}


private int compareMagnitude(size_t Limbs)(
    ref const CompactDyadic!Limbs lhs,
    ref const CompactDyadic!Limbs rhs
)
    pure nothrow @safe @nogc
{
    const size_t lhsEnd =
        cast(size_t) lhs.offset +
        lhs.used;

    const size_t rhsEnd =
        cast(size_t) rhs.offset +
        rhs.used;

    size_t end =
        lhsEnd > rhsEnd
            ? lhsEnd
            : rhsEnd;

    const size_t begin =
        lhs.offset < rhs.offset
            ? lhs.offset
            : rhs.offset;

    while (end > begin)
    {
        --end;

        const uint a =
            limbAt(lhs, end);

        const uint b =
            limbAt(rhs, end);

        if (a < b)
            return -1;

        if (a > b)
            return 1;
    }

    return 0;
}


private bool addMagnitude(size_t Limbs)(
    ref const CompactDyadic!Limbs lhs,
    ref const CompactDyadic!Limbs rhs,
    out CompactDyadic!Limbs result
)
    pure nothrow @safe @nogc
{
    result =
        CompactDyadic!Limbs.init;

    const size_t begin =
        lhs.offset < rhs.offset
            ? lhs.offset
            : rhs.offset;

    const size_t lhsEnd =
        cast(size_t) lhs.offset +
        lhs.used;

    const size_t rhsEnd =
        cast(size_t) rhs.offset +
        rhs.used;

    const size_t end =
        lhsEnd > rhsEnd
            ? lhsEnd
            : rhsEnd;

    const size_t span =
        end - begin;

    if (span > Limbs)
        return false;

    result.offset =
        cast(ushort) begin;

    result.used =
        cast(ubyte) span;

    ulong carry;

    foreach (i; 0 .. span)
    {
        const size_t absolute =
            begin + i;

        const ulong sum =
            cast(ulong)
                limbAt(lhs, absolute) +
            cast(ulong)
                limbAt(rhs, absolute) +
            carry;

        result.limb[i] =
            cast(uint) sum;

        carry =
            sum >> 32;
    }

    if (carry != 0)
    {
        if (span == Limbs)
            return false;

        result.limb[span] =
            cast(uint) carry;

        result.used =
            cast(ubyte)(span + 1);
    }

    canonicalize(result);

    return true;
}


private bool subtractMagnitude(
    size_t Limbs
)(
    ref const CompactDyadic!Limbs larger,
    ref const CompactDyadic!Limbs smaller,
    out CompactDyadic!Limbs result
)
    pure nothrow @safe @nogc
{
    result =
        CompactDyadic!Limbs.init;

    const size_t begin =
        larger.offset < smaller.offset
            ? larger.offset
            : smaller.offset;

    const size_t end =
        cast(size_t) larger.offset +
        larger.used;

    const size_t span =
        end - begin;

    if (span > Limbs)
        return false;

    result.offset =
        cast(ushort) begin;

    result.used =
        cast(ubyte) span;

    ulong borrow;

    foreach (i; 0 .. span)
    {
        const size_t absolute =
            begin + i;

        const ulong a =
            limbAt(
                larger,
                absolute
            );

        const ulong b =
            cast(ulong)
                limbAt(
                    smaller,
                    absolute
                ) +
            borrow;

        if (a >= b)
        {
            result.limb[i] =
                cast(uint)(a - b);

            borrow = 0;
        }
        else
        {
            result.limb[i] =
                cast(uint)(
                    0x1_0000_0000UL +
                    a -
                    b
                );

            borrow = 1;
        }
    }

    if (borrow != 0)
        return false;

    canonicalize(result);

    return true;
}


private bool subtractCompact(
    size_t Limbs
)(
    ref const CompactDyadic!Limbs lhs,
    ref const CompactDyadic!Limbs rhs,
    out CompactDyadic!Limbs result
)
    pure nothrow @safe @nogc
{
    result =
        CompactDyadic!Limbs.init;

    if (lhs.sign == 0)
    {
        result = rhs;
        result.sign = -rhs.sign;
        return true;
    }

    if (rhs.sign == 0)
    {
        result = lhs;
        return true;
    }

    if (lhs.sign != rhs.sign)
    {
        if (
            !addMagnitude(
                lhs,
                rhs,
                result
            )
        )
        {
            return false;
        }

        result.sign =
            lhs.sign;

        return true;
    }

    const int comparison =
        compareMagnitude(
            lhs,
            rhs
        );

    if (comparison == 0)
        return true;

    if (comparison > 0)
    {
        if (
            !subtractMagnitude(
                lhs,
                rhs,
                result
            )
        )
        {
            return false;
        }

        result.sign =
            lhs.sign;
    }
    else
    {
        if (
            !subtractMagnitude(
                rhs,
                lhs,
                result
            )
        )
        {
            return false;
        }

        result.sign =
            -lhs.sign;
    }

    return true;
}


private bool multiplyCompact(
    ref const CompactDifference lhs,
    ref const CompactDifference rhs,
    out CompactProduct result
)
    pure nothrow @safe @nogc
{
    result =
        CompactProduct.init;

    if (
        lhs.sign == 0 ||
        rhs.sign == 0
    )
    {
        return true;
    }

    const size_t used =
        cast(size_t) lhs.used +
        cast(size_t) rhs.used;

    if (
        used >
        compactProductLimbs
    )
    {
        return false;
    }

    result.sign =
        lhs.sign == rhs.sign
            ? 1
            : -1;

    result.offset =
        cast(ushort)(
            cast(size_t) lhs.offset +
            cast(size_t) rhs.offset
        );

    result.used =
        cast(ubyte) used;

    foreach (
        i;
        0 .. cast(size_t) lhs.used
    )
    {
        ulong carry;

        foreach (
            j;
            0 .. cast(size_t) rhs.used
        )
        {
            const size_t k =
                i + j;

            const ulong sum =
                cast(ulong)
                    result.limb[k] +
                cast(ulong)
                    lhs.limb[i] *
                    cast(ulong)
                        rhs.limb[j] +
                carry;

            result.limb[k] =
                cast(uint) sum;

            carry =
                sum >> 32;
        }

        size_t k =
            i +
            cast(size_t) rhs.used;

        while (carry != 0)
        {
            if (
                k >=
                compactProductLimbs
            )
            {
                return false;
            }

            const ulong sum =
                cast(ulong)
                    result.limb[k] +
                carry;

            result.limb[k] =
                cast(uint) sum;

            carry =
                sum >> 32;

            ++k;
        }
    }

    canonicalize(result);

    return true;
}


private bool compactDeterminant(
    ref const CompactCoordinate ax,
    ref const CompactCoordinate ay,
    ref const CompactCoordinate bx,
    ref const CompactCoordinate by,
    ref const CompactCoordinate cx,
    ref const CompactCoordinate cy,
    out CompactProduct result
)
    pure nothrow @safe @nogc
{
    CompactDifference bax;
    CompactDifference bay;
    CompactDifference cax;
    CompactDifference cay;

    if (
        !subtractCompact(
            bx,
            ax,
            bax
        ) ||
        !subtractCompact(
            by,
            ay,
            bay
        ) ||
        !subtractCompact(
            cx,
            ax,
            cax
        ) ||
        !subtractCompact(
            cy,
            ay,
            cay
        )
    )
    {
        return false;
    }

    CompactProduct left;
    CompactProduct right;

    if (
        !multiplyCompact(
            bax,
            cay,
            left
        ) ||
        !multiplyCompact(
            bay,
            cax,
            right
        )
    )
    {
        return false;
    }

    return
        subtractCompact(
            left,
            right,
            result
        );
}


private bool materialize(
    ref const CompactProduct compact,
    out SignedDyadicProduct result
)
    pure nothrow @safe @nogc
{
    result =
        SignedDyadicProduct.init;

    result.sign =
        compact.sign;

    if (compact.sign == 0)
        return true;

    const size_t end =
        cast(size_t) compact.offset +
        compact.used;

    if (
        end >
        result.magnitude.limb.length
    )
    {
        return false;
    }

    foreach (
        i;
        0 .. cast(size_t) compact.used
    )
    {
        result.magnitude.limb[
            cast(size_t) compact.offset +
            i
        ] =
            compact.limb[i];
    }

    return true;
}


/**
 * Research probe for one already-decoded exact orient2d determinant.
 *
 * Returns true only when the complete determinant fits the compact research
 * representation. On false, callers must use the existing fixed-width exact
 * backend. A true result is materialized bit-identically into the ordinary
 * SignedDyadicProduct carrier so downstream exact construction remains
 * unchanged.
 */
bool tryOrientationDeterminantCompactDecoded(
    ref const SignedDyadicCoordinate ax,
    ref const SignedDyadicCoordinate ay,
    ref const SignedDyadicCoordinate bx,
    ref const SignedDyadicCoordinate by,
    ref const SignedDyadicCoordinate cx,
    ref const SignedDyadicCoordinate cy,
    out SignedDyadicProduct result
)
    pure nothrow @safe @nogc
{
    CompactCoordinate cax;
    CompactCoordinate cay;
    CompactCoordinate cbx;
    CompactCoordinate cby;
    CompactCoordinate ccx;
    CompactCoordinate ccy;

    if (
        !compactCoordinate(ax, cax) ||
        !compactCoordinate(ay, cay) ||
        !compactCoordinate(bx, cbx) ||
        !compactCoordinate(by, cby) ||
        !compactCoordinate(cx, ccx) ||
        !compactCoordinate(cy, ccy)
    )
    {
        result =
            SignedDyadicProduct.init;

        return false;
    }

    CompactProduct compact;

    if (
        !compactDeterminant(
            cax,
            cay,
            cbx,
            cby,
            ccx,
            ccy,
            compact
        )
    )
    {
        result =
            SignedDyadicProduct.init;

        return false;
    }

    return
        materialize(
            compact,
            result
        );
}
