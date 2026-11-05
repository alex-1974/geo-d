/**
 * Robust reduced polygon-to-polygon topological relationship classification.
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
 *     September 30, 2026
 */
module geo.polygon_relationship;

import core.exception :
    onOutOfMemoryError;

import geo.internal.polygon_pair_topology :
    PolygonPairTopologyStatus;

import geo.internal.polygon_relationship_reducer :
    PolygonRelationshipFactsInternal,
    tryClassifyPolygonRelationshipInternal;

import geo.polygon_view :
    Polygon2View;


/**
 * Existential topological facts describing the relationship of two polygons.
 *
 * The facts intentionally form a smaller contract than DE-9IM. They preserve
 * only the information needed by qualified consumers; they do not expose
 * contact counts, ordering, coordinates, component identity, ring identity,
 * or constructed intersection geometry.
 *
 * `hasFirstOnlyInterior` is true exactly when some two-dimensional region is
 * inside `first` and outside `second`.
 *
 * `hasSecondOnlyInterior` is the symmetric fact for `second`.
 *
 * `hasSharedInterior` is true exactly when some two-dimensional region lies
 * inside both polygons.
 *
 * `hasBoundaryContact` is true exactly when the two polygon boundaries share
 * at least one point.
 *
 * `hasBoundaryOverlap` is true exactly when the boundaries share a
 * positive-length subset. Therefore boundary overlap implies boundary contact.
 */
struct PolygonRelationship
{
    bool hasFirstOnlyInterior;

    bool hasSecondOnlyInterior;

    bool hasSharedInterior;

    bool hasBoundaryContact;

    bool hasBoundaryOverlap;
}


/**
 * Outcome of checked polygon-relationship classification.
 *
 * `PolygonRelationshipStatus.init` is `notComputed`. This keeps the default
 * result distinct from a successfully classified relationship whose five
 * facts are all false, such as empty polygon versus empty polygon.
 *
 * Runtime allocation/resource exhaustion is not represented by this enum.
 */
enum PolygonRelationshipStatus : ubyte
{
    /// No polygon-relationship operation has produced this result.
    notComputed,

    /// Relationship classification completed successfully.
    success,

    /// The first input does not satisfy the polygon-validation contract.
    invalidFirstInput,

    /// The second input does not satisfy the polygon-validation contract.
    invalidSecondInput,
}


/**
 * Checked result of polygon-to-polygon relationship classification.
 *
 * `PolygonRelationshipResult.init` has status
 * `PolygonRelationshipStatus.notComputed`.
 *
 * Inspect `status` or `succeeded` before accessing `relationship`.
 */
struct PolygonRelationshipResult
{
private:
    PolygonRelationshipStatus _status =
        PolygonRelationshipStatus.notComputed;

    PolygonRelationship _relationship;

public:
    /// Checked classification outcome.
    @property PolygonRelationshipStatus status() const
        pure nothrow @safe @nogc
    {
        return _status;
    }


    /// True exactly when relationship classification completed successfully.
    @property bool succeeded() const
        pure nothrow @safe @nogc
    {
        return
            _status ==
            PolygonRelationshipStatus.success;
    }


    /**
     * Classified relationship facts.
     *
     * The result must have `succeeded == true`.
     */
    @property PolygonRelationship relationship() const
        pure nothrow @safe @nogc
    {
        assert(succeeded);

        return _relationship;
    }
}


private enum bool isPolygonRelationshipScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/**
 * Classifies the reduced exact topological relationship of two polygons.
 *
 * Both inputs are validated. Invalid geometry is reported through
 * `PolygonRelationshipStatus.invalidFirstInput` or
 * `PolygonRelationshipStatus.invalidSecondInput`; it is never repaired
 * implicitly. When both operands are invalid, the first operand is reported
 * first.
 *
 * Supported scalar domains are `int`, `long`, `float`, and `double`.
 *
 * Empty polygons are valid. Empty versus empty succeeds with all five
 * relationship facts false. Empty versus a non-empty polygon reports only
 * `hasSecondOnlyInterior`; the reversed operand order reports only
 * `hasFirstOnlyInterior`.
 *
 * Classification reuses the exact noding, arrangement, operand provenance,
 * half-edge embedding, and A/B side-label machinery shared with polygon union.
 * It reduces that exact topology directly and does not construct union
 * boundaries, components, or rounded/materialized result coordinates.
 *
 * The operation may allocate variable-size temporary topology workspace and
 * is deliberately not `@nogc`. Allocation/resource exhaustion follows normal
 * D runtime failure semantics and is not a geometric relationship status.
 *
 * The current correctness-first implementation has a conservative documented
 * worst-case upper bound of O(n^4) time or better in the total input
 * boundary-edge count. This is an implementation bound, not a promise that
 * future implementations retain that complexity.
 *
 * Swapping `first` and `second` exchanges only
 * `hasFirstOnlyInterior` and `hasSecondOnlyInterior`. The shared-interior,
 * boundary-contact, and boundary-overlap facts are symmetric.
 *
 * Params:
 *     first = first polygon operand
 *     second = second polygon operand
 *
 * Returns:
 *     A checked relationship-classification result.
 */
