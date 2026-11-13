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
    { return ShapeConstructionResult(value, ShapeConstructionStatus.success); }

    static ShapeConstructionResult failure(ShapeConstructionStatus status)
        pure nothrow @safe @nogc
    { return ShapeConstructionResult(Shape.init, status); }
}

