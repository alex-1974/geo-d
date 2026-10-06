module geo.internal.polygon_union_exact;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    decodeDyadicCoordinate,
    dyadicProductLimbs;

import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator,
    compareCanonicalExactCoordinatesEqualPreferred,
    compareExactCoordinates,
    compareExactCoordinatesEqualPreferred,
    exactCoordinateNumeratorLimbs;

import geo.internal.fixed_uint :
    UIntFixed,
    addUnsigned,
    compareUnsigned,
    multiplyUnsigned,
    subtractUnsigned;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    PreparedExactSegment,
    prepareExactSegment,
    properIntersectionExactKnownCrossing,
    properIntersectionExactKnownCrossingPreparedFirst,
    tryProperIntersectionExact;

import geo.intersection :
    SegmentContactKind,
    segmentContactKind;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact point representation used by the polygon-union overlay core.
 *
 * Input vertices and constructed proper-intersection events are lifted into
 * the same rational coordinate model:
 *
 *     numerator
 *     ----------- * 2^-1074
 *     denominator
 *
 * with one positive denominator shared by x and y.
 *
 * Rounded construction coordinates are deliberately absent here. Arrangement
 * identity and edge-event ordering are exact.
 */


private enum bool isPolygonUnionExactScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * Exact internal arrangement point.
 *
 * This type is implementation-only. It is not a public exact-geometry scalar
 * or consumer-visible polygon coordinate.
 */
struct ExactOverlayPoint
{
    SignedExactCoordinateNumerator xNumerator;
    SignedExactCoordinateNumerator yNumerator;

    DyadicProductMagnitude denominator;
}


/*
 * Lifts one represented finite coordinate into the established exact rational
 * construction domain with denominator 1.
 *
 * decodeDyadicCoordinate represents every supported input exactly in the
 * common 2^-1074 scale. Its 66-limb magnitude is embedded without arithmetic
 * into the established 198-limb exact-coordinate numerator.
 */
private SignedExactCoordinateNumerator liftRepresentedCoordinate(T)(
    T value
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    const auto coordinate =
        decodeDyadicCoordinate(value);

    SignedExactCoordinateNumerator result;
    result.sign = coordinate.sign;

    foreach (i, limb; coordinate.magnitude.limb)
    {
        result.magnitude.limb[i] =
            limb;
    }

    return result;
}


/*
 * Lifts one represented input point exactly into overlay space.
 */
ExactOverlayPoint exactOverlayPoint(T)(
    Point2!T point
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    ExactOverlayPoint result;

    result.xNumerator =
        liftRepresentedCoordinate(
            point.x
        );

    result.yNumerator =
        liftRepresentedCoordinate(
            point.y
        );

    result.denominator.limb[0] = 1;

    return result;
}


/*
 * Re-expresses an already exact proper-intersection event as an overlay point.
 *
 * No arithmetic or normalization is needed because ExactProperIntersection
 * already uses the same numerator/denominator model.
 */
ExactOverlayPoint exactOverlayPoint(
    ref const ExactProperIntersection intersection
)
    pure nothrow @safe @nogc
{
    return
        ExactOverlayPoint(
            intersection.xNumerator,
            intersection.yNumerator,
            intersection.denominator
        );
}


/*
 * One homogeneous orientation term contains two exact coordinate numerators
 * and one positive exact denominator:
 *
 *     198 + 198 + 132 = 528 32-bit limbs.
 *
 * A 3x3 determinant contains six signed terms. One additional limb provides
 * more than the required three bits of accumulation headroom.
 */
private enum size_t exactOverlayOrientationTermLimbs =
    exactCoordinateNumeratorLimbs * 2 +
    dyadicProductLimbs;

private enum size_t exactOverlayOrientationAccumulatorLimbs =
    exactOverlayOrientationTermLimbs + 1;

private alias ExactOverlayOrientationTermMagnitude =
    UIntFixed!exactOverlayOrientationTermLimbs;

private alias ExactOverlayOrientationAccumulatorMagnitude =
    UIntFixed!exactOverlayOrientationAccumulatorLimbs;


private struct ExactOverlayOrientationAccumulator
{
    int sign;
    ExactOverlayOrientationAccumulatorMagnitude magnitude;
}


private ExactOverlayOrientationAccumulatorMagnitude
widenOverlayOrientationTerm(
    ref const ExactOverlayOrientationTermMagnitude term
)
    pure nothrow @safe @nogc
{
    ExactOverlayOrientationAccumulatorMagnitude result;

    foreach (i; 0 .. exactOverlayOrientationTermLimbs)
        result.limb[i] = term.limb[i];

    return result;
}


private void addOverlayOrientationTerm(
    ref ExactOverlayOrientationAccumulator accumulator,
    int termSign,
    ref const ExactOverlayOrientationTermMagnitude term
)
    pure nothrow @safe @nogc
{
    assert(
        termSign == -1 ||
        termSign == 0 ||
        termSign == 1
    );

    if (
        termSign == 0 ||
        term.isZero
    )
    {
        return;
    }

    const auto widened =
        widenOverlayOrientationTerm(
            term
        );

    if (
        accumulator.sign == 0 ||
        accumulator.magnitude.isZero
    )
    {
        accumulator.sign =
            termSign;

        accumulator.magnitude =
            widened;

        return;
    }

    if (
        accumulator.sign ==
        termSign
    )
    {
        accumulator.magnitude =
            addUnsigned(
                accumulator.magnitude,
                widened
            );

        return;
    }

    const int comparison =
        compareUnsigned(
            accumulator.magnitude,
            widened
        );

    if (comparison == 0)
    {
        accumulator =
            ExactOverlayOrientationAccumulator.init;

        return;
    }

    if (comparison > 0)
    {
        accumulator.magnitude =
            subtractUnsigned(
                accumulator.magnitude,
                widened
            );

        return;
    }

    accumulator.magnitude =
        subtractUnsigned(
            widened,
            accumulator.magnitude
        );

    accumulator.sign =
        termSign;
}


