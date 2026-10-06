module normalized_dyadic_representation_bench;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicDifference,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import core.stdc.stdlib : abort;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

enum size_t compactCoordinateLimbs = 4;
enum size_t compactProductLimbs = 8;
enum size_t iterations = 200_000;

__gshared ulong sink;
__gshared size_t runtimeOffset;

private struct CompactDyadic(size_t Limbs)
{
    int sign;
    ushort offset;
    ubyte used;
    uint[Limbs] limb;
}

alias CompactCoordinate = CompactDyadic!compactCoordinateLimbs;
alias CompactDifference = CompactDyadic!compactCoordinateLimbs;
alias CompactProduct = CompactDyadic!compactProductLimbs;

private struct Inputs
{
    SignedDyadicCoordinate ax, ay, bx, by, cx, cy;
    CompactCoordinate cax, cay, cbx, cby, ccx, ccy;
    SignedDyadicDifference fixedDx, fixedDy;
    CompactDifference compactDx, compactDy;
    SignedDyadicProduct fixedProduct, fixedDeterminantValue;
    CompactProduct compactProduct, compactDeterminantValue;
}

private Inputs[8] ordinaryCases;

private ulong mix(ulong value, ulong part)
{
    return (value * 0x100000001b3UL) ^ part;
}

private void require(bool condition, string message)
{
    if (!condition)
    {
        writefln("ERROR,%s", message);
        abort();
    }
}

pragma(inline, false)
private size_t caseIndex(size_t i)
{
    return (i + runtimeOffset) & 7;
}

private ulong fingerprint(size_t Limbs)(
    ref const CompactDyadic!Limbs value
)
{
    ulong result = cast(ulong)(value.sign + 1);
    result = mix(result, value.offset);
    result = mix(result, value.used);

    foreach (i; 0 .. cast(size_t) value.used)
        result = mix(result, value.limb[i]);

    return result;
}

private ulong fingerprint(
    ref const SignedDyadicProduct value
)
{
    ulong result = cast(ulong)(value.sign + 1);

    foreach (limb; value.magnitude.limb)
        result = mix(result, limb);

    return result;
}

private void canonicalize(size_t Limbs)(
    ref CompactDyadic!Limbs value
)
{
    size_t used = value.used;

    while (used > 0 && value.limb[used - 1] == 0)
        --used;

    if (used == 0)
    {
        value = CompactDyadic!Limbs.init;
        return;
    }

    size_t first;

    while (first < used && value.limb[first] == 0)
        ++first;

    if (first > 0)
    {
        foreach (i; 0 .. used - first)
            value.limb[i] = value.limb[i + first];

        foreach (i; used - first .. Limbs)
            value.limb[i] = 0;

        value.offset = cast(ushort)(
            cast(size_t) value.offset + first
        );

        used -= first;
    }

    value.used = cast(ubyte) used;
}

private bool compactCoordinate(
    ref const SignedDyadicCoordinate source,
    out CompactCoordinate result
)
{
    result.sign = source.sign;

    if (source.sign == 0)
        return true;

    size_t first;

    while (
        first < source.magnitude.limb.length &&
        source.magnitude.limb[first] == 0
    )
        ++first;

    size_t end = source.magnitude.limb.length;

    while (
        end > first &&
        source.magnitude.limb[end - 1] == 0
    )
        --end;

    const size_t used = end - first;

    if (used > compactCoordinateLimbs)
        return false;

    result.offset = cast(ushort) first;
    result.used = cast(ubyte) used;

    foreach (i; 0 .. used)
        result.limb[i] = source.magnitude.limb[first + i];

    return true;
}

private uint limbAt(size_t Limbs)(
    ref const CompactDyadic!Limbs value,
    size_t absoluteIndex
)
{
    if (value.sign == 0)
        return 0;

    if (absoluteIndex < value.offset)
        return 0;

    const size_t relative =
        absoluteIndex - cast(size_t) value.offset;

    if (relative >= value.used)
        return 0;

    return value.limb[relative];
}