PolygonRelationshipResult classifyPolygonRelationship(T)(
    scope Polygon2View!T first,
    scope Polygon2View!T second
)
    @safe
if (isPolygonRelationshipScalar!T)
{
    PolygonRelationshipFactsInternal internalFacts;

    const internalStatus =
        tryClassifyPolygonRelationshipInternal(
            first,
            second,
            internalFacts
        );

    PolygonRelationshipResult result;

    final switch (internalStatus)
    {
        case PolygonPairTopologyStatus.success:
            result._status =
                PolygonRelationshipStatus.success;

            result._relationship =
                PolygonRelationship(
                    internalFacts.hasFirstOnlyInterior,
                    internalFacts.hasSecondOnlyInterior,
                    internalFacts.hasSharedInterior,
                    internalFacts.hasBoundaryContact,
                    internalFacts.hasBoundaryOverlap
                );

            return result;

        case PolygonPairTopologyStatus.invalidFirstInput:
            result._status =
                PolygonRelationshipStatus.invalidFirstInput;

            return result;

        case PolygonPairTopologyStatus.invalidSecondInput:
            result._status =
                PolygonRelationshipStatus.invalidSecondInput;

            return result;

        case PolygonPairTopologyStatus.resourceLimit:
            /*
             * Impossible workspace cardinality is a resource failure, not a
             * geometric relationship alternative.
             */
            onOutOfMemoryError();

        case PolygonPairTopologyStatus.internalInvariantFailure:
            /*
             * Valid inputs reaching inconsistent shared exact topology signal
             * an implementation defect, never a consumer-visible geometry
             * status.
             */
            assert(
                0,
                "internal polygon-relationship invariant failure"
            );
    }
}


/// Example classifying two adjacent polygons through the public root API.
@safe unittest
{
    import geo;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;

    P[4] firstPoints = [
        P(0, 0),
        P(2, 0),
        P(2, 2),
        P(0, 2),
    ];

    P[4] secondPoints = [
        P(2, 0),
        P(4, 0),
        P(4, 2),
        P(2, 2),
    ];

    R[1] firstRings = [
        R(firstPoints[])
    ];

    R[1] secondRings = [
        R(secondPoints[])
    ];

    const first =
        G(firstRings[]);

    const second =
        G(secondRings[]);

    const result =
        classifyPolygonRelationship(
            first: first,
            second: second
        );

    assert(result.succeeded);

    const relationship =
        result.relationship;

    assert(relationship.hasFirstOnlyInterior);
    assert(relationship.hasSecondOnlyInterior);
    assert(!relationship.hasSharedInterior);
    assert(relationship.hasBoundaryContact);
    assert(relationship.hasBoundaryOverlap);


    /*
     * The same public operation supports UFCS with the first polygon as the
     * receiver.
     */
    const ufcsResult =
        first.classifyPolygonRelationship(
            second
        );

    assert(
        ufcsResult.relationship ==
        relationship
    );
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;


    /*
     * Default result and successfully computed all-false relationship are
     * deliberately distinct.
     */
    {
        const initial =
            PolygonRelationshipResult.init;

        assert(
            initial.status ==
            PolygonRelationshipStatus.notComputed
        );

        assert(!initial.succeeded);
    }


    {
        LinearRing2View!int[] noRings;

        const empty =
            Polygon2View!int(noRings);

        const result =
            classifyPolygonRelationship(
                empty,
                empty
            );

        assert(result.succeeded);

        assert(
            result.status ==
            PolygonRelationshipStatus.success
        );

        assert(
            result.relationship ==
            PolygonRelationship.init
        );
    }
}


@safe unittest
{
    import geo.linear_ring_view :
        LinearRing2View;

    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;


    /*
     * Checked validation failure preserves operand identity and first-input
     * precedence.
     */
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

    const invalid =
        G(invalidRings[]);

    const valid =
        G(validRings[]);

    const firstInvalid =
        classifyPolygonRelationship(
            invalid,
            valid
        );

    assert(!firstInvalid.succeeded);

    assert(
        firstInvalid.status ==
        PolygonRelationshipStatus.invalidFirstInput
    );


    const secondInvalid =
        classifyPolygonRelationship(
            valid,
            invalid
        );

    assert(!secondInvalid.succeeded);

    assert(
        secondInvalid.status ==
        PolygonRelationshipStatus.invalidSecondInput
    );


    const bothInvalid =
        classifyPolygonRelationship(
            invalid,
            invalid
        );

    assert(
        bothInvalid.status ==
        PolygonRelationshipStatus.invalidFirstInput
    );
}
