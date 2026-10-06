module geo.internal.intersection_exact;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeDyadicCoordinate;

import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator,
    compareExactCoordinates,
    exactCoordinateNumeratorLimbs,
    exactCoordinatesEqual;

import geo.internal.dyadic_compact :
    CompactDyadicProduct,
    tryCompactWeightDenominator,
    tryCompactWeightedCoordinate,
    tryOrientationDeterminantCompactDecodedRaw;

import geo.internal.fixed_uint :
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;

import geo.internal.orientation_dyadic :
    orientationDeterminantDyadic,
    orientationDeterminantDyadicDecoded;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact construction data for a proper segment crossing.
 *
 * No floating-point construction arithmetic is performed here.
 *
 * For a proper crossing of AB and CD, let:
 *
 *     dA = orient(C, D, A)
 *     dB = orient(C, D, B)
 *
 * Their signs are opposite. The intersection point on AB is:
 *
 *     P =
 *         (|dB| A + |dA| B)
 *         -----------------
 *             |dB| + |dA|
 *
 * The orientation determinants are exact fixed-width integers in a
 * common dyadic scale. That scale cancels in the ratio.
 */


private enum bool isExactIntersectionScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


version (LDC)
private enum bool useCompactPreparedConstruction = true;
else
private enum bool useCompactPreparedConstruction = false;


/*
 * Package-internal exact representation of one already-decoded segment.
 *
 * This is execution state, not public geometry. It exists so callers with a
 * repeated source segment can hoist scalar-to-dyadic decoding out of an edge
 * loop without changing the exact arithmetic or result representation.
 */
package(geo)
struct PreparedExactSegment
{
    SignedDyadicCoordinate aX;
    SignedDyadicCoordinate aY;
    SignedDyadicCoordinate bX;
    SignedDyadicCoordinate bY;
}


package(geo)
PreparedExactSegment prepareExactSegment(T)(
    Segment2!T segment
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    PreparedExactSegment result;

    result.aX =
        decodeDyadicCoordinate(
            segment.a.x
        );

    result.aY =
        decodeDyadicCoordinate(
            segment.a.y
        );

    result.bX =
        decodeDyadicCoordinate(
            segment.b.x
        );

    result.bY =
        decodeDyadicCoordinate(
            segment.b.y
        );

    return result;
}


/**
 * Exact rational construction data for one proper segment crossing.
 *
 * Both coordinates share the same positive denominator.
 */
struct ExactProperIntersection
{
    SignedExactCoordinateNumerator xNumerator;
    SignedExactCoordinateNumerator yNumerator;

    DyadicProductMagnitude denominator;
}


/*
 * Exact equality of two proper-intersection events.
 *
 * Equivalent events can carry different raw denominators. Equality therefore
 * compares both rational coordinates by exact cross-denominator arithmetic.
 */
bool exactProperIntersectionsEqual(
    ref const ExactProperIntersection lhs,
    ref const ExactProperIntersection rhs
)
    pure nothrow @safe @nogc
{
    return
        exactCoordinatesEqual(
            lhs.xNumerator,
            lhs.denominator,
            rhs.xNumerator,
            rhs.denominator
        ) &&
        exactCoordinatesEqual(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );
}


/*
 * Orders two exact proper-intersection events along one non-degenerate source
 * segment.
 *
 * Non-vertical segments are strictly monotone in x; vertical segments are
 * strictly monotone in y. Exact coordinate comparison therefore orders events
 * without constructing a floating segment parameter.
 *
 * Returns -1, 0, or 1 according to source.a -> source.b order.
 */
int compareProperIntersectionsAlongSegment(T)(
    Segment2!T source,
    ref const ExactProperIntersection lhs,
    ref const ExactProperIntersection rhs
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    int comparison;

    if (source.a.x != source.b.x)
    {
        comparison =
            compareExactCoordinates(
                lhs.xNumerator,
                lhs.denominator,
                rhs.xNumerator,
                rhs.denominator
            );

        return
            source.a.x < source.b.x
                ? comparison
                : -comparison;
    }

    assert(source.a.y != source.b.y);

    comparison =
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );

    return
        source.a.y < source.b.y
            ? comparison
            : -comparison;
}


/*
 * Exact weighted sum:
 *
 *     weightA * a + weightB * b
 *
 * Both weights are non-negative exact orientation magnitudes.
 */