private int compareMagnitude(size_t Limbs)(
    ref const CompactDyadic!Limbs lhs,
    ref const CompactDyadic!Limbs rhs
)
{
    const size_t lhsEnd =
        cast(size_t) lhs.offset + lhs.used;

    const size_t rhsEnd =
        cast(size_t) rhs.offset + rhs.used;

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

        const uint a = limbAt(lhs, end);
        const uint b = limbAt(rhs, end);

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
{
    const size_t begin =
        lhs.offset < rhs.offset
            ? lhs.offset
            : rhs.offset;

    const size_t lhsEnd =
        cast(size_t) lhs.offset + lhs.used;

    const size_t rhsEnd =
        cast(size_t) rhs.offset + rhs.used;

    const size_t end =
        lhsEnd > rhsEnd
            ? lhsEnd
            : rhsEnd;

    const size_t span = end - begin;

    if (span > Limbs)
        return false;

    result.offset = cast(ushort) begin;
    result.used = cast(ubyte) span;

    ulong carry;

    foreach (i; 0 .. span)
    {
        const size_t absolute = begin + i;

        const ulong sum =
            cast(ulong) limbAt(lhs, absolute) +
            cast(ulong) limbAt(rhs, absolute) +
            carry;

        result.limb[i] = cast(uint) sum;
        carry = sum >> 32;
    }

    if (carry != 0)
    {
        if (span == Limbs)
            return false;

        result.limb[span] = cast(uint) carry;
        result.used = cast(ubyte)(span + 1);
    }

    canonicalize(result);
    return true;
}

private bool subtractMagnitude(size_t Limbs)(
    ref const CompactDyadic!Limbs larger,
    ref const CompactDyadic!Limbs smaller,
    out CompactDyadic!Limbs result
)
{
    const size_t begin =
        larger.offset < smaller.offset
            ? larger.offset
            : smaller.offset;

    const size_t end =
        cast(size_t) larger.offset + larger.used;

    const size_t span = end - begin;

    if (span > Limbs)
        return false;

    result.offset = cast(ushort) begin;
    result.used = cast(ubyte) span;

    ulong borrow;

    foreach (i; 0 .. span)
    {
        const size_t absolute = begin + i;

        const ulong a = limbAt(larger, absolute);
        const ulong b =
            cast(ulong) limbAt(smaller, absolute) +
            borrow;

        if (a >= b)
        {
            result.limb[i] = cast(uint)(a - b);
            borrow = 0;
        }
        else
        {
            result.limb[i] = cast(uint)(
                0x1_0000_0000UL + a - b
            );
            borrow = 1;
        }
    }

    assert(borrow == 0);

    canonicalize(result);
    return true;
}

private bool subtractCompact(size_t Limbs)(
    ref const CompactDyadic!Limbs lhs,
    ref const CompactDyadic!Limbs rhs,
    out CompactDyadic!Limbs result
)
{
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
        if (!addMagnitude(lhs, rhs, result))
            return false;

        result.sign = lhs.sign;
        return true;
    }

    const int comparison =
        compareMagnitude(lhs, rhs);

    if (comparison == 0)
        return true;

    if (comparison > 0)
    {
        if (!subtractMagnitude(lhs, rhs, result))
            return false;

        result.sign = lhs.sign;
    }
    else
    {
        if (!subtractMagnitude(rhs, lhs, result))
            return false;

        result.sign = -lhs.sign;
    }

    return true;
}

