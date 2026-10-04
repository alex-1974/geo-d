module geo.internal.segment_parameter_event;

import geo.internal.dyadic :
    DyadicCoordinateMagnitude,
    DyadicProductMagnitude,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;

import geo.internal.fixed_uint :
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    ExactSegmentParameter,
    PreparedExactSegment,
    materializeExactSegmentWeights;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact source-segment parameter ordering for clipping/noding events.
 *
 * Every event is represented by the two nonnegative exact source weights:
 *
 *     P = (weightA * A + weightB * B) / (weightA + weightB)
 *     t = weightB / (weightA + weightB)
 *
 * Storing the direct weights preserves the high-performing proper-crossing
 * research shape and avoids materializing dense denominator carriers merely
 * for event ordering.
 */


private enum bool isExactSourceParameterScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


package(geo)
struct ExactSourceParameter
{
    DyadicProductMagnitude weightA;
    DyadicProductMagnitude weightB;
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

    DyadicProductMagnitude totalMagnitude;
    DyadicProductMagnitude partMagnitude;

    embedCoordinateMagnitude(
        totalMagnitude,
        total.magnitude
    );

    if (part.sign != 0)
    {
        embedCoordinateMagnitude(
            partMagnitude,
            part.magnitude
        );
    }

    assert(!totalMagnitude.isZero);

    return
        ExactSourceParameter(
            subtractUnsigned(
                totalMagnitude,
                partMagnitude
            ),
            partMagnitude,
            totalMagnitude
        );
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
            crossing.weightA,
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
    assert(
        !lhs.weightA.isZero ||
        !lhs.weightB.isZero
    );

    assert(
        !rhs.weightA.isZero ||
        !rhs.weightB.isZero
    );

    const auto left =
        multiplyUnsigned(
            lhs.weightB,
            rhs.weightA
        );

    const auto right =
        multiplyUnsigned(
            rhs.weightB,
            lhs.weightA
        );

    return compareUnsigned(left, right);
}


package(geo)
void materializeExactSourceParameter(
    ref const PreparedExactSegment source,
    ref const ExactSourceParameter parameter,
    out ExactProperIntersection result
)
    pure nothrow @safe @nogc
{
    assert(
        !parameter.weightA.isZero ||
        !parameter.weightB.isZero
    );

    materializeExactSegmentWeights(
        source,
        parameter.weightA,
        parameter.weightB,
        result
    );
}


package(geo)
size_t sortUniqueExactSourceParameters(
    scope ExactSourceParameter[] events
)
    pure nothrow @safe @nogc
{
    if (events.length < 2)
        return events.length;

    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;

        size_t root = start;

        while (true)
        {
            const size_t left =
                root * 2 + 1;

            if (left >= events.length)
                break;

            size_t largest = root;

            if (
                compareExactSourceParameters(
                    events[largest],
                    events[left]
                ) < 0
            )
            {
                largest = left;
            }

            const size_t right =
                left + 1;

            if (
                right < events.length &&
                compareExactSourceParameters(
                    events[largest],
                    events[right]
                ) < 0
            )
            {
                largest = right;
            }

            if (largest == root)
                break;

            const auto temporary =
                events[root];

            events[root] =
                events[largest];

            events[largest] =
                temporary;

            root = largest;
        }
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const auto temporary =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporary;

        size_t root = 0;

        while (true)
        {
            const size_t left =
                root * 2 + 1;

            if (left >= end)
                break;

            size_t largest = root;

            if (
                compareExactSourceParameters(
                    events[largest],
                    events[left]
                ) < 0
            )
            {
                largest = left;
            }

            const size_t right =
                left + 1;

            if (
                right < end &&
                compareExactSourceParameters(
                    events[largest],
                    events[right]
                ) < 0
            )
            {
                largest = right;
            }

            if (largest == root)
                break;

            const auto swapValue =
                events[root];

            events[root] =
                events[largest];

            events[largest] =
                swapValue;

            root = largest;
        }
    }

    size_t write = 1;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactSourceParametersEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            events[write++] =
                events[read];
        }
    }

    return write;
}