private SignedExactCoordinateNumerator weightedCoordinate(
    ref const DyadicProductMagnitude weightA,
    ref const SignedDyadicCoordinate a,
    ref const DyadicProductMagnitude weightB,
    ref const SignedDyadicCoordinate b
)
    pure nothrow @safe @nogc
{
    SignedExactCoordinateNumerator result;

    const auto magnitudeA =
        multiplyUnsigned(
            weightA,
            a.magnitude
        );

    const auto magnitudeB =
        multiplyUnsigned(
            weightB,
            b.magnitude
        );

    const bool zeroA =
        a.sign == 0 ||
        magnitudeA.isZero;

    const bool zeroB =
        b.sign == 0 ||
        magnitudeB.isZero;

    if (zeroA)
    {
        if (zeroB)
            return result;

        result.sign = b.sign;
        result.magnitude = magnitudeB;
        return result;
    }

    if (zeroB)
    {
        result.sign = a.sign;
        result.magnitude = magnitudeA;
        return result;
    }

    if (a.sign == b.sign)
    {
        result.sign = a.sign;

        result.magnitude =
            addUnsigned(
                magnitudeA,
                magnitudeB
            );

        return result;
    }

    const int comparison =
        compareUnsigned(
            magnitudeA,
            magnitudeB
        );

    if (comparison == 0)
        return result;

    if (comparison > 0)
    {
        result.sign = a.sign;

        result.magnitude =
            subtractUnsigned(
                magnitudeA,
                magnitudeB
            );
    }
    else
    {
        result.sign = b.sign;

        result.magnitude =
            subtractUnsigned(
                magnitudeB,
                magnitudeA
            );
    }

    return result;
}


/*
 * Constructs exact rational data from the two already established
 * opposite-side determinants of A and B relative to CD.
 */
private void buildProperIntersectionExact(T)(
    Segment2!T first,
    ref const SignedDyadicProduct dA,
    ref const SignedDyadicProduct dB,
    ref ExactProperIntersection result
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    const DyadicProductMagnitude weightA =
        dB.magnitude;

    const DyadicProductMagnitude weightB =
        dA.magnitude;

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    assert(!result.denominator.isZero);

    const auto aX =
        decodeDyadicCoordinate(
            first.a.x
        );

    const auto aY =
        decodeDyadicCoordinate(
            first.a.y
        );

    const auto bX =
        decodeDyadicCoordinate(
            first.b.x
        );

    const auto bY =
        decodeDyadicCoordinate(
            first.b.y
        );

    result.xNumerator =
        weightedCoordinate(
            weightA,
            aX,
            weightB,
            bX
        );

    result.yNumerator =
        weightedCoordinate(
            weightA,
            aY,
            weightB,
            bY
        );
}


/*
 * Exact construction for a crossing that has already been established
 * as a strict interior/interior crossing by the authoritative
 * intersection classifier.
 *
 * Only the two determinants required as barycentric weights are
 * evaluated here.
 */
void properIntersectionExactKnownCrossing(T)(
    Segment2!T first,
    Segment2!T second,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    const auto dA =
        orientationDeterminantDyadic(
            second.a.x,
            second.a.y,
            second.b.x,
            second.b.y,
            first.a.x,
            first.a.y
        );

    const auto dB =
        orientationDeterminantDyadic(
            second.a.x,
            second.a.y,
            second.b.x,
            second.b.y,
            first.b.x,
            first.b.y
        );

    /*
     * The caller has already established a strict proper crossing.
     */
    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    buildProperIntersectionExact(
        first,
        dA,
        dB,
        result
    );
}


/*
 * Exact construction for a strict crossing when the first/source segment has
 * already been decoded once by a caller that reuses it across many edges.
 *
 * The second segment is still decoded exactly once per crossing. Arithmetic,
 * fixed widths and exact rational result are identical to
 * properIntersectionExactKnownCrossing().
 */
