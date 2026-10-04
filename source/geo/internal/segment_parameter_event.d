module geo.internal.segment_parameter_event;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    DyadicProductMagnitude,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;

import geo.internal.fixed_uint :
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned;

import geo.internal.intersection_exact :
    ExactSegmentParameter;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact source-segment parameter ordering for clipping/noding events.
 *
 * Every event is represented as one exact rational t in [0,1]:
 *
 *     t = numerator / denominator
 *
 * No Cartesian exact intersection is required for ordering/equality.
 */


private enum bool isExactSourceParameterScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


package(geo)
struct ExactSourceParameter
{
    DyadicProductMagnitude numerator;
    DyadicProductMagnitude denominator;
}


private void embedCoordinateMagnitude(
    ref DyadicProductMagnitude destination,
    ref const DyadicCoordinateMagnitude source
)
    pure nothrow @safe @nogc
{
    foreach (i, limb; source.limb)
        destination.limb[i] = limb;
}


package(geo)
ExactSourceParameter exactSourceParameter(T)(
    Segment2!T source,
    Point2!T point
)
    pure nothrow @safe @nogc
if (isExactSourceParameterScalar!T)
{
    T sourceA;
    T sourceB;
    T pointValue;

    if (source.a.x != source.b.x)
    {
        sourceA = source.a.x;
        sourceB = source.b.x;
        pointValue = point.x;
    }
    else
    {
        sourceA = source.a.y;
        sourceB = source.b.y;
        pointValue = point.y;
    }

    const auto a =
        decodeDyadicCoordinate(sourceA);

    const auto b =
        decodeDyadicCoordinate(sourceB);

    const auto p =
        decodeDyadicCoordinate(pointValue);

    const auto total =
        subtractDyadicCoordinates(
            b,
            a
        );

    const auto part =
        subtractDyadicCoordinates(
            p,
            a
        );

    assert(total.sign != 0);
    assert(
        part.sign == 0 ||
        part.sign == total.sign
    );

    ExactSourceParameter result;

    embedCoordinateMagnitude(
        result.denominator,
        total.magnitude
    );

    if (part.sign != 0)
    {
        embedCoordinateMagnitude(
            result.numerator,
            part.magnitude
        );
    }

    assert(!result.denominator.isZero);

    return result;
}


package(geo)
ExactSourceParameter exactSourceParameter(
    ref const ExactSegmentParameter crossing
)
    pure nothrow @safe @nogc
{
    assert(!crossing.weightA.isZero);
    assert(!crossing.weightB.isZero);

    return
        ExactSourceParameter(
            crossing.weightB,
            addUnsigned(
                crossing.weightA,
                crossing.weightB
            )
        );
}


package(geo)
int compareExactSourceParameters(
    ref const ExactSourceParameter lhs,
    ref const ExactSourceParameter rhs
)
    pure nothrow @safe @nogc
{
    assert(!lhs.denominator.isZero);
    assert(!rhs.denominator.isZero);

    const auto left =
        multiplyUnsigned(
            lhs.numerator,
            rhs.denominator
        );

    const auto right =
        multiplyUnsigned(
            rhs.numerator,
            lhs.denominator
        );

    return compareUnsigned(left, right);
}


package(geo)
bool exactSourceParametersEqual(
    ref const ExactSourceParameter lhs,
    ref const ExactSourceParameter rhs
)
    pure nothrow @safe @nogc
{
    return
        compareExactSourceParameters(
            lhs,
            rhs
        ) == 0;
}


@safe unittest
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const source =
        S(
            P(0.0, 0.0),
            P(10.0, 0.0)
        );

    const a =
        exactSourceParameter(
            source,
            P(2.0, 0.0)
        );

    const b =
        exactSourceParameter(
            source,
            P(7.0, 0.0)
        );

    assert(
        compareExactSourceParameters(
            a,
            b
        ) < 0
    );

    assert(
        exactSourceParametersEqual(
            a,
            a
        )
    );
}