private ExactOverlayOrientationTermMagnitude
multiplyExactNumeratorsAndDenominator(
    ref const SignedExactCoordinateNumerator first,
    ref const SignedExactCoordinateNumerator second,
    ref const DyadicProductMagnitude denominator
)
    pure nothrow @safe @nogc
{
    if (
        first.sign == 0 ||
        first.magnitude.isZero ||
        second.sign == 0 ||
        second.magnitude.isZero
    )
    {
        return
            ExactOverlayOrientationTermMagnitude.init;
    }

    const auto numeratorProduct =
        multiplyUnsigned(
            first.magnitude,
            second.magnitude
        );

    return
        multiplyUnsigned(
            numeratorProduct,
            denominator
        );
}


private int exactNumeratorProductSign(
    ref const SignedExactCoordinateNumerator first,
    ref const SignedExactCoordinateNumerator second
)
    pure nothrow @safe @nogc
{
    if (
        first.sign == 0 ||
        first.magnitude.isZero ||
        second.sign == 0 ||
        second.magnitude.isZero
    )
    {
        return 0;
    }

    return
        first.sign ==
        second.sign
            ? 1
            : -1;
}


/*
 * Exact orientation of three rational overlay points.
 *
 * Each point stores:
 *
 *     (xNumerator / denominator,
 *      yNumerator / denominator) * 2^-1074
 *
 * Denominators are positive. Multiplying the usual orientation determinant
 * by the positive common denominator product leaves the sign unchanged and
 * yields the homogeneous determinant
 *
 *     | ax ay ad |
 *     | bx by bd |
 *     | cx cy cd |
 *
 * expanded into six fixed-width integer terms.
 *
 * Returns:
 *
 *     -1 clockwise
 *      0 collinear
 *      1 counter-clockwise
 *
 * No floating-point construction, GCD normalization, or allocation occurs.
 */
int orientationExactOverlayPoints(
    ref const ExactOverlayPoint a,
    ref const ExactOverlayPoint b,
    ref const ExactOverlayPoint c
)
    pure nothrow @safe @nogc
{
    assert(!a.denominator.isZero);
    assert(!b.denominator.isZero);
    assert(!c.denominator.isZero);

    ExactOverlayOrientationAccumulator accumulator;


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                a.xNumerator,
                b.yNumerator,
                c.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            exactNumeratorProductSign(
                a.xNumerator,
                b.yNumerator
            ),
            term
        );
    }


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                a.xNumerator,
                c.yNumerator,
                b.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            -exactNumeratorProductSign(
                a.xNumerator,
                c.yNumerator
            ),
            term
        );
    }


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                a.yNumerator,
                b.xNumerator,
                c.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            -exactNumeratorProductSign(
                a.yNumerator,
                b.xNumerator
            ),
            term
        );
    }


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                a.yNumerator,
                c.xNumerator,
                b.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            exactNumeratorProductSign(
                a.yNumerator,
                c.xNumerator
            ),
            term
        );
    }


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                b.xNumerator,
                c.yNumerator,
                a.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            exactNumeratorProductSign(
                b.xNumerator,
                c.yNumerator
            ),
            term
        );
    }


    {
        const auto term =
            multiplyExactNumeratorsAndDenominator(
                b.yNumerator,
                c.xNumerator,
                a.denominator
            );

        addOverlayOrientationTerm(
            accumulator,
            -exactNumeratorProductSign(
                b.yNumerator,
                c.xNumerator
            ),
            term
        );
    }


    if (accumulator.magnitude.isZero)
        return 0;

    assert(
        accumulator.sign == -1 ||
        accumulator.sign == 1
    );

    return accumulator.sign;
}


static assert(
    exactOverlayOrientationTermLimbs ==
    528
);

static assert(
    exactOverlayOrientationAccumulatorLimbs ==
    529
);


/*
 * Exact lexicographic ordering of arrangement points.
 *
 * Raw unreduced numerator/denominator storage is not used as identity.
 */
int compareExactOverlayPoints(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    const int xComparison =
        compareExactCoordinates(
            lhs.xNumerator,
            lhs.denominator,
            rhs.xNumerator,
            rhs.denominator
        );

    if (xComparison != 0)
        return xComparison;

    return
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );
}


/*
 * Exact arrangement-point equality.
 */
bool exactOverlayPointsEqual(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    return
        compareExactOverlayPoints(
            lhs,
            rhs
        ) == 0;
}


/*
 * Orders exact overlay events along one represented non-degenerate source
 * segment from source.a toward source.b.
 *
 * A non-vertical segment is strictly monotone in x. A vertical segment is
 * strictly monotone in y. Therefore exact coordinate comparison orders all
 * points known to lie on the segment without constructing a floating-point
 * segment parameter.
 *
 * Returns -1, 0, or 1 according to source.a -> source.b order.
 */
int compareExactOverlayPointsAlongSegment(T)(
    Segment2!T source,
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);

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
 * Seeds one source edge with its two exact endpoint events.
 *
 * The caller supplies storage because the eventual P1 overlay layer owns the
 * variable-size event buffers. No allocation is hidden here.
 */
bool seedExactEdgeEvents(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    out size_t count
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    count = 0;

    if (events.length < 2)
        return false;

    assert(source.a != source.b);

    events[0] =
        exactOverlayPoint(
            source.a
        );

    events[1] =
        exactOverlayPoint(
            source.b
        );

    count = 2;

    return true;
}


/*
 * Appends one exact point to caller-provided event storage.
 */
private bool appendExactEdgeEvent(
    scope ExactOverlayPoint[] events,
    ref size_t count,
    ref const ExactOverlayPoint event
)
    pure nothrow @safe @nogc
{
    if (count >= events.length)
        return false;

    events[count++] = event;

    return true;
}


