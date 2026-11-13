/**
 * Results and statuses for shape construction.
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
 *     November 13, 2026
 */
module geo.shape_result;

/** Stable categories for checked intrinsic-shape construction. */
enum ShapeConstructionStatus : ubyte
{
    success,
    nonFinite,
    nonPositive,
    degenerate,
    inconsistent,
    ambiguous
}

struct ShapeConstructionResult(Shape)
{
    Shape value;
    ShapeConstructionStatus status = ShapeConstructionStatus.success;

    @property bool valid() const pure nothrow @safe @nogc
    { return status == ShapeConstructionStatus.success; }

    static ShapeConstructionResult success(Shape value)
        pure nothrow @safe @nogc
    {
        ShapeConstructionResult result;
        result.value = value;
        result.status = ShapeConstructionStatus.success;
        return result;
    }

    static ShapeConstructionResult failure(ShapeConstructionStatus status)
        pure nothrow @safe @nogc
    {
        ShapeConstructionResult result;
        result.value = Shape.init;
        result.status = status;
        return result;
    }
}

