/**
 * Robust regularized polygon-union construction with immutable owning results.
 *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 *
 * Date:
 *     September 27, 2026
 */
module geo.polygon_union;

import core.exception :
    onOutOfMemoryError;

import geo.intersection :
    IntersectionScalar;

import geo.internal.polygon_union_p1 :
    PolygonUnionP1InternalStatus,
    tryPolygonUnionP1Internal;

import geo.internal.polygon_union_result :
    PolygonUnionOwnedResultInternal;

import geo.polygon_view :
    Polygon2View;


/**
 * Outcome of a checked polygon-union construction.
 *
 * `PolygonUnionStatus.init` is `notComputed`. This keeps the default state
 * distinct from both successful empty output and every checked failure.
 *
 * Runtime allocation/resource exhaustion is not represented by this enum.
 */
enum PolygonUnionStatus : ubyte
{
    /// No polygon-union operation has produced this result.
    notComputed,

    /// A complete canonical union result was constructed.
    success,

    /// The first input does not satisfy the polygon-validation contract.
    invalidFirstInput,

    /// The second input does not satisfy the polygon-validation contract.
    invalidSecondInput,

    /**
     * The exact union exists, but the public construction scalar cannot
     * represent its required topology faithfully.
     */
    unrepresentableConstruction,
}


/**
 * Immutable owning result of polygon-union construction.
 *
 * Successful results contain zero or more canonical polygon components.
 * Component coordinates use the established construction scalar, currently
 * `double` for every supported polygon-union input scalar.
 *
 * Ordinary copies are shallow descriptor copies. They share immutable
 * GC-backed geometry storage and do not deep-copy point data.
 *
 * Component access returns read-only `Polygon2View!double` descriptors backed
 * by the immutable storage kept alive by the returned views themselves.
 *
 * Geometry access requires `succeeded == true`. Check `status` or
 * `succeeded` before inspecting `length`, `empty`, or indexing the result.
 *
 * `PolygonUnionResult.init` has status `PolygonUnionStatus.notComputed`.
 */
struct PolygonUnionResult
{
private:
    PolygonUnionStatus _status =
        PolygonUnionStatus.notComputed;

    PolygonUnionOwnedResultInternal _owned;

public:
    /// Checked construction outcome.
    @property PolygonUnionStatus status() const
        pure nothrow @safe @nogc
    {
        return _status;
    }


    /// True exactly when a complete polygon union was constructed.
    @property bool succeeded() const
        pure nothrow @safe @nogc
    {
        return _status ==
            PolygonUnionStatus.success;
    }


    /**
     * Number of polygon components in a successful result.
     *
     * The result must have `succeeded == true`.
     */
    @property size_t length() const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned.componentCount;
    }


    /**
     * True when a successful union contains no polygon components.
     *
     * The result must have `succeeded == true`.
     */
    @property bool empty() const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned.componentCount == 0;
    }


    /**
     * Returns one canonical polygon component as a read-only view.
     *
     * The result must have `succeeded == true`.
     * Invalid component indices retain normal D bounds/assert semantics.
     */
    Polygon2View!double opIndex(size_t index) const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _owned.component(index);
    }
}


private enum bool isPolygonUnionScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/**
 * Constructs the regularized two-dimensional union of two polygons.
 *
 * Both inputs are validated. Invalid geometry is reported through
 * `PolygonUnionStatus.invalidFirstInput` or
 * `PolygonUnionStatus.invalidSecondInput`; it is never repaired implicitly.
 * When both operands are invalid, the first operand is reported first.
 *
 * Supported input scalar domains are `int`, `long`, `float`, and
 * `double`. Robust `real` support remains outside this contract.
 *
 * Constructed coordinates follow the existing `IntersectionScalar!T`
 * construction policy and are currently `double` for every supported input
 * scalar.
 *
 * Exact topology remains authoritative until the selected result boundary is
 * materialized. If binary64 materialization cannot preserve the required
 * exact result topology, the returned status is
 * `PolygonUnionStatus.unrepresentableConstruction` and no partial geometry is
 * exposed.
 *
 * The operation allocates variable-size workspace and immutable result
 * storage. It is deliberately not `@nogc`. Allocation/resource exhaustion
 * follows normal D runtime failure semantics and is not a polygon-union
 * geometry status.
 *
 * The current implementation is the correctness-first exact-overlay baseline.
 * Its worst-case time may reach O(n^4) in the total input boundary-edge count
 * because output-topology verification is itself quadratic. This is a
 * baseline implementation bound, not a promise that future implementations
 * retain that complexity.
 *
 * Params:
 *     first = first polygon operand
 *     second = second polygon operand
 *
 * Returns:
 *     A checked immutable owning result.
 */
PolygonUnionResult polygonUnion(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second
)
    @safe