/*
 * Adds all exact noding events created by one source-segment pair to both
 * caller-provided edge-event buffers.
 *
 * none:
 *     adds nothing
 *
 * touch:
 *     adds the exact represented input endpoint to both edges
 *
 * properCrossing:
 *     adds one ExactProperIntersection promoted without rounding
 *
 * overlap:
 *     adds the two exact represented overlap endpoints to both edges
 *
 * Capacity is checked before any writes, so a false return leaves both counts
 * unchanged.
 */
bool appendSegmentPairNodingEvents(T)(
    Segment2!T first,
    Segment2!T second,
    scope ExactOverlayPoint[] firstEvents,
    ref size_t firstCount,
    scope ExactOverlayPoint[] secondEvents,
    ref size_t secondCount
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    import geo.intersection :
        SegmentContactKind,
        segmentContactKind,
        trySegmentIntersectionOverlap,
        trySegmentTouchPoint;

    const SegmentContactKind contact =
        segmentContactKind(
            first,
            second
        );

    size_t required = 0;

    final switch (contact)
    {
        case SegmentContactKind.none:
            return true;

        case SegmentContactKind.touch:
        case SegmentContactKind.properCrossing:
            required = 1;
            break;

        case SegmentContactKind.overlap:
            required = 2;
            break;
    }

    if (
        firstCount > firstEvents.length ||
        secondCount > secondEvents.length ||
        required > firstEvents.length - firstCount ||
        required > secondEvents.length - secondCount
    )
    {
        return false;
    }

    final switch (contact)
    {
        case SegmentContactKind.none:
            assert(false);

        case SegmentContactKind.touch:
        {
            Point2!T point;

            const bool found =
                trySegmentTouchPoint(
                    first,
                    second,
                    point
                );

            assert(found);

            const auto event =
                exactOverlayPoint(
                    point
                );

            const bool firstAdded =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    event
                );

            const bool secondAdded =
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    event
                );

            assert(firstAdded);
            assert(secondAdded);

            return true;
        }

        case SegmentContactKind.properCrossing:
        {
            ExactProperIntersection exact;

            properIntersectionExactKnownCrossing(
                first,
                second,
                exact
            );

            const auto event =
                exactOverlayPoint(
                    exact
                );

            const bool firstAdded =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    event
                );

            const bool secondAdded =
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    event
                );

            assert(firstAdded);
            assert(secondAdded);

            return true;
        }

        case SegmentContactKind.overlap:
        {
            Segment2!T overlap;

            const bool found =
                trySegmentIntersectionOverlap(
                    first,
                    second,
                    overlap
                );

            assert(found);

            const auto lower =
                exactOverlayPoint(
                    overlap.a
                );

            const auto upper =
                exactOverlayPoint(
                    overlap.b
                );

            bool added =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    lower
                );

            added =
                added &&
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    upper
                );

            added =
                added &&
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    lower
                );

            added =
                added &&
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    upper
                );

            assert(added);

            return true;
        }
    }
}


bool appendSegmentPairNodingEventsKnownContact(T)(
    Segment2!T first,
    Segment2!T second,
    SegmentContactKind contact,
    scope ExactOverlayPoint[] firstEvents,
    ref size_t firstCount,
    scope ExactOverlayPoint[] secondEvents,
    ref size_t secondCount
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    import geo.intersection :
        trySegmentIntersectionOverlap,
        trySegmentTouchPoint;

    size_t required = 0;

    final switch (contact)
    {
        case SegmentContactKind.none:
            return true;

        case SegmentContactKind.touch:
        case SegmentContactKind.properCrossing:
            required = 1;
            break;

        case SegmentContactKind.overlap:
            required = 2;
            break;
    }

    if (
        firstCount > firstEvents.length ||
        secondCount > secondEvents.length ||
        required > firstEvents.length - firstCount ||
        required > secondEvents.length - secondCount
    )
    {
        return false;
    }

    final switch (contact)
    {
        case SegmentContactKind.none:
            assert(false);

        case SegmentContactKind.touch:
        {
            Point2!T point;

            const bool found =
                trySegmentTouchPoint(
                    first,
                    second,
                    point
                );

            assert(found);

            const auto event =
                exactOverlayPoint(
                    point
                );

            const bool firstAdded =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    event
                );

            const bool secondAdded =
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    event
                );

            assert(firstAdded);
            assert(secondAdded);

            return true;
        }

        case SegmentContactKind.properCrossing:
        {
            ExactProperIntersection exact;

            properIntersectionExactKnownCrossing(
                first,
                second,
                exact
            );

            const auto event =
                exactOverlayPoint(
                    exact
                );

            const bool firstAdded =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    event
                );

            const bool secondAdded =
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    event
                );

            assert(firstAdded);
            assert(secondAdded);

            return true;
        }

        case SegmentContactKind.overlap:
        {
            Segment2!T overlap;

            const bool found =
                trySegmentIntersectionOverlap(
                    first,
                    second,
                    overlap
                );

            assert(found);

            const auto lower =
                exactOverlayPoint(
                    overlap.a
                );

            const auto upper =
                exactOverlayPoint(
                    overlap.b
                );

            bool added =
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    lower
                );

            added =
                added &&
                appendExactEdgeEvent(
                    firstEvents,
                    firstCount,
                    upper
                );

            added =
                added &&
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    lower
                );

            added =
                added &&
                appendExactEdgeEvent(
                    secondEvents,
                    secondCount,
                    upper
                );

            assert(added);

            return true;
        }
    }
}


/*
 * Appends one source-pair event while allowing the first/source segment's
 * exact dyadic coordinates to be prepared lazily and then reused by the
 * caller across many boundary edges.
 *
 * Non-crossing contacts delegate to the established known-contact writer.
 * Only strict proper crossings use the prepared exact-construction path.
 */