private bool tryProperIntersectionExactKnownCrossingPreparedFirstCompact(T)(
    ref const PreparedExactSegment first,
    Segment2!T second,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    result =
        ExactProperIntersection.init;

    const auto preparedSecond =
        prepareExactSegment(
            second
        );

    CompactDyadicProduct dA;
    CompactDyadicProduct dB;

    if (
        !tryOrientationDeterminantCompactDecodedRaw(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.aX,
            first.aY,
            dA
        ) ||
        !tryOrientationDeterminantCompactDecodedRaw(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.bX,
            first.bY,
            dB
        )
    )
    {
        return false;
    }

    /*
     * The caller has already established a strict proper crossing. Recheck the
     * determinant signs here because the compact path is an independently
     * fallible optimization and must never weaken the fixed-path precondition.
     */
    if (
        dA.sign == 0 ||
        dB.sign == 0 ||
        dA.sign == dB.sign
    )
    {
        return false;
    }

    /*
     * The barycentric weights are the opposite determinant magnitudes:
     *
     *     weightA = |dB|
     *     weightB = |dA|
     */
    if (
        !tryCompactWeightDenominator(
            dB,
            dA,
            result.denominator
        ) ||
        !tryCompactWeightedCoordinate(
            dB,
            first.aX,
            dA,
            first.bX,
            result.xNumerator
        ) ||
        !tryCompactWeightedCoordinate(
            dB,
            first.aY,
            dA,
            first.bY,
            result.yNumerator
        )
    )
    {
        result =
            ExactProperIntersection.init;

        return false;
    }

    return true;
}


/*
 * Exact construction for a strict crossing when the first/source segment has
 * already been decoded once by a caller that reuses it across many edges.
 *
 * LDC first attempts the compact dyadic construction qualified by #132/#144.
 * Any unsupported compact intermediate falls back to the complete fixed-width
 * implementation below. DMD deliberately uses only the fixed-width path.
 */
package(geo)
void properIntersectionExactKnownCrossingPreparedFirst(T)(
    ref const PreparedExactSegment first,
    Segment2!T second,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    static if (useCompactPreparedConstruction)
    {
        if (
            tryProperIntersectionExactKnownCrossingPreparedFirstCompact(
                first,
                second,
                result
            )
        )
        {
            return;
        }
    }

    const auto preparedSecond =
        prepareExactSegment(
            second
        );

    const auto dA =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.aX,
            first.aY
        );

    const auto dB =
        orientationDeterminantDyadicDecoded(
            preparedSecond.aX,
            preparedSecond.aY,
            preparedSecond.bX,
            preparedSecond.bY,
            first.bX,
            first.bY
        );

    assert(dA.sign != 0);
    assert(dB.sign != 0);
    assert(dA.sign != dB.sign);

    const DyadicProductMagnitude weightA =
        dB.magnitude;

    const DyadicProductMagnitude weightB =
        dA.magnitude;

    result.denominator =
        addUnsigned(
            weightA,
            weightB
        );

    assert(!result.denominator.isZero);

    result.xNumerator =
        weightedCoordinate(
            weightA,
            first.aX,
            weightB,
            first.bX
        );

    result.yNumerator =
        weightedCoordinate(
            weightA,
            first.aY,
            weightB,
            first.bY
        );
}


/**
 * Builds exact rational construction data for a proper crossing.
 *
 * Returns true only when both non-degenerate segments cross strictly
 * through each other's interiors.
 *
 * Endpoint contact, T-junctions, collinear contact, overlap and
 * disjoint segments return false. Those cases are handled elsewhere by
 * the intersection construction layer.
 *
 * No division or rounded coordinate construction occurs here.
 */
