module geo.internal.intersection_exact;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    dyadicCoordinateLimbs,
    dyadicProductLimbs;

import geo.internal.fixed_uint :
    UIntFixed,
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;

import geo.internal.orientation_dyadic :
    orientationDeterminantDyadic;

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


/*
 * Maximum width of:
 *
 *     orientation-weight * coordinate
 *
 *     132 limbs + 66 limbs = 198 limbs
 *
 * The exact bounds are tighter than these storage widths, leaving
 * enough room for addition of the two weighted terms.
 */
enum size_t intersectionNumeratorLimbs =
    dyadicProductLimbs +
    dyadicCoordinateLimbs;


alias IntersectionNumeratorMagnitude =
    UIntFixed!intersectionNumeratorLimbs;


/**
 * Signed exact numerator for one constructed coordinate.
 *
 * The corresponding geometric coordinate is:
 *
 *     numerator / denominator * 2^-1074
 *
 * where denominator is stored by ExactProperIntersection.
 */
struct SignedIntersectionNumerator
{
    int sign;
    IntersectionNumeratorMagnitude magnitude;
}


/**
 * Exact rational construction data for one proper segment crossing.
 *
 * Both coordinates share the same positive denominator.
 */
struct ExactProperIntersection
{
    SignedIntersectionNumerator xNumerator;
    SignedIntersectionNumerator yNumerator;

    DyadicProductMagnitude denominator;
}


/*
 * Exact weighted sum:
 *
 *     weightA * a + weightB * b
 *
 * Both weights are non-negative exact orientation magnitudes.
 */
private SignedIntersectionNumerator weightedCoordinate(
    ref const DyadicProductMagnitude weightA,
    ref const SignedDyadicCoordinate a,
    ref const DyadicProductMagnitude weightB,
    ref const SignedDyadicCoordinate b
)
    pure nothrow @safe @nogc
{
    SignedIntersectionNumerator result;

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
        intersectionNumeratorLimbs == 198
    );
}