bool appendSegmentPairNodingEventsKnownContactPreparedFirst(T)(
    Segment2!T first,
    Segment2!T second,
    SegmentContactKind contact,
    ref PreparedExactSegment preparedFirst,
    ref bool preparedFirstReady,
    scope ExactOverlayPoint[] firstEvents,
    ref size_t firstCount,
    scope ExactOverlayPoint[] secondEvents,
    ref size_t secondCount
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    if (contact != SegmentContactKind.properCrossing)
    {
        return
            appendSegmentPairNodingEventsKnownContact(
                first,
                second,
                contact,
                firstEvents,
                firstCount,
                secondEvents,
                secondCount
            );
    }

    if (
        firstCount >= firstEvents.length ||
        secondCount >= secondEvents.length
    )
    {
        return false;
    }

    if (!preparedFirstReady)
    {
        preparedFirst =
            prepareExactSegment(
                first
            );

        preparedFirstReady = true;
    }

    ExactProperIntersection exact;

    properIntersectionExactKnownCrossingPreparedFirst(
        preparedFirst,
        second,
        exact
    );

    const auto event =
        exactOverlayPoint(
            exact
        );

    const bool firstAdded =
        appendExactEdgeEvent(
            firstEvents,
            firstCount,
            event
        );

    const bool secondAdded =
        appendExactEdgeEvent(
            secondEvents,
            secondCount,
            event
        );

    assert(firstAdded);
    assert(secondAdded);

    return true;
}


bool appendSegmentPairNodingEventsPreparedFirst(T)(
    Segment2!T first,
    Segment2!T second,
    ref PreparedExactSegment preparedFirst,
    ref bool preparedFirstReady,
    scope ExactOverlayPoint[] firstEvents,
    ref size_t firstCount,
    scope ExactOverlayPoint[] secondEvents,
    ref size_t secondCount
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    const SegmentContactKind contact =
        segmentContactKind(
            first,
            second
        );

    return
        appendSegmentPairNodingEventsKnownContactPreparedFirst(
            first,
            second,
            contact,
            preparedFirst,
            preparedFirstReady,
            firstEvents,
            firstCount,
            secondEvents,
            secondCount
        );
}


/*
 * Dense provenance sorts already own rawToUnique scratch storage that is dead
 * until deduplication. During heap ordering, reuse one size_t per event for
 * three packed past-last-nonzero limb ends:
 *
 *     x numerator | y numerator | denominator
 *
 * Each fixed-width carrier currently needs fewer than 256 limbs, so one byte
 * per end is sufficient even on 32-bit targets. The scratch words are
 * overwritten with the normal raw-to-unique mapping immediately after sort.
 */
private enum size_t denseEventEndMask = 0xff;
private enum size_t denseEventYEndShift = 8;
private enum size_t denseEventDenominatorEndShift = 16;

static assert(exactCoordinateNumeratorLimbs <= denseEventEndMask);
static assert(dyadicProductLimbs <= denseEventEndMask);


private size_t pastLastNonZeroLimb(
    scope const(uint)[] limbs
)
    pure nothrow @safe @nogc
{
    size_t end = limbs.length;

    while (end != 0)
    {
        if (limbs[end - 1] != 0)
            return end;

        --end;
    }

    return 0;
}


private size_t packDenseEventEnds(
    ref const ExactOverlayPoint event
)
    pure nothrow @safe @nogc
{
    const size_t xEnd =
        pastLastNonZeroLimb(
            event.xNumerator.magnitude.limb[]
        );

    const size_t yEnd =
        pastLastNonZeroLimb(
            event.yNumerator.magnitude.limb[]
        );

    const size_t denominatorEnd =
        pastLastNonZeroLimb(
            event.denominator.limb[]
        );

    assert(xEnd <= denseEventEndMask);
    assert(yEnd <= denseEventEndMask);
    assert(denominatorEnd != 0);
    assert(denominatorEnd <= denseEventEndMask);

    return
        xEnd |
        (yEnd << denseEventYEndShift) |
        (
            denominatorEnd <<
            denseEventDenominatorEndShift
        );
}


private size_t denseEventXEnd(size_t metadata)
    pure nothrow @safe @nogc
{
    return metadata & denseEventEndMask;
}


private size_t denseEventYEnd(size_t metadata)
    pure nothrow @safe @nogc
{
    return
        (
            metadata >>
            denseEventYEndShift
        ) &
        denseEventEndMask;
}


private size_t denseEventDenominatorEnd(size_t metadata)
    pure nothrow @safe @nogc
{
    return
        (
            metadata >>
            denseEventDenominatorEndShift
        ) &
        denseEventEndMask;
}


private bool equalUnsignedBounded(
    scope const(uint)[] lhs,
    size_t lhsEnd,
    scope const(uint)[] rhs,
    size_t rhsEnd
)
    pure nothrow @safe @nogc
{
    if (lhsEnd != rhsEnd)
        return false;

    foreach (i; 0 .. lhsEnd)
    {
        if (lhs[i] != rhs[i])
            return false;
    }

    return true;
}


private int compareUnsignedBounded(
    scope const(uint)[] lhs,
    size_t lhsEnd,
    scope const(uint)[] rhs,
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

        if (lhs[i] < rhs[i])
            return -1;

        if (lhs[i] > rhs[i])
            return 1;
    }

    return 0;
}