if (isPolygonUnionScalar!T)
{
    /*
     * The public owning result is deliberately non-templated because the
     * accepted construction policy maps every currently supported input
     * scalar to the same binary64 output domain. Fail compilation here if that
     * policy changes instead of silently drifting the result contract.
     */
    static assert(
        is(
            IntersectionScalar!T ==
            double
        )
    );

    PolygonUnionOwnedResultInternal owned;

    const internalStatus =
        tryPolygonUnionP1Internal(
            first,
            second,
            owned
        );

    PolygonUnionResult result;

    final switch (internalStatus)
    {
        case PolygonUnionP1InternalStatus.success:
            result._status =
                PolygonUnionStatus.success;

            result._owned =
                owned;

            return result;

        case PolygonUnionP1InternalStatus.invalidFirstInput:
            result._status =
                PolygonUnionStatus.invalidFirstInput;

            return result;

        case PolygonUnionP1InternalStatus.invalidSecondInput:
            result._status =
                PolygonUnionStatus.invalidSecondInput;

            return result;

        case PolygonUnionP1InternalStatus.unrepresentableConstruction:
            result._status =
                PolygonUnionStatus.unrepresentableConstruction;

            return result;

        case PolygonUnionP1InternalStatus.resourceLimit:
            /*
             * An impossible-to-size workspace is a resource failure rather
             * than a geometric result alternative.
             */
            onOutOfMemoryError();

        case PolygonUnionP1InternalStatus.internalInvariantFailure:
            /*
             * A valid input reaching an inconsistent exact arrangement is an
             * implementation defect, never a consumer-visible geometry
             * status. Literal-false assert is retained in release builds.
             */
            assert(
                0,
                "internal polygon-union invariant failure"
            );
    }
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;


    /*
     * The default result is deliberately not a successful empty union.
     */
    {
        const result =
            PolygonUnionResult.init;

        assert(
            result.status ==
            PolygonUnionStatus.notComputed
        );

        assert(!result.succeeded);
    }


    /*
     * Empty union empty is a successful empty polygon set.
     */
    {
        LinearRing2View!int[] rings;

        const empty =
            Polygon2View!int(rings);

        const result =
            polygonUnion(
                first: empty,
                second: empty
            );

        assert(result.succeeded);

        assert(
            result.status ==
            PolygonUnionStatus.success
        );

        assert(result.empty);
        assert(result.length == 0);
    }


    /*
     * A valid polygon union empty yields one canonical component.
     */
    {
        alias P = Point2!int;
        alias R = LinearRing2View!int;
        alias G = Polygon2View!int;

        P[4] points = [
            P(0, 0),
            P(4, 0),
            P(4, 4),
            P(0, 4),
        ];

        R[1] rings = [
            R(points[])
        ];

        R[] emptyRings;

        const result =
            polygonUnion(
                first: G(rings[]),
                second: G(emptyRings)
            );

        assert(result.succeeded);
        assert(result.length == 1);
        assert(!result.empty);

        const component =
            result[0];

        assert(component.length == 1);
        assert(component.holeCount == 0);
        assert(component.exterior.length == 4);
    }


    /*
     * Validation failure identifies the failing operand.
     */
    {
        alias P = Point2!int;
        alias R = LinearRing2View!int;
        alias G = Polygon2View!int;

        P[4] invalidPoints = [
            P(0, 0),
            P(4, 4),
            P(0, 4),
            P(4, 0),
        ];

        P[4] validPoints = [
            P(10, 0),
            P(14, 0),
            P(14, 4),
            P(10, 4),
        ];

        R[1] invalidRings = [
            R(invalidPoints[])
        ];

        R[1] validRings = [
            R(validPoints[])
        ];

        const result =
            polygonUnion(
                G(invalidRings[]),
                G(validRings[])
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            PolygonUnionStatus.invalidFirstInput
        );
    }


    /*
     * Exact topology that collapses in binary64 is a checked construction
     * failure, not a successful empty result.
     */
    {
        alias P = Point2!long;
        alias R = LinearRing2View!long;
        alias G = Polygon2View!long;

        P[4] points = [
            P(long.max - 1, 0),
            P(long.max, 0),
            P(long.max, 10),
            P(long.max - 1, 10),
        ];

        R[1] rings = [
            R(points[])
        ];

        R[] emptyRings;

        const result =
            polygonUnion(
                G(rings[]),
                G(emptyRings)
            );

        assert(!result.succeeded);

        assert(
            result.status ==
            PolygonUnionStatus
                .unrepresentableConstruction
        );
    }


    /*
     * Ordinary result copies share immutable backing while a component view
     * remains valid after the original owner descriptor is reset.
     */
    {
        alias P = Point2!int;
        alias R = LinearRing2View!int;
        alias G = Polygon2View!int;

        P[4] points = [
            P(0, 0),
            P(2, 0),
            P(2, 2),
            P(0, 2),
        ];

        R[1] rings = [
            R(points[])
        ];

        R[] emptyRings;

        auto original =
            polygonUnion(
                G(rings[]),
                G(emptyRings)
            );

        auto copy =
            original;

        const retained =
            original[0];

        original =
            PolygonUnionResult.init;

        assert(copy.succeeded);
        assert(copy.length == 1);
        assert(retained.exterior.length == 4);

        assert(
            retained.exterior[0] ==
            Point2!double(0.0, 0.0)
        );
    }
}
