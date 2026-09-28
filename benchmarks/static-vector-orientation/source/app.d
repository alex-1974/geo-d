module app;

import geo.internal.orientation_robust :
    tryOrientationRobustDoubleFallback;

import std.conv : to;
import std.stdio : stderr, writeln;

enum size_t caseCount = 256;

private struct Case
{
    double ax;
    double ay;
    double bx;
    double by;
    double cx;
    double cy;
}

private void fillCases(ref Case[caseCount] cases)
    pure nothrow @safe @nogc
{
    foreach (i, ref item; cases)
    {
        const double t =
            cast(double)(i & 31);

        double delta;

        final switch (i % 3)
        {
            case 0:
                delta = 0.0;
                break;

            case 1:
                delta = 0x1p-45;
                break;

            case 2:
                delta = -0x1p-45;
                break;
        }

        item =
            Case(
                t, t,
                t + 10.0, t + 10.0,
                t + 5.0, t + 5.0 + delta
            );
    }
}

pragma(inline, false)
extern(C) ulong bench_fallback(
    scope const Case[] cases,
    size_t rounds)
    @safe @nogc nothrow
{
    ulong checksum =
        0xCBF2_9CE4_8422_2325UL;

    foreach (round; 0 .. rounds)
    {
        foreach (i, item; cases)
        {
            int sign;

            const success =
                tryOrientationRobustDoubleFallback(
                    item.ax, item.ay,
                    item.bx, item.by,
                    item.cx, item.cy,
                    sign
                );

            assert(success);

            checksum ^=
                cast(ulong)(sign + 2) +
                (cast(ulong) i + 1) *
                    0x9E37_79B9_7F4A_7C15UL +
                (cast(ulong) round + 1) *
                    0xD6E8_FEB8_6659_FD93UL;

            checksum *=
                0x0000_0100_0000_01B3UL;
        }
    }

    return checksum;
}

void main(string[] args)
{
    if (args.length != 2)
    {
        stderr.writeln(
            "usage: geo-static-vector-orientation-probe <rounds>");
        return;
    }

    const rounds =
        to!size_t(args[1]);

    Case[caseCount] cases;
    fillCases(cases);

    const checksum =
        bench_fallback(
            cases[],
            rounds
        );

    writeln(checksum);
}