private bool multiplyCompact(
    ref const CompactDifference lhs,
    ref const CompactDifference rhs,
    out CompactProduct result
)
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return true;

    const size_t used =
        cast(size_t) lhs.used +
        cast(size_t) rhs.used;

    if (used > compactProductLimbs)
        return false;

    result.sign =
        lhs.sign == rhs.sign
            ? 1
            : -1;

    result.offset = cast(ushort)(
        cast(size_t) lhs.offset +
        cast(size_t) rhs.offset
    );

    result.used = cast(ubyte) used;

    foreach (i; 0 .. cast(size_t) lhs.used)
    {
        ulong carry;

        foreach (j; 0 .. cast(size_t) rhs.used)
        {
            const size_t k = i + j;

            const ulong sum =
                cast(ulong) result.limb[k] +
                cast(ulong) lhs.limb[i] *
                    cast(ulong) rhs.limb[j] +
                carry;

            result.limb[k] = cast(uint) sum;
            carry = sum >> 32;
        }

        size_t k =
            i + cast(size_t) rhs.used;

        while (carry != 0)
        {
            if (k >= compactProductLimbs)
                return false;

            const ulong sum =
                cast(ulong) result.limb[k] +
                carry;

            result.limb[k] = cast(uint) sum;
            carry = sum >> 32;
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
{
    CompactDifference bax, bay, cax, cay;

    if (!subtractCompact(bx, ax, bax))
        return false;

    if (!subtractCompact(by, ay, bay))
        return false;

    if (!subtractCompact(cx, ax, cax))
        return false;

    if (!subtractCompact(cy, ay, cay))
        return false;

    CompactProduct left, right;

    if (!multiplyCompact(bax, cay, left))
        return false;

    if (!multiplyCompact(bay, cax, right))
        return false;

    return subtractCompact(left, right, result);
}

private bool compactDifferenceMatches(
    ref const CompactDifference compact,
    ref const SignedDyadicDifference fixed
)
{
    if (compact.sign != fixed.sign)
        return false;

    foreach (i, limb; fixed.magnitude.limb)
    {
        if (limbAt(compact, i) != limb)
            return false;
    }

    return true;
}

private bool compactProductMatches(
    ref const CompactProduct compact,
    ref const SignedDyadicProduct fixed
)
{
    if (compact.sign != fixed.sign)
        return false;

    foreach (i, limb; fixed.magnitude.limb)
    {
        if (limbAt(compact, i) != limb)
            return false;
    }

    return true;
}

private void prepareCase(
    ref Inputs result,
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
)
{
    result.ax = decodeDyadicCoordinate(ax);
    result.ay = decodeDyadicCoordinate(ay);
    result.bx = decodeDyadicCoordinate(bx);
    result.by = decodeDyadicCoordinate(by);
    result.cx = decodeDyadicCoordinate(cx);
    result.cy = decodeDyadicCoordinate(cy);

    require(compactCoordinate(result.ax, result.cax), "compact ax");
    require(compactCoordinate(result.ay, result.cay), "compact ay");
    require(compactCoordinate(result.bx, result.cbx), "compact bx");
    require(compactCoordinate(result.by, result.cby), "compact by");
    require(compactCoordinate(result.cx, result.ccx), "compact cx");
    require(compactCoordinate(result.cy, result.ccy), "compact cy");

    result.fixedDx =
        subtractDyadicCoordinates(
            result.bx,
            result.ax
        );

    result.fixedDy =
        subtractDyadicCoordinates(
            result.cy,
            result.ay
        );

    require(
        subtractCompact(
            result.cbx,
            result.cax,
            result.compactDx
        ),
        "compact dx"
    );

    require(
        subtractCompact(
            result.ccy,
            result.cay,
            result.compactDy
        ),
        "compact dy"
    );

    require(
        compactDifferenceMatches(
            result.compactDx,
            result.fixedDx
        ),
        "dx oracle"
    );

    require(
        compactDifferenceMatches(
            result.compactDy,
            result.fixedDy
        ),
        "dy oracle"
    );

    result.fixedProduct =
        multiplyDyadicDifferences(
            result.fixedDx,
            result.fixedDy
        );

    require(
        multiplyCompact(
            result.compactDx,
            result.compactDy,
            result.compactProduct
        ),
        "compact product"
    );

    require(
        compactProductMatches(
            result.compactProduct,
            result.fixedProduct
        ),
        "product oracle"
    );

    result.fixedDeterminantValue =
        fixedDeterminantDecoded(
            result.ax, result.ay,
            result.bx, result.by,
            result.cx, result.cy
        );

    require(
        compactDeterminant(
            result.cax, result.cay,
            result.cbx, result.cby,
            result.ccx, result.ccy,
            result.compactDeterminantValue
        ),
        "compact determinant"
    );

    require(
        compactProductMatches(
            result.compactDeterminantValue,
            result.fixedDeterminantValue
        ),
        "determinant oracle"
    );
}

private void prepare()
{
    prepareCase(
        ordinaryCases[0],
        1_000_000.0, 1_000_000.0,
        1_000_100.0, 1_000_100.0,
        1_000_025.0, 1_000_090.0
    );

    prepareCase(
        ordinaryCases[1],
        4_000_000.25, 4_000_000.5,
        4_000_150.75, 4_000_120.25,
        4_000_010.5, 4_000_099.75
    );

    prepareCase(
        ordinaryCases[2],
        -2_000_000.0, -1_999_900.5,
        -1_999_800.25, -1_999_700.75,
        -1_999_950.5, -1_999_725.25
    );

    prepareCase(
        ordinaryCases[3],
        0.125, 0.25,
        64.5, 128.75,
        8.25, 96.125
    );

    prepareCase(
        ordinaryCases[4],
        2_097_152.0, 2_097_152.25,
        2_097_408.5, 2_097_600.75,
        2_097_200.125, 2_097_500.5
    );

    prepareCase(
        ordinaryCases[5],
        10_000_000.0, 9_999_999.5,
        10_000_256.25, 10_000_384.5,
        10_000_032.75, 10_000_300.125
    );

    prepareCase(
        ordinaryCases[6],
        -0.5, 0.75,
        1024.25, 2048.5,
        128.125, 1536.75
    );

    prepareCase(
        ordinaryCases[7],
        33_554_432.0, 33_554_432.125,
        33_554_800.5, 33_554_900.75,
        33_554_500.25, 33_554_850.5
    );
}


private SignedDyadicProduct fixedDeterminantDecoded(
    ref const SignedDyadicCoordinate ax,
    ref const SignedDyadicCoordinate ay,
    ref const SignedDyadicCoordinate bx,
    ref const SignedDyadicCoordinate by,
    ref const SignedDyadicCoordinate cx,
    ref const SignedDyadicCoordinate cy
)
{
    const auto bax = subtractDyadicCoordinates(bx, ax);
    const auto bay = subtractDyadicCoordinates(by, ay);
    const auto cax = subtractDyadicCoordinates(cx, ax);
    const auto cay = subtractDyadicCoordinates(cy, ay);

    const auto left = multiplyDyadicDifferences(bax, cay);
    const auto right = multiplyDyadicDifferences(bay, cax);

    return subtractDyadicProducts(left, right);
}

private void oracleOrdinary()
{
    foreach (ref const v; ordinaryCases)
    {
        CompactProduct compact;

        require(
            compactDeterminant(
                v.cax, v.cay,
                v.cbx, v.cby,
                v.ccx, v.ccy,
                compact
            ),
            "ordinary compact determinant"
        );

        const auto fixed =
            fixedDeterminantDecoded(
                v.ax, v.ay,
                v.bx, v.by,
                v.cx, v.cy
            );

        require(
            compactProductMatches(
                compact,
                fixed
            ),
            "ordinary determinant oracle"
        );
    }
}

private void broadCensus()
{
    static immutable double[] values = [
        -0x1.fffffffffffffp+1023,
        -0x1p+900,
        -0x1p+512,
        -0x1p+128,
        -0x1p+32,
        -1.0,
        -0x1p-32,
        -0x1p-512,
        -0x1p-1022,
        -0x0.0000000000001p-1022,
        0.0,
        0x0.0000000000001p-1022,
        0x1p-1022,
        0x1p-512,
        0x1p-32,
        1.0,
        0x1p+32,
        0x1p+128,
        0x1p+512,
        0x1p+900,
        0x1.fffffffffffffp+1023
    ];

    size_t coordinateCount;
    size_t coordinateCompact;
    size_t determinantCount;
    size_t determinantCompact;
    size_t determinantOraclePass;

    foreach (i; 0 .. values.length)
    {
        const auto decoded =
            decodeDyadicCoordinate(cast(double) values[i]);

        CompactCoordinate compact;

        ++coordinateCount;

        if (compactCoordinate(decoded, compact))
            ++coordinateCompact;
    }

    foreach (i; 0 .. 512)
    {
        const size_t n = values.length;

        const auto ax = decodeDyadicCoordinate(
            cast(double) values[(i * 3 + 1) % n]
        );

        const auto ay = decodeDyadicCoordinate(
            cast(double) values[(i * 5 + 2) % n]
        );

        const auto bx = decodeDyadicCoordinate(
            cast(double) values[(i * 7 + 3) % n]
        );

        const auto by = decodeDyadicCoordinate(
            cast(double) values[(i * 11 + 4) % n]
        );

        const auto cx = decodeDyadicCoordinate(
            cast(double) values[(i * 13 + 5) % n]
        );

        const auto cy = decodeDyadicCoordinate(
            cast(double) values[(i * 17 + 6) % n]
        );

        CompactCoordinate cax, cay, cbx, cby, ccx, ccy;

        require(compactCoordinate(ax, cax), "census compact ax");
        require(compactCoordinate(ay, cay), "census compact ay");
        require(compactCoordinate(bx, cbx), "census compact bx");
        require(compactCoordinate(by, cby), "census compact by");
        require(compactCoordinate(cx, ccx), "census compact cx");
        require(compactCoordinate(cy, ccy), "census compact cy");

        CompactProduct compact;

        ++determinantCount;

        if (compactDeterminant(
            cax, cay,
            cbx, cby,
            ccx, ccy,
            compact
        ))
        {
            ++determinantCompact;

            const auto fixed =
                fixedDeterminantDecoded(
                    ax, ay,
                    bx, by,
                    cx, cy
                );

            require(
                compactProductMatches(
                    compact,
                    fixed
                ),
                "census determinant oracle"
            );

            ++determinantOraclePass;
        }
    }

    writefln(
        "census,coordinates,%s,%s,%.2f",
        coordinateCount,
        coordinateCompact,
        100.0 * coordinateCompact /
            cast(double) coordinateCount
    );

    writefln(
        "census,determinants,%s,%s,%s,%.2f",
        determinantCount,
        determinantCompact,
        determinantOraclePass,
        100.0 * determinantCompact /
            cast(double) determinantCount
    );
}

pragma(inline, false)
private ulong fixedCopy(size_t i)
{
    const auto value =
        ordinaryCases[caseIndex(i)].ax;

    return
        cast(ulong)(value.sign + 1) ^
        value.magnitude.limb[0] ^
        value.magnitude.limb[33] ^
        value.magnitude.limb[$ - 1];
}

pragma(inline, false)
private ulong compactCopy(size_t i)
{
    const auto value =
        ordinaryCases[caseIndex(i)].cax;

    return fingerprint(value);
}

private ulong fixedDifferenceFingerprint(
    ref const SignedDyadicDifference value
)
{
    return
        cast(ulong)(value.sign + 1) ^
        value.magnitude.limb[0] ^
        value.magnitude.limb[33] ^
        value.magnitude.limb[$ - 1];
}

pragma(inline, false)
private ulong fixedSubtractControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fixedDifferenceFingerprint(v.fixedDx);
}

pragma(inline, false)
private ulong fixedSubtract(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    const auto value =
        subtractDyadicCoordinates(
            v.bx,
            v.ax
        );

    return fixedDifferenceFingerprint(value);
}

pragma(inline, false)
private ulong compactSubtractControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fingerprint(v.compactDx);
}