private size_t activeEnd(
    ref const DyadicProductMagnitude value
)
    pure nothrow @safe @nogc
{
    for (size_t i = value.limb.length; i != 0; --i)
    {
        if (value.limb[i - 1] != 0)
            return i;
    }

    return 0;
}


private size_t packDenseParameterEnds(
    ref const ExactSourceParameter event
)
    pure nothrow @safe @nogc
{
    const size_t numeratorEnd =
        activeEnd(event.weightB);

    const size_t denominatorEnd =
        activeEnd(event.denominator);

    assert(numeratorEnd <= ushort.max);
    assert(denominatorEnd <= ushort.max);

    return
        numeratorEnd |
        (denominatorEnd << 16);
}


private size_t denseParameterNumeratorEnd(size_t metadata)
    pure nothrow @safe @nogc
{
    return metadata & 0xFFFF;
}


private size_t denseParameterDenominatorEnd(size_t metadata)
    pure nothrow @safe @nogc
{
    return (metadata >> 16) & 0xFFFF;
}


private bool equalUnsignedBounded(
    ref const DyadicProductMagnitude lhs,
    size_t lhsEnd,
    ref const DyadicProductMagnitude rhs,
    size_t rhsEnd
)
    pure nothrow @safe @nogc
{
    if (lhsEnd != rhsEnd)
        return false;

    foreach (i; 0 .. lhsEnd)
    {
        if (lhs.limb[i] != rhs.limb[i])
            return false;
    }

    return true;
}


private int compareUnsignedBounded(
    ref const DyadicProductMagnitude lhs,
    size_t lhsEnd,
    ref const DyadicProductMagnitude rhs,
    size_t rhsEnd
)
    pure nothrow @safe @nogc
{
    if (lhsEnd < rhsEnd)
        return -1;

    if (lhsEnd > rhsEnd)
        return 1;

    size_t i = lhsEnd;

    while (i != 0)
    {
        --i;

        if (lhs.limb[i] < rhs.limb[i])
            return -1;

        if (lhs.limb[i] > rhs.limb[i])
            return 1;
    }

    return 0;
}


private int compareExactSourceParametersEqualPreferredBounded(
    ref const ExactSourceParameter lhs,
    size_t lhsMetadata,
    ref const ExactSourceParameter rhs,
    size_t rhsMetadata
)
    pure nothrow @safe @nogc
{
    const size_t lhsDenominatorEnd =
        denseParameterDenominatorEnd(lhsMetadata);

    const size_t rhsDenominatorEnd =
        denseParameterDenominatorEnd(rhsMetadata);

    if (
        equalUnsignedBounded(
            lhs.denominator,
            lhsDenominatorEnd,
            rhs.denominator,
            rhsDenominatorEnd
        )
    )
    {
        return
            compareUnsignedBounded(
                lhs.weightB,
                denseParameterNumeratorEnd(lhsMetadata),
                rhs.weightB,
                denseParameterNumeratorEnd(rhsMetadata)
            );
    }

    return
        compareExactSourceParameters(
            lhs,
            rhs
        );
}