private int compareCanonicalExactCoordinatesEqualPreferredBounded(
    ref const SignedExactCoordinateNumerator lhsNumerator,
    ref const DyadicProductMagnitude lhsDenominator,
    size_t lhsNumeratorEnd,
    size_t lhsDenominatorEnd,
    ref const SignedExactCoordinateNumerator rhsNumerator,
    ref const DyadicProductMagnitude rhsDenominator,
    size_t rhsNumeratorEnd,
    size_t rhsDenominatorEnd
)
    pure nothrow @safe @nogc
{
    assert(!lhsDenominator.isZero);
    assert(!rhsDenominator.isZero);

    const bool equalDenominator =
        equalUnsignedBounded(
            lhsDenominator.limb[],
            lhsDenominatorEnd,
            rhsDenominator.limb[],
            rhsDenominatorEnd
        );

    if (!equalDenominator)
    {
        return
            compareCanonicalExactCoordinatesEqualPreferred(
                lhsNumerator,
                lhsDenominator,
                rhsNumerator,
                rhsDenominator
            );
    }

    const int lhsSign =
        lhsNumerator.sign;

    const int rhsSign =
        rhsNumerator.sign;

    assert(lhsSign >= -1 && lhsSign <= 1);
    assert(rhsSign >= -1 && rhsSign <= 1);

    assert(
        (lhsSign == 0) ==
        lhsNumerator.magnitude.isZero
    );

    assert(
        (rhsSign == 0) ==
        rhsNumerator.magnitude.isZero
    );

    if (lhsSign < rhsSign)
        return -1;

    if (lhsSign > rhsSign)
        return 1;

    if (lhsSign == 0)
        return 0;

    const int magnitudeComparison =
        compareUnsignedBounded(
            lhsNumerator.magnitude.limb[],
            lhsNumeratorEnd,
            rhsNumerator.magnitude.limb[],
            rhsNumeratorEnd
        );

    return
        lhsSign > 0
            ? magnitudeComparison
            : -magnitudeComparison;
}


private int compareExactOverlayPointsAlongSegmentEqualPreferredBounded(T)(
    Segment2!T source,
    ref const ExactOverlayPoint lhs,
    size_t lhsMetadata,
    ref const ExactOverlayPoint rhs,
    size_t rhsMetadata
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);

    int comparison;

    if (source.a.x != source.b.x)
    {
        comparison =
            compareCanonicalExactCoordinatesEqualPreferredBounded(
                lhs.xNumerator,
                lhs.denominator,
                denseEventXEnd(lhsMetadata),
                denseEventDenominatorEnd(lhsMetadata),
                rhs.xNumerator,
                rhs.denominator,
                denseEventXEnd(rhsMetadata),
                denseEventDenominatorEnd(rhsMetadata)
            );

        if (source.a.x > source.b.x)
            comparison = -comparison;
    }
    else
    {
        comparison =
            compareCanonicalExactCoordinatesEqualPreferredBounded(
                lhs.yNumerator,
                lhs.denominator,
                denseEventYEnd(lhsMetadata),
                denseEventDenominatorEnd(lhsMetadata),
                rhs.yNumerator,
                rhs.denominator,
                denseEventYEnd(rhsMetadata),
                denseEventDenominatorEnd(rhsMetadata)
            );

        if (source.a.y > source.b.y)
            comparison = -comparison;
    }

    assert(
        comparison ==
        compareExactOverlayPointsAlongSegmentEqualPreferred(
            source,
            lhs,
            rhs
        )
    );

    return comparison;
}


package(geo) int compareExactOverlayPointsAlongSegmentEqualPreferred(T)(
    Segment2!T source,
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);

    int comparison;

    if (source.a.x != source.b.x)
    {
        comparison =
            compareCanonicalExactCoordinatesEqualPreferred(
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

    comparison =
        compareCanonicalExactCoordinatesEqualPreferred(
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
 * Dense-event heap helper. This is separate from the baseline sift helper so
 * sparse/crossing sorts retain the established develop call path.
 */
private void siftDownExactEdgeEventsEqualPreferred(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
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
            compareExactOverlayPointsAlongSegmentEqualPreferred(
                source,
                events[largest],
                events[right]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const ExactOverlayPoint temporary =
            events[root];

        events[root] =
            events[largest];

        events[largest] =
            temporary;

        root = largest;
    }
}


private void siftDownExactEdgeEventsEqualPreferredWithRawIndices(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    scope size_t[] eventEndMetadata,
    scope size_t[] rawIndices,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(eventEndMetadata.length >= events.length);
    assert(rawIndices.length >= events.length);

    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPointsAlongSegmentEqualPreferredBounded(
                source,
                events[largest],
                eventEndMetadata[largest],
                events[left],
                eventEndMetadata[left]
            ) < 0
        )
        {
            largest = left;
        }

        const size_t right =
            left + 1;

        if (
            right < end &&
            compareExactOverlayPointsAlongSegmentEqualPreferredBounded(
                source,
                events[largest],
                eventEndMetadata[largest],
                events[right],
                eventEndMetadata[right]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const ExactOverlayPoint temporaryEvent =
            events[root];

        events[root] =
            events[largest];

        events[largest] =
            temporaryEvent;

        const size_t temporaryMetadata =
            eventEndMetadata[root];

        eventEndMetadata[root] =
            eventEndMetadata[largest];

        eventEndMetadata[largest] =
            temporaryMetadata;

        const size_t temporaryRawIndex =
            rawIndices[root];

        rawIndices[root] =
            rawIndices[largest];

        rawIndices[largest] =
            temporaryRawIndex;

        root = largest;
    }
}


/*
 * Dense exact-event sort with compact provenance.
 *
 * rawIndices is scratch storage for the raw pre-sort event identity.
 *
 * During heap ordering, rawToUnique temporarily holds packed x/y/denominator
 * active-end metadata aligned with the mutable event slots. Once ordering is
 * complete that metadata is dead, and rawToUnique is overwritten with the
 * final mapping from every raw input slot to its unique event index.
 *
 * Duplicate raw events therefore map to the same unique index without
 * retaining another ExactOverlayPoint carrier or allocating metadata storage.
 */
package(geo)
size_t sortUniqueExactEdgeEventsEqualPreferredWithRawMapping(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    scope size_t[] rawIndices,
    scope size_t[] rawToUnique
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(rawIndices.length >= events.length);
    assert(rawToUnique.length >= events.length);

    if (events.length == 0)
        return 0;

    foreach (i; 0 .. events.length)
    {
        rawIndices[i] = i;

        rawToUnique[i] =
            packDenseEventEnds(
                events[i]
            );
    }

    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;

        siftDownExactEdgeEventsEqualPreferredWithRawIndices(
            source,
            events,
            rawToUnique,
            rawIndices,
            start,
            events.length
        );
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const ExactOverlayPoint temporaryEvent =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporaryEvent;

        const size_t temporaryMetadata =
            rawToUnique[0];

        rawToUnique[0] =
            rawToUnique[end];

        rawToUnique[end] =
            temporaryMetadata;

        const size_t temporaryRawIndex =
            rawIndices[0];

        rawIndices[0] =
            rawIndices[end];

        rawIndices[end] =
            temporaryRawIndex;

        siftDownExactEdgeEventsEqualPreferredWithRawIndices(
            source,
            events,
            rawToUnique,
            rawIndices,
            0,
            end
        );
    }

    size_t write = 1;

    rawToUnique[rawIndices[0]] = 0;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactOverlayPointsEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            if (write != read)
                events[write] = events[read];

            rawToUnique[rawIndices[read]] =
                write;

            ++write;
        }
        else
        {
            rawToUnique[rawIndices[read]] =
                write - 1;
        }
    }

    return write;
}


