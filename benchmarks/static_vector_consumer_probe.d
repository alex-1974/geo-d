/**
 * Research-only branch-vs-branch performance probe for the containers-d
 * StaticVector consumer experiment.
 *
 * The same source is compiled once against geo-d develop and once against the
 * research branch. Only the imported geo implementation differs.
 */
module static_vector_consumer_probe;

import geo.internal.expansion :
    ExpansionBuffer,
    fastExpansionSumZeroElim,
    scaleExpansionZeroElim;
import geo.internal.orientation_exact :
    tryOrientationExactExpansion;
import std.conv : to;
import std.stdio : stderr, writeln;

private struct OrientationCase
{
    double ax;
    double ay;
    double bx;
    double by;
    double cx;
    double cy;
}

private __gshared ExpansionBuffer!2[2] scaleInputs;
private __gshared double[2] scaleScalars;

private __gshared ExpansionBuffer!4[2] sumLeft;
private __gshared ExpansionBuffer!4[2] sumRight;

private __gshared OrientationCase[2] orientationCollinearCases;
private __gshared OrientationCase[2] orientationNearCases;

private void prepareCases()
{
    foreach (index; 0 .. 2)
        scaleInputs[index].clear();

    scaleInputs[0].append(0x1p-104);
    scaleInputs[0].append(1.0);
    scaleScalars[0] = 1.0 + 0x1p-27;

    scaleInputs[1].append(-0x1p-103);
    scaleInputs[1].append(2.0);
    scaleScalars[1] = -0.5 + 0x1p-28;

    foreach (index; 0 .. 2)
    {
        sumLeft[index].clear();
        sumRight[index].clear();
    }

    sumLeft[0].append(0x1p-156);
    sumLeft[0].append(-0x1p-104);
    sumLeft[0].append(0x1p-52);
    sumLeft[0].append(1.0);

    sumRight[0].append(-0x1p-155);
    sumRight[0].append(0x1p-103);
    sumRight[0].append(-0x1p-51);
    sumRight[0].append(2.0);

    sumLeft[1].append(-0x1p-158);
    sumLeft[1].append(0x1p-106);
    sumLeft[1].append(-0x1p-54);
    sumLeft[1].append(-1.5);

    sumRight[1].append(0x1p-157);
    sumRight[1].append(-0x1p-105);
    sumRight[1].append(0x1p-53);
    sumRight[1].append(-2.5);

    orientationCollinearCases[0] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 5.0
        );

    orientationCollinearCases[1] =
        OrientationCase(
            1.0, 1.0,
            11.0, 11.0,
            6.0, 6.0
        );

    orientationNearCases[0] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 0x1.4000000000001p+2
        );

    orientationNearCases[1] =
        OrientationCase(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 0x1.3ffffffffffffp+2
        );
}

pragma(inline, false)
extern(C) ulong bench_scale2(size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const index = i & 1;

        ExpansionBuffer!4 result;

        scaleExpansionZeroElim(
            scaleInputs[index],
            scaleScalars[index],
            result
        );

        checksum +=
            cast(ulong) result.length +
            7UL * cast(ulong)(
                result[result.length - 1] != 0.0
            );
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_sum4x4(size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const index = i & 1;

        ExpansionBuffer!8 result;

        fastExpansionSumZeroElim(
            sumLeft[index],
            sumRight[index],
            result
        );

        checksum +=
            cast(ulong) result.length +
            7UL * cast(ulong)(
                result[result.length - 1] != 0.0
            );
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_orientation_collinear(size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const value =
            orientationCollinearCases[i & 1];

        int sign;

        const success =
            tryOrientationExactExpansion(
                value.ax, value.ay,
                value.bx, value.by,
                value.cx, value.cy,
                sign
            );

        checksum +=
            cast(ulong) success +
            cast(ulong)(sign + 1) * 3UL;
    }

    return checksum;
}

pragma(inline, false)
extern(C) ulong bench_orientation_near(size_t rounds)
{
    ulong checksum;

    foreach (i; 0 .. rounds)
    {
        const value =
            orientationNearCases[i & 1];

        int sign;

        const success =
            tryOrientationExactExpansion(
                value.ax, value.ay,
                value.bx, value.by,
                value.cx, value.cy,
                sign
            );

        checksum +=
            cast(ulong) success +
            cast(ulong)(sign + 1) * 3UL;
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 3)
    {
        stderr.writeln(
            "usage: static-vector-consumer-probe <scale2|sum4x4|orientation-collinear|orientation-near> <rounds>");
        return;
    }

    prepareCases();

    const rounds = to!size_t(args[2]);
    ulong checksum;

    final switch (args[1])
    {
        case "scale2":
            checksum = bench_scale2(rounds);
            break;

        case "sum4x4":
            checksum = bench_sum4x4(rounds);
            break;

        case "orientation-collinear":
            checksum =
                bench_orientation_collinear(rounds);
            break;

        case "orientation-near":
            checksum =
                bench_orientation_near(rounds);
            break;
    }

    writeln(args[1], " ", checksum);
}