pragma(inline, false)
private ulong compactSubtract(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    CompactDifference value;

    if (!subtractCompact(
        v.cbx,
        v.cax,
        value
    ))
    {
        abort();
    }

    return fingerprint(value);
}

pragma(inline, false)
private ulong fixedMultiplyControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fingerprint(v.fixedProduct);
}

pragma(inline, false)
private ulong fixedMultiply(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    const auto value =
        multiplyDyadicDifferences(
            v.fixedDx,
            v.fixedDy
        );

    return fingerprint(value);
}

pragma(inline, false)
private ulong compactMultiplyControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fingerprint(v.compactProduct);
}

pragma(inline, false)
private ulong compactMultiply(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    CompactProduct value;

    if (!multiplyCompact(
        v.compactDx,
        v.compactDy,
        value
    ))
    {
        abort();
    }

    return fingerprint(value);
}

pragma(inline, false)
private ulong fixedDeterminantControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fingerprint(v.fixedDeterminantValue);
}

pragma(inline, false)
private ulong fixedDeterminant(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    const auto value =
        fixedDeterminantDecoded(
            v.ax, v.ay,
            v.bx, v.by,
            v.cx, v.cy
        );

    return fingerprint(value);
}

pragma(inline, false)
private ulong compactDeterminantControl(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];
    return fingerprint(v.compactDeterminantValue);
}