size_t sortUniqueExactEdgeEventsEqualPreferred(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;

        siftDownExactEdgeEventsEqualPreferred(
            source,
            events,
            start,
            events.length
        );
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const ExactOverlayPoint temporary =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporary;

        siftDownExactEdgeEventsEqualPreferred(
            source,
            events,
            0,
            end
        );
    }

    size_t write = 1;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactOverlayPointsEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            if (write != read)
                events[write] = events[read];

            ++write;
        }
    }

    return write;
}


/*
 * Restores the max-heap property in events[root .. end), using exact
 * source-edge order as the key.
 */
private void siftDownExactEdgeEvents(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    size_t root,
    size_t end
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    while (true)
    {
        const size_t left =
            root * 2 + 1;

        if (left >= end)
            return;

        size_t largest = root;

        if (
            compareExactOverlayPointsAlongSegment(
                source,
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
            compareExactOverlayPointsAlongSegment(
                source,
                events[largest],
                events[right]
            ) < 0
        )
        {
            largest = right;
        }

        if (largest == root)
            return;

        const ExactOverlayPoint temporary =
            events[root];

        events[root] =
            events[largest];

        events[largest] =
            temporary;

        root = largest;
    }
}


/*
 * Sorts exact edge events in source.a -> source.b order and removes exact
 * duplicates in-place.
 *
 * Event-count research showed that 2-4-event sorts are the sparse/crossing
 * regime, while measured dense sorts begin at 9 events. Unobserved 5-8-event
 * sorts conservatively retain this baseline path.
 */
/*
 * Research support for small exact-event provenance.
 *
 * This is the baseline exact comparator path with compact raw-slot identity
 * carried alongside the mutable event slots. It deliberately does not use the
 * dense equal-denominator comparator, so enabling provenance does not change
 * the established 2-8-event sort regime.
 */
package(geo)
size_t sortUniqueExactEdgeEventsWithRawMapping(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events,
    scope size_t[] rawIndices,
    scope size_t[] rawToUnique
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);
    assert(rawIndices.length >= events.length);
    assert(rawToUnique.length >= events.length);

    if (events.length == 0)
        return 0;

    foreach (i; 0 .. events.length)
        rawIndices[i] = i;

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
                compareExactOverlayPointsAlongSegment(
                    source,
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
                compareExactOverlayPointsAlongSegment(
                    source,
                    events[largest],
                    events[right]
                ) < 0
            )
            {
                largest = right;
            }

            if (largest == root)
                break;

            const ExactOverlayPoint temporaryEvent =
                events[root];

            events[root] =
                events[largest];

            events[largest] =
                temporaryEvent;

            const size_t temporaryRawIndex =
                rawIndices[root];

            rawIndices[root] =
                rawIndices[largest];

            rawIndices[largest] =
                temporaryRawIndex;

            root = largest;
        }
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const ExactOverlayPoint temporaryEvent =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporaryEvent;

        const size_t temporaryRawIndex =
            rawIndices[0];

        rawIndices[0] =
            rawIndices[end];

        rawIndices[end] =
            temporaryRawIndex;

        size_t root = 0;

        while (true)
        {
            const size_t left =
                root * 2 + 1;

            if (left >= end)
                break;

            size_t largest = root;

            if (
                compareExactOverlayPointsAlongSegment(
                    source,
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
                compareExactOverlayPointsAlongSegment(
                    source,
                    events[largest],
                    events[right]
                ) < 0
            )
            {
                largest = right;
            }

            if (largest == root)
                break;

            const ExactOverlayPoint siftEvent =
                events[root];

            events[root] =
                events[largest];

            events[largest] =
                siftEvent;

            const size_t siftRawIndex =
                rawIndices[root];

            rawIndices[root] =
                rawIndices[largest];

            rawIndices[largest] =
                siftRawIndex;

            root = largest;
        }
    }

    size_t write = 1;

    rawToUnique[rawIndices[0]] = 0;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactOverlayPointsEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            if (write != read)
                events[write] = events[read];

            rawToUnique[rawIndices[read]] =
                write;

            ++write;
        }
        else
        {
            rawToUnique[rawIndices[read]] =
                write - 1;
        }
    }

    return write;
}