package(geo)
size_t sortUniqueExactSourceParametersWithRawMapping(
    scope ExactSourceParameter[] events,
    scope size_t[] rawEventIndices,
    scope size_t[] rawToUnique
)
    pure nothrow @safe @nogc
{
    assert(rawEventIndices.length >= events.length);
    assert(rawToUnique.length >= events.length);

    foreach (i; 0 .. events.length)
        rawEventIndices[i] = i;

    if (events.length >= 2)
    {
        size_t start =
            events.length / 2;

        while (start > 0)
        {
            --start;
            size_t root = start;

            while (true)
            {
                const size_t left =
                    root * 2 + 1;

                if (left >= events.length)
                    break;

                size_t largest = root;

                if (
                    compareExactSourceParameters(
                        events[largest],
                        events[left]
                    ) < 0
                )
                {
                    largest = left;
                }

                const size_t right =
                    left + 1;

                if (
                    right < events.length &&
                    compareExactSourceParameters(
                        events[largest],
                        events[right]
                    ) < 0
                )
                {
                    largest = right;
                }

                if (largest == root)
                    break;

                const auto eventSwap =
                    events[root];

                events[root] =
                    events[largest];

                events[largest] =
                    eventSwap;

                const size_t indexSwap =
                    rawEventIndices[root];

                rawEventIndices[root] =
                    rawEventIndices[largest];

                rawEventIndices[largest] =
                    indexSwap;

                root = largest;
            }
        }

        size_t end =
            events.length;

        while (end > 1)
        {
            --end;

            const auto eventSwap =
                events[0];

            events[0] =
                events[end];

            events[end] =
                eventSwap;

            const size_t indexSwap =
                rawEventIndices[0];

            rawEventIndices[0] =
                rawEventIndices[end];

            rawEventIndices[end] =
                indexSwap;

            size_t root = 0;

            while (true)
            {
                const size_t left =
                    root * 2 + 1;

                if (left >= end)
                    break;

                size_t largest = root;

                if (
                    compareExactSourceParameters(
                        events[largest],
                        events[left]
                    ) < 0
                )
                {
                    largest = left;
                }

                const size_t right =
                    left + 1;

                if (
                    right < end &&
                    compareExactSourceParameters(
                        events[largest],
                        events[right]
                    ) < 0
                )
                {
                    largest = right;
                }

                if (largest == root)
                    break;

                const auto siftEvent =
                    events[root];

                events[root] =
                    events[largest];

                events[largest] =
                    siftEvent;

                const size_t siftIndex =
                    rawEventIndices[root];

                rawEventIndices[root] =
                    rawEventIndices[largest];

                rawEventIndices[largest] =
                    siftIndex;

                root = largest;
            }
        }
    }

    if (events.length == 0)
        return 0;

    size_t write = 1;
    rawToUnique[rawEventIndices[0]] = 0;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactSourceParametersEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            events[write] =
                events[read];

            ++write;
        }

        rawToUnique[
            rawEventIndices[read]
        ] =
            write - 1;
    }

    return write;
}


package(geo)
size_t findExactSourceParameterIndex(
    scope const(ExactSourceParameter)[] events,
    ref const ExactSourceParameter target
)
    pure nothrow @safe @nogc
{
    size_t lower = 0;
    size_t upper =
        events.length;

    while (lower < upper)
    {
        const size_t middle =
            lower + (upper - lower) / 2;

        if (
            compareExactSourceParameters(
                events[middle],
                target
            ) < 0
        )
        {
            lower = middle + 1;
        }
        else
        {
            upper = middle;
        }
    }

    if (
        lower < events.length &&
        exactSourceParametersEqual(
            events[lower],
            target
        )
    )
    {
        return lower;
    }

    return size_t.max;
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

    const start =
        exactSourceParameter(
            source,
            P(0.0, 0.0)
        );

    const midpoint =
        exactSourceParameter(
            source,
            P(5.0, 0.0)
        );

    const end =
        exactSourceParameter(
            source,
            P(10.0, 0.0)
        );

    ExactSegmentParameter crossing;
    crossing.weightA.limb[0] = 1;
    crossing.weightB.limb[0] = 1;

    const crossingMidpoint =
        exactSourceParameter(
            crossing
        );

    assert(
        compareExactSourceParameters(
            start,
            midpoint
        ) < 0
    );

    assert(
        compareExactSourceParameters(
            midpoint,
            end
        ) < 0
    );

    assert(
        exactSourceParametersEqual(
            midpoint,
            crossingMidpoint
        )
    );
}
