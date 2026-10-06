module geo.internal.compact_clipping_census_research;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.dyadic_compact_research :
    tryOrientationDeterminantCompactDecoded;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/*
 * RESEARCH-ONLY MODULE.
 *
 * Counts compact determinant applicability specifically for the exact
 * proper-crossing construction work exercised by segment/polygon clipping.
 * Every compact hit is checked bit-for-bit against the existing fixed-width
 * determinant before it is counted as an oracle pass.
 */

struct CompactClippingCensus
{
    size_t properCrossings;
    size_t determinantAttempts;
    size_t compactHits;
    size_t oraclePasses;
    size_t fallbacks;

    @property double hitPercent() const
        pure nothrow @safe @nogc
    {
        return
            determinantAttempts == 0
                ? 100.0
                : 100.0 *
                    cast(double) compactHits /
                    cast(double) determinantAttempts;
    }
}


private SignedDyadicProduct fixedDeterminantDecoded(
    ref const SignedDyadicCoordinate ax,
    ref const SignedDyadicCoordinate ay,
    ref const SignedDyadicCoordinate bx,
    ref const SignedDyadicCoordinate by,
    ref const SignedDyadicCoordinate cx,
    ref const SignedDyadicCoordinate cy
)
    pure nothrow @safe @nogc
{
    const auto bax =
        subtractDyadicCoordinates(
            bx,
            ax
        );

    const auto bay =
        subtractDyadicCoordinates(
            by,
            ay
        );

    const auto cax =
        subtractDyadicCoordinates(
            cx,
            ax
        );

    const auto cay =
        subtractDyadicCoordinates(
            cy,
            ay
        );

    const auto left =
        multiplyDyadicDifferences(
            bax,
            cay
        );

    const auto right =
        multiplyDyadicDifferences(
            bay,
            cax
        );

    return
        subtractDyadicProducts(
            left,
            right
        );
}


private void recordDeterminant(
    ref CompactClippingCensus stats,
    ref const SignedDyadicCoordinate eAx,
    ref const SignedDyadicCoordinate eAy,
    ref const SignedDyadicCoordinate eBx,
    ref const SignedDyadicCoordinate eBy,
    ref const SignedDyadicCoordinate qX,
    ref const SignedDyadicCoordinate qY
)
    pure nothrow @safe @nogc
{
    SignedDyadicProduct compact;

    ++stats.determinantAttempts;

    if (
        !tryOrientationDeterminantCompactDecoded(
            eAx,
            eAy,
            eBx,
            eBy,
            qX,
            qY,
            compact
        )
    )
    {
        ++stats.fallbacks;
        return;
    }

    ++stats.compactHits;

    const auto fixed =
        fixedDeterminantDecoded(
            eAx,
            eAy,
            eBx,
            eBy,
            qX,
            qY
        );

    if (
        compact.sign == fixed.sign &&
        compact.magnitude.limb ==
            fixed.magnitude.limb
    )
    {
        ++stats.oraclePasses;
    }
}


/**
 * Research-only compact-dyadic applicability census for two query directions
 * against one polygon.
 *
 * The caller passes the forward and reverse forms of the same segment to match
 * the benchmark's ordinary clipping workload.
 */
CompactClippingCensus compactClippingCensus(T)(
    Segment2!T firstQuery,
    Segment2!T secondQuery,
    scope Polygon2View!T polygon
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    CompactClippingCensus stats;

    Segment2!T[2] queries = [
        firstQuery,
        secondQuery,
    ];

    foreach (query; queries)
    {
        const auto qAx =
            decodeDyadicCoordinate(
                query.a.x
            );

        const auto qAy =
            decodeDyadicCoordinate(
                query.a.y
            );

        const auto qBx =
            decodeDyadicCoordinate(
                query.b.x
            );

        const auto qBy =
            decodeDyadicCoordinate(
                query.b.y
            );

        foreach (ringIndex; 0 .. polygon.length)
        {
            const auto ring =
                polygon[ringIndex];

            foreach (
                edgeIndex;
                0 .. ring.segmentCount
            )
            {
                const auto edge =
                    ring.segment(
                        edgeIndex
                    );

                if (
                    segmentContactKind(
                        query,
                        edge
                    ) !=
                    SegmentContactKind.properCrossing
                )
                {
                    continue;
                }

                ++stats.properCrossings;

                const auto eAx =
                    decodeDyadicCoordinate(
                        edge.a.x
                    );

                const auto eAy =
                    decodeDyadicCoordinate(
                        edge.a.y
                    );

                const auto eBx =
                    decodeDyadicCoordinate(
                        edge.b.x
                    );

                const auto eBy =
                    decodeDyadicCoordinate(
                        edge.b.y
                    );

                recordDeterminant(
                    stats,
                    eAx,
                    eAy,
                    eBx,
                    eBy,
                    qAx,
                    qAy
                );

                recordDeterminant(
                    stats,
                    eAx,
                    eAy,
                    eBx,
                    eBy,
                    qBx,
                    qBy
                );
            }
        }
    }

    return stats;
}