bool tryProperIntersectionExact(T)(
    Segment2!T first,
    Segment2!T second,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
if (isExactIntersectionScalar!T)
{
    /*
     * Positions of A and B relative to supporting line CD.
     */
    const auto dA =
        orientationDeterminantDyadic(
            second.a.x,
            second.a.y,
            second.b.x,
            second.b.y,
            first.a.x,
            first.a.y
        );

    const auto dB =
        orientationDeterminantDyadic(
            second.a.x,
            second.a.y,
            second.b.x,
            second.b.y,
            first.b.x,
            first.b.y
        );

    if (
        dA.sign == 0 ||
        dB.sign == 0 ||
        dA.sign == dB.sign
    )
    {
        return false;
    }


    /*
     * Confirm that C and D also lie on strictly opposite sides of AB.
     *
     * This keeps this helper's contract independent of any preceding
     * classifier call.
     */
    const auto dC =
        orientationDeterminantDyadic(
            first.a.x,
            first.a.y,
            first.b.x,
            first.b.y,
            second.a.x,
            second.a.y
        );

    const auto dD =
        orientationDeterminantDyadic(
            first.a.x,
            first.a.y,
            first.b.x,
            first.b.y,
            second.b.x,
            second.b.y
        );

    if (
        dC.sign == 0 ||
        dD.sign == 0 ||
        dC.sign == dD.sign
    )
    {
        return false;
    }


    buildProperIntersectionExact(
        first,
        dA,
        dB,
        result
    );

    return true;
}


@safe unittest
{
    import geo.point : Point2;

    alias P = Point2!int;
    alias S = Segment2!int;


    /*
     * Symmetric diagonal crossing:
     *
     *     (0,0) ---- (10,10)
     *     (0,10) --- (10,0)
     *
     * Exact result is (5,5).
     *
     * Instead of dividing here, verify:
     *
     *     numerator == denominator * exact(5)
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const second =
            S(
                P(0, 10),
                P(10, 0)
            );

        ExactProperIntersection exact;

        assert(
            tryProperIntersectionExact(
                first,
                second,
                exact
            )
        );

        const auto five =
            decodeDyadicCoordinate(5);

        const auto expected =
            multiplyUnsigned(
                exact.denominator,
                five.magnitude
            );

        assert(exact.xNumerator.sign == 1);
        assert(exact.yNumerator.sign == 1);

        assert(
            exact.xNumerator.magnitude.limb ==
            expected.limb
        );

        assert(
            exact.yNumerator.magnitude.limb ==
            expected.limb
        );
    }


    /*
     * A prepared first segment must produce bit-identical exact construction.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const second =
            S(
                P(0, 10),
                P(10, 0)
            );

        ExactProperIntersection regular;
        ExactProperIntersection preparedResult;

        properIntersectionExactKnownCrossing(
            first,
            second,
            regular
        );

        const auto preparedFirst =
            prepareExactSegment(
                first
            );

        properIntersectionExactKnownCrossingPreparedFirst(
            preparedFirst,
            second,
            preparedResult
        );

        assert(
            regular.xNumerator.sign ==
            preparedResult.xNumerator.sign
        );

        assert(
            regular.xNumerator.magnitude.limb ==
            preparedResult.xNumerator.magnitude.limb
        );

        assert(
            regular.yNumerator.sign ==
            preparedResult.yNumerator.sign
        );

        assert(
            regular.yNumerator.magnitude.limb ==
            preparedResult.yNumerator.magnitude.limb
        );

        assert(
            regular.denominator.limb ==
            preparedResult.denominator.limb
        );
    }


    /*
     * Reversing either segment preserves the exact rational data when
     * AB remains the constructed segment.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 10)
            );

        const firstReversed =
            S(
                P(10, 10),
                P(0, 0)
            );

        const second =
            S(
                P(0, 10),
                P(10, 0)
            );

        const secondReversed =
            S(
                P(10, 0),
                P(0, 10)
            );

        ExactProperIntersection normal;
        ExactProperIntersection reverseFirst;
        ExactProperIntersection reverseSecond;

        assert(
            tryProperIntersectionExact(
                first,
                second,
                normal
            )
        );

        assert(
            tryProperIntersectionExact(
                firstReversed,
                second,
                reverseFirst
            )
        );

        assert(
            tryProperIntersectionExact(
                first,
                secondReversed,
                reverseSecond
            )
        );

        assert(
            normal.denominator.limb ==
            reverseFirst.denominator.limb
        );

        assert(
            normal.denominator.limb ==
            reverseSecond.denominator.limb
        );

        assert(
            normal.xNumerator.sign ==
            reverseFirst.xNumerator.sign
        );

        assert(
            normal.xNumerator.magnitude.limb ==
            reverseFirst.xNumerator.magnitude.limb
        );

        assert(
            normal.yNumerator.sign ==
            reverseFirst.yNumerator.sign
        );

        assert(
            normal.yNumerator.magnitude.limb ==
            reverseFirst.yNumerator.magnitude.limb
        );

        assert(
            normal.xNumerator.magnitude.limb ==
            reverseSecond.xNumerator.magnitude.limb
        );

        assert(
            normal.yNumerator.magnitude.limb ==
            reverseSecond.yNumerator.magnitude.limb
        );
    }


    /*
     * Endpoint contact is deliberately not a proper crossing.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(10, 0),
                P(10, 10)
            );

        ExactProperIntersection exact;

        assert(
            !tryProperIntersectionExact(
                first,
                second,
                exact
            )
        );
    }


    /*
     * T-junction is likewise handled by endpoint construction.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(5, 0),
                P(5, 10)
            );

        ExactProperIntersection exact;

        assert(
            !tryProperIntersectionExact(
                first,
                second,
                exact
            )
        );
    }


    /*
     * Collinear overlap is not a proper crossing.
     */
    {
        const first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const second =
            S(
                P(5, 0),
                P(15, 0)
            );

        ExactProperIntersection exact;

        assert(
            !tryProperIntersectionExact(
                first,
                second,
                exact
            )
        );
    }
}


version (LDC)
{
    @safe unittest
    {
        import geo.point : Point2;

        alias P = Point2!double;
        alias S = Segment2!double;

        /*
         * Ordinary proper crossing must take the compact construction path and
         * produce the same exact rational carriers as the authoritative fixed
         * implementation.
         */
        {
            const first =
                S(
                    P(0.0, 0.0),
                    P(10.0, 10.0)
                );

            const second =
                S(
                    P(0.0, 10.0),
                    P(10.0, 0.0)
                );

            const auto prepared =
                prepareExactSegment(
                    first
                );

            ExactProperIntersection compact;
            ExactProperIntersection fixed;

            assert(
                tryProperIntersectionExactKnownCrossingPreparedFirstCompact(
                    prepared,
                    second,
                    compact
                )
            );

            properIntersectionExactKnownCrossing(
                first,
                second,
                fixed
            );

            assert(
                compact.denominator.limb ==
                fixed.denominator.limb
            );

            assert(
                compact.xNumerator.sign ==
                fixed.xNumerator.sign
            );

            assert(
                compact.xNumerator.magnitude.limb ==
                fixed.xNumerator.magnitude.limb
            );

            assert(
                compact.yNumerator.sign ==
                fixed.yNumerator.sign
            );

            assert(
                compact.yNumerator.magnitude.limb ==
                fixed.yNumerator.magnitude.limb
            );
        }


        /*
         * A huge exponent spread makes the compact difference window
         * inapplicable. The public prepared construction must then fall back
         * to the fixed implementation without changing exact rational data.
         */
        {
            const double tiny =
                double.min_normal *
                double.epsilon;

            const first =
                S(
                    P(-double.max, 0.0),
                    P(double.max, 0.0)
                );

            const second =
                S(
                    P(tiny, -1.0),
                    P(double.max / 16.0, 1.0)
                );

            const auto prepared =
                prepareExactSegment(
                    first
                );

            ExactProperIntersection compact;
            ExactProperIntersection fixed;
            ExactProperIntersection fallback;

            assert(
                !tryProperIntersectionExactKnownCrossingPreparedFirstCompact(
                    prepared,
                    second,
                    compact
                )
            );

            properIntersectionExactKnownCrossing(
                first,
                second,
                fixed
            );

            properIntersectionExactKnownCrossingPreparedFirst(
                prepared,
                second,
                fallback
            );

            assert(
                fallback.denominator.limb ==
                fixed.denominator.limb
            );

            assert(
                fallback.xNumerator.sign ==
                fixed.xNumerator.sign
            );

            assert(
                fallback.xNumerator.magnitude.limb ==
                fixed.xNumerator.magnitude.limb
            );

            assert(
                fallback.yNumerator.sign ==
                fixed.yNumerator.sign
            );

            assert(
                fallback.yNumerator.magnitude.limb ==
                fixed.yNumerator.magnitude.limb
            );
        }
    }
}


@safe unittest
{
    import geo.point : Point2;

    alias P = Point2!double;
    alias S = Segment2!double;

    /*
     * Full-range binary64 stress case.
     *
     * The exact intersection is the origin, while ordinary determinant
     * formulas would overflow repeatedly.
     */
    const first =
        S(
            P(-double.max, 0.0),
            P(double.max, 0.0)
        );

    const second =
        S(
            P(0.0, -double.max),
            P(0.0, double.max)
        );

    ExactProperIntersection exact;

    assert(
        tryProperIntersectionExact(
            first,
            second,
            exact
        )
    );

    assert(!exact.denominator.isZero);

    assert(exact.xNumerator.sign == 0);
    assert(exact.xNumerator.magnitude.isZero);

    assert(exact.yNumerator.sign == 0);
    assert(exact.yNumerator.magnitude.isZero);

    static assert(
        exactCoordinateNumeratorLimbs == 198
    );
}


@safe unittest
{
    import geo.internal.exact_coordinate_round :
        roundExactCoordinateBinary64;

    import geo.point : Point2;


    /*
     * The same exact event can be constructed with different denominators.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const source = S(P(0, 0), P(10, 0));
        const shortCrossing = S(P(5, -1), P(5, 1));
        const longCrossing = S(P(5, -3), P(5, 7));

        ExactProperIntersection first;
        ExactProperIntersection second;

        assert(
            tryProperIntersectionExact(
                source,
                shortCrossing,
                first
            )
        );

        assert(
            tryProperIntersectionExact(
                source,
                longCrossing,
                second
            )
        );

        assert(first.denominator.limb != second.denominator.limb);
        assert(exactProperIntersectionsEqual(first, second));

        assert(
            compareProperIntersectionsAlongSegment(
                source,
                first,
                second
            ) == 0
        );
    }


    /*
     * Non-vertical and reversed source ordering.
     *
     * Crossings occur at x = 1/3 and x = 2/3.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const source = S(P(0, 0), P(10, 0));
        const reversed = S(P(10, 0), P(0, 0));

        const oneThird = S(P(0, -1), P(1, 2));
        const twoThird = S(P(0, -2), P(1, 1));

        ExactProperIntersection first;
        ExactProperIntersection second;

        assert(tryProperIntersectionExact(source, oneThird, first));
        assert(tryProperIntersectionExact(source, twoThird, second));

        assert(
            compareProperIntersectionsAlongSegment(
                source,
                first,
                second
            ) < 0
        );

        assert(
            compareProperIntersectionsAlongSegment(
                reversed,
                first,
                second
            ) > 0
        );

        assert(!exactProperIntersectionsEqual(first, second));
    }


    /*
     * Vertical sources use exact y ordering.
     */
    {
        alias P = Point2!int;
        alias S = Segment2!int;

        const source = S(P(0, 0), P(0, 10));
        const lowerCrossing = S(P(-1, 2), P(1, 2));
        const upperCrossing = S(P(-1, 7), P(1, 7));

        ExactProperIntersection lower;
        ExactProperIntersection upper;

        assert(
            tryProperIntersectionExact(
                source,
                lowerCrossing,
                lower
            )
        );

        assert(
            tryProperIntersectionExact(
                source,
                upperCrossing,
                upper
            )
        );

        assert(
            compareProperIntersectionsAlongSegment(
                source,
                lower,
                upper
            ) < 0
        );
    }


    /*
     * Distinct exact events can correctly round to the same binary64 point.
     * Rounded construction must therefore never be an arrangement-event key.
     */
    {
        alias P = Point2!double;
        alias S = Segment2!double;

        enum double a0 = 0x1p-10;
        enum double a1 = 0x1.0000000000001p-10;
        enum double b = 0x1p-10;

        const source = S(P(0.0, 0.0), P(1.0, 0.0));

        const firstCrossing =
            S(
                P(0.0, -a0),
                P(1.0, b)
            );

        const secondCrossing =
            S(
                P(0.0, -a1),
                P(1.0, b)
            );

        ExactProperIntersection first;
        ExactProperIntersection second;

        assert(
            tryProperIntersectionExact(
                source,
                firstCrossing,
                first
            )
        );

        assert(
            tryProperIntersectionExact(
                source,
                secondCrossing,
                second
            )
        );

        assert(
            compareProperIntersectionsAlongSegment(
                source,
                first,
                second
            ) < 0
        );

        assert(!exactProperIntersectionsEqual(first, second));

        const double firstRounded =
            roundExactCoordinateBinary64(
                first.xNumerator,
                first.denominator
            );

        const double secondRounded =
            roundExactCoordinateBinary64(
                second.xNumerator,
                second.denominator
            );

        assert(firstRounded == 0.5);
        assert(secondRounded == 0.5);
        assert(firstRounded == secondRounded);
    }
}