size_t sortUniqueExactEdgeEvents(T)(
    Segment2!T source,
    scope ExactOverlayPoint[] events
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);

    if (events.length < 2)
        return events.length;

    size_t start =
        events.length / 2;

    while (start > 0)
    {
        --start;

        siftDownExactEdgeEvents(
            source,
            events,
            start,
            events.length
        );
    }

    size_t end =
        events.length;

    while (end > 1)
    {
        --end;

        const ExactOverlayPoint temporary =
            events[0];

        events[0] =
            events[end];

        events[end] =
            temporary;

        siftDownExactEdgeEvents(
            source,
            events,
            0,
            end
        );
    }

    size_t write = 1;

    foreach (read; 1 .. events.length)
    {
        if (
            !exactOverlayPointsEqual(
                events[write - 1],
                events[read]
            )
        )
        {
            if (write != read)
                events[write] = events[read];

            ++write;
        }
    }

    return write;
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    /*
     * ExactOverlayPoint producers keep zero numerators canonical. This is the
     * precondition used by the dense canonical comparator; the general exact
     * comparator deliberately retains stale-sign tolerance for other callers.
     */
    {
        const auto representedZero =
            exactOverlayPoint(
                P(0, 0)
            );

        assert(representedZero.xNumerator.sign == 0);
        assert(representedZero.xNumerator.magnitude.isZero);
        assert(representedZero.yNumerator.sign == 0);
        assert(representedZero.yNumerator.magnitude.isZero);

        ExactProperIntersection crossing;

        properIntersectionExactKnownCrossing(
            S(P(-1, -1), P(1, 1)),
            S(P(-1, 1), P(1, -1)),
            crossing
        );

        const auto constructedZero =
            exactOverlayPoint(
                crossing
            );

        assert(constructedZero.xNumerator.sign == 0);
        assert(constructedZero.xNumerator.magnitude.isZero);
        assert(constructedZero.yNumerator.sign == 0);
        assert(constructedZero.yNumerator.magnitude.isZero);
    }



    /*
     * Dense provenance sort preserves exact order and maps duplicate raw
     * slots to one final unique event index.
     */
    {
        const S source =
            S(
                P(0, 0),
                P(10, 0)
            );

        ExactOverlayPoint[4] events = [
            exactOverlayPoint(P(10, 0)),
            exactOverlayPoint(P(5, 0)),
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(5, 0)),
        ];

        size_t[4] rawIndices;
        size_t[4] rawToUnique;

        const size_t count =
            sortUniqueExactEdgeEventsEqualPreferredWithRawMapping(
                source,
                events[],
                rawIndices[],
                rawToUnique[]
            );

        assert(count == 3);

        const auto expected0 =
            exactOverlayPoint(
                P(0, 0)
            );

        const auto expected1 =
            exactOverlayPoint(
                P(5, 0)
            );

        const auto expected2 =
            exactOverlayPoint(
                P(10, 0)
            );

        assert(
            exactOverlayPointsEqual(
                events[0],
                expected0
            )
        );

        assert(
            exactOverlayPointsEqual(
                events[1],
                expected1
            )
        );

        assert(
            exactOverlayPointsEqual(
                events[2],
                expected2
            )
        );

        assert(rawToUnique[0] == 2);
        assert(rawToUnique[1] == 1);
        assert(rawToUnique[2] == 0);
        assert(rawToUnique[3] == 1);
    }




    /*
     * Proper crossing: both edges receive the same exact rational event.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S second =
            S(
                P(5, -5),
                P(5, 5)
            );

        ExactOverlayPoint[4] firstEvents;
        ExactOverlayPoint[4] secondEvents;

        size_t firstCount;
        size_t secondCount;

        assert(
            seedExactEdgeEvents(
                first,
                firstEvents[],
                firstCount
            )
        );

        assert(
            seedExactEdgeEvents(
                second,
                secondEvents[],
                secondCount
            )
        );

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstCount,
                secondEvents[],
                secondCount
            )
        );

        assert(firstCount == 3);
        assert(secondCount == 3);

        firstCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstCount]
            );

        secondCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondCount]
            );

        assert(firstCount == 3);
        assert(secondCount == 3);

        const auto crossing =
            exactOverlayPoint(
                P(5, 0)
            );

        assert(
            exactOverlayPointsEqual(
                firstEvents[1],
                crossing
            )
        );

        assert(
            exactOverlayPointsEqual(
                secondEvents[1],
                crossing
            )
        );
    }


    /*
     * T-junction: the touch is an interior event on the horizontal source
     * and a duplicate endpoint event on the vertical source.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(10, 0)
            );

        const S second =
            S(
                P(5, 0),
                P(5, 5)
            );

        ExactOverlayPoint[4] firstEvents;
        ExactOverlayPoint[4] secondEvents;

        size_t firstCount;
        size_t secondCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondCount));

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstCount,
                secondEvents[],
                secondCount
            )
        );

        firstCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstCount]
            );

        secondCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondCount]
            );

        assert(firstCount == 3);
        assert(secondCount == 2);
    }


    /*
     * Partial collinear overlap: both overlap endpoints are inserted into
     * both source event sets and deduplicated against existing endpoints.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S second =
            S(
                P(2, 0),
                P(6, 0)
            );

        ExactOverlayPoint[6] firstEvents;
        ExactOverlayPoint[6] secondEvents;

        size_t firstCount;
        size_t secondCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondCount));

        assert(
            appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstCount,
                secondEvents[],
                secondCount
            )
        );

        firstCount =
            sortUniqueExactEdgeEvents(
                first,
                firstEvents[0 .. firstCount]
            );

        secondCount =
            sortUniqueExactEdgeEvents(
                second,
                secondEvents[0 .. secondCount]
            );

        assert(firstCount == 3);
        assert(secondCount == 3);

        const auto two =
            exactOverlayPoint(
                P(2, 0)
            );

        const auto four =
            exactOverlayPoint(
                P(4, 0)
            );

        assert(exactOverlayPointsEqual(firstEvents[1], two));
        assert(exactOverlayPointsEqual(firstEvents[2], four));

        assert(exactOverlayPointsEqual(secondEvents[0], two));
        assert(exactOverlayPointsEqual(secondEvents[1], four));
    }


    /*
     * Reversed source storage orders events from the represented source.a
     * toward source.b, not lexicographically.
     */
    {
        const S source =
            S(
                P(10, 0),
                P(0, 0)
            );

        ExactOverlayPoint[5] events = [
            exactOverlayPoint(P(3, 0)),
            exactOverlayPoint(P(10, 0)),
            exactOverlayPoint(P(7, 0)),
            exactOverlayPoint(P(0, 0)),
            exactOverlayPoint(P(7, 0)),
        ];

        const size_t count =
            sortUniqueExactEdgeEvents(
                source,
                events[]
            );

        assert(count == 4);

        const int[4] expected = [
            10,
            7,
            3,
            0,
        ];

        foreach (i; 0 .. count)
        {
            const auto point =
                exactOverlayPoint(
                    P(expected[i], 0)
                );

            assert(
                exactOverlayPointsEqual(
                    events[i],
                    point
                )
            );
        }
    }


    /*
     * Capacity failure is transactional with respect to event counts.
     */
    {
        const S first =
            S(
                P(0, 0),
                P(4, 0)
            );

        const S second =
            S(
                P(2, 0),
                P(6, 0)
            );

        ExactOverlayPoint[3] firstEvents;
        ExactOverlayPoint[3] secondEvents;

        size_t firstCount;
        size_t secondCount;

        assert(seedExactEdgeEvents(first, firstEvents[], firstCount));
        assert(seedExactEdgeEvents(second, secondEvents[], secondCount));

        const size_t beforeFirst =
            firstCount;

        const size_t beforeSecond =
            secondCount;

        assert(
            !appendSegmentPairNodingEvents(
                first,
                second,
                firstEvents[],
                firstCount,
                secondEvents[],
                secondCount
            )
        );

        assert(firstCount == beforeFirst);
        assert(secondCount == beforeSecond);
    }
}