pragma(inline, false)
private ulong compactDeterminantBench(size_t i)
{
    ref const v = ordinaryCases[caseIndex(i)];

    CompactProduct value;

    if (!compactDeterminant(
        v.cax, v.cay,
        v.cbx, v.cby,
        v.ccx, v.ccy,
        value
    ))
    {
        abort();
    }

    return fingerprint(value);
}

private void bench(alias operation)(
    string name
)
{
    ulong local;

    foreach (i; 0 .. 2000)
        local = mix(local, operation(i));

    StopWatch watch;
    watch.start();

    foreach (i; 0 .. iterations)
        local = mix(local, operation(i));

    watch.stop();

    sink ^= local;

    writefln(
        "bench,%s,%.3f",
        name,
        cast(double) watch.peek.total!"nsecs" /
            cast(double) iterations
    );
}

private void benchPair(alias control, alias target)(
    string controlName,
    string targetName
)
{
    if ((runtimeOffset & 1) == 0)
    {
        bench!control(controlName);
        bench!target(targetName);
    }
    else
    {
        bench!target(targetName);
        bench!control(controlName);
    }
}

void main(string[] args)
{
    runtimeOffset =
        args.length > 1
            ? to!size_t(args[1])
            : args.length;

    prepare();
    oracleOrdinary();
    broadCensus();

    writefln("runtime,offset,%s", runtimeOffset);

    writefln(
        "sizeof,SignedDyadicCoordinate,%s",
        SignedDyadicCoordinate.sizeof
    );

    writefln(
        "sizeof,CompactCoordinate,%s",
        CompactCoordinate.sizeof
    );

    writefln(
        "sizeof,SignedDyadicProduct,%s",
        SignedDyadicProduct.sizeof
    );

    writefln(
        "sizeof,CompactProduct,%s",
        CompactProduct.sizeof
    );

    if ((runtimeOffset & 1) == 0)
    {
        bench!fixedCopy("fixed-copy");
        bench!compactCopy("compact-copy");
    }
    else
    {
        bench!compactCopy("compact-copy");
        bench!fixedCopy("fixed-copy");
    }

    benchPair!(fixedSubtractControl, fixedSubtract)(
        "fixed-subtract-control",
        "fixed-subtract"
    );

    benchPair!(compactSubtractControl, compactSubtract)(
        "compact-subtract-control",
        "compact-subtract"
    );

    benchPair!(fixedMultiplyControl, fixedMultiply)(
        "fixed-multiply-control",
        "fixed-multiply"
    );

    benchPair!(compactMultiplyControl, compactMultiply)(
        "compact-multiply-control",
        "compact-multiply"
    );

    benchPair!(fixedDeterminantControl, fixedDeterminant)(
        "fixed-determinant-control",
        "fixed-determinant"
    );

    benchPair!(compactDeterminantControl, compactDeterminantBench)(
        "compact-determinant-control",
        "compact-determinant"
    );

    writefln("oracle,ordinary,PASS");
    writefln("sink,%s", sink);
}