@safe unittest
{
    /*
     * Exact represented-point orientation.
     */
    const auto a =
        exactOverlayPoint(
            Point2!int(0, 0)
        );

    const auto b =
        exactOverlayPoint(
            Point2!int(4, 0)
        );

    const auto c =
        exactOverlayPoint(
            Point2!int(0, 3)
        );

    assert(
        orientationExactOverlayPoints(
            a,
            b,
            c
        ) > 0
    );

    assert(
        orientationExactOverlayPoints(
            a,
            c,
            b
        ) < 0
    );

    const auto collinear =
        exactOverlayPoint(
            Point2!int(2, 0)
        );

    assert(
        orientationExactOverlayPoints(
            a,
            collinear,
            b
        ) == 0
    );
}


@safe unittest
{
    /*
     * A proper intersection at (2/3, 2/3) remains an exact rational input
     * to orientation; no binary64 materialization is involved.
     */
    alias P = Point2!int;
    alias S = Segment2!int;

    const S first =
        S(
            P(0, 0),
            P(2, 2)
        );

    const S second =
        S(
            P(0, 1),
            P(2, 0)
        );

    ExactProperIntersection intersection;

    assert(
        tryProperIntersectionExact(
            first,
            second,
            intersection
        )
    );

    const auto a =
        exactOverlayPoint(
            P(0, 0)
        );

    const auto rational =
        exactOverlayPoint(
            intersection
        );

    const auto c =
        exactOverlayPoint(
            P(0, 1)
        );

    assert(
        orientationExactOverlayPoints(
            a,
            rational,
            c
        ) > 0
    );

    assert(
        orientationExactOverlayPoints(
            a,
            c,
            rational
        ) < 0
    );
}


@safe unittest
{
    /*
     * Represented integral and binary64 points with the same mathematical
     * value receive the same exact overlay identity.
     */
    const integerPoint =
        exactOverlayPoint(
            Point2!int(
                1,
                -2
            )
        );

    const floatingPoint =
        exactOverlayPoint(
            Point2!double(
                1.0,
                -2.0
            )
        );

    assert(
        exactOverlayPointsEqual(
            integerPoint,
            floatingPoint
        )
    );
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const source =
        S(
            P(0, 0),
            P(10, 0)
        );

    const crossing =
        S(
            P(5, -3),
            P(5, 7)
        );

    ExactProperIntersection exact;

    assert(
        tryProperIntersectionExact(
            source,
            crossing,
            exact
        )
    );

    const auto sourceA =
        exactOverlayPoint(
            source.a
        );

    const auto sourceB =
        exactOverlayPoint(
            source.b
        );

    const auto event =
        exactOverlayPoint(
            exact
        );

    const auto representedCrossing =
        exactOverlayPoint(
            P(5, 0)
        );

    assert(
        exactOverlayPointsEqual(
            event,
            representedCrossing
        )
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            sourceA,
            event
        ) < 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            event,
            sourceB
        ) < 0
    );

    const auto reversed =
        S(
            source.b,
            source.a
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            sourceA,
            event
        ) > 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            event,
            sourceB
        ) > 0
    );
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const vertical =
        S(
            P(3, -5),
            P(3, 8)
        );

    const lower =
        exactOverlayPoint(
            P(3, -2)
        );

    const upper =
        exactOverlayPoint(
            P(3, 7)
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            vertical,
            lower,
            upper
        ) < 0
    );

    const reversed =
        S(
            vertical.b,
            vertical.a
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            lower,
            upper
        ) > 0
    );
}


@safe unittest
{
    /*
     * Proper intersections with different raw denominators but the same
     * mathematical point compare equal after promotion to overlay points.
     */
    alias P = Point2!int;
    alias S = Segment2!int;

    const source =
        S(
            P(0, 0),
            P(10, 0)
        );

    const shortCrossing =
        S(
            P(5, -1),
            P(5, 1)
        );

    const longCrossing =
        S(
            P(5, -3),
            P(5, 7)
        );

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

    assert(
        first.denominator.limb !=
        second.denominator.limb
    );

    const auto firstPoint =
        exactOverlayPoint(
            first
        );

    const auto secondPoint =
        exactOverlayPoint(
            second
        );

    assert(
        exactOverlayPointsEqual(
            firstPoint,
            secondPoint
        )
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            firstPoint,
            secondPoint
        ) == 0
    );
}
