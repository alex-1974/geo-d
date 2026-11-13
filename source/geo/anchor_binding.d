/** Shared source/target anchor descriptors for geometry registration. */
module geo.anchor_binding;

import geo.measure : Angle, Length;
import geo.placement : ScalePolicy2;
import geo.placement : Placement2;
import geo.metric : MetricScalar;
import geo.point : Point2;
import geo.scalar : isGeoScalar;

enum AnchorKind2 : ubyte
{
    vertex,
    edge
}

struct Anchor2(T)
if (isGeoScalar!T)
{
    AnchorKind2 kind;
    size_t startVertex;
    size_t endVertex;
    Point2!T point;
    Angle!T angle;
    Length!T length;

    static Anchor2 vertex(size_t index, Point2!T point)
        pure nothrow @safe @nogc
    {
        Anchor2 result;
        result.kind = AnchorKind2.vertex;
        result.startVertex = index;
        result.point = point;
        return result;
    }

    static Anchor2 edge(size_t startVertex, size_t endVertex,
                        Length!T length, Angle!T angle)
        pure nothrow @safe @nogc
    {
        Anchor2 result;
        result.kind = AnchorKind2.edge;
        result.startVertex = startVertex;
        result.endVertex = endVertex;
        result.length = length;
        result.angle = angle;
        return result;
    }
}

struct AnchorBinding2(T)
if (isGeoScalar!T)
{
    Anchor2!T source;
    Anchor2!T target;
    ScalePolicy2 scalePolicy;

    this(Anchor2!T source, Anchor2!T target,
         ScalePolicy2 scalePolicy = ScalePolicy2.exact)
        pure nothrow @safe @nogc
    {
        this.source = source;
        this.target = target;
        this.scalePolicy = scalePolicy;
    }
}

@safe unittest
{
    import geo;
    import geo.polygon : polygonSourceEdge = sourceEdge,
                         polygonTargetEdge = targetEdge;
    alias T = double;
    auto first = bind(
        sourceVertex(1, Point2!T(0, 0)),
        targetVertex(3, Point2!T(10, 20)));
    auto second = bind(
        sourceVertex(2, Point2!T(2, 0)),
        targetVertex(4, Point2!T(10, 23)));
    Placement2!T placement;
    assert(tryResolve(first, second, placement));
    assert(placement.scale == 1);

    auto scaled = bind(
        sourceVertex(1, Point2!T(0, 0)),
        targetVertex(3, Point2!T(10, 20)),
        ScalePolicy2.uniform);
    auto scaledSecond = bind(
        sourceVertex(2, Point2!T(2, 0)),
        targetVertex(4, Point2!T(10, 24)),
        ScalePolicy2.uniform);
    assert(tryResolve(scaled, scaledSecond, placement));
    assert(placement.scale == 2);
}

@safe unittest
{
    import geo;
    import geo.polygon : polygonSourceEdge = sourceEdge,
                         polygonTargetEdge = targetEdge;
    alias T = double;
    alias P = Point2!T;
    auto source = Polygon2!T([P(0, 0), P(2, 0), P(2, 2), P(0, 2)]);
    auto target = Polygon2!T([P(10, 20), P(10, 23), P(7, 23), P(7, 20)]);

    auto binding = bind(
        polygonSourceEdge(source, 1),
        polygonTargetEdge(target, 1),
        ScalePolicy2.uniform
    );
    auto attached = source.attachTo(binding);
    assert(!attached.empty);
    assert(attached.vertexCount == 4);
    assert(attached.vertex(1) == P(10, 20));
    assert(attached.vertex(2) == P(10, 23));
}

Anchor2!T sourceVertex(T)(size_t index, Point2!T point)
    if (isGeoScalar!T)
{
    return Anchor2!T.vertex(index, point);
}

Anchor2!T targetVertex(T)(size_t index, Point2!T point)
    if (isGeoScalar!T)
{
    return Anchor2!T.vertex(index, point);
}

Anchor2!T sourceEdge(T)(size_t startVertex, size_t endVertex,
                        Point2!T startPoint, Length!T length,
                        Angle!T angle)
    if (isGeoScalar!T)
{
    auto result = Anchor2!T.edge(startVertex, endVertex, length, angle);
    result.point = startPoint;
    return result;
}

Anchor2!T targetEdge(T)(size_t startVertex, size_t endVertex,
                        Point2!T startPoint, Length!T length,
                        Angle!T angle)
    if (isGeoScalar!T)
{
    auto result = Anchor2!T.edge(startVertex, endVertex, length, angle);
    result.point = startPoint;
    return result;
}

AnchorBinding2!T bind(T)(Anchor2!T source, Anchor2!T target,
                         ScalePolicy2 policy = ScalePolicy2.exact)
    if (isGeoScalar!T)
{
    return AnchorBinding2!T(source, target, policy);
}

/** Resolve a binding into a coordinate placement when enough anchors exist. */
bool tryResolve(T)(AnchorBinding2!T binding, out Placement2!T placement)
    pure nothrow @safe
    if (isGeoScalar!T)
{
    // One vertex correspondence contains no direction information.
    if (binding.source.kind == AnchorKind2.vertex &&
        binding.target.kind == AnchorKind2.vertex)
    {
        placement = Placement2!T.init;
        return false;
    }

    if (binding.source.kind == AnchorKind2.edge &&
        binding.target.kind == AnchorKind2.edge)
    {
        if (binding.source.length.value == 0 ||
            binding.target.length.value == 0)
        {
            placement = Placement2!T.init;
            return false;
        }
        const bool scaled = binding.scalePolicy == ScalePolicy2.uniform;
        if (scaled)
        {
            import std.math.trigonometry : cos, sin;
            alias R = MetricScalar!T;
            const T sourceDx = cast(T)(R(binding.source.length.value) *
                cos(R(binding.source.angle.radians)));
            const T sourceDy = cast(T)(R(binding.source.length.value) *
                sin(R(binding.source.angle.radians)));
            const T targetDx = cast(T)(R(binding.target.length.value) *
                cos(R(binding.target.angle.radians)));
            const T targetDy = cast(T)(R(binding.target.length.value) *
                sin(R(binding.target.angle.radians)));
            return Placement2!T.tryFromVerticesScaled(
                binding.source.point, binding.target.point,
                Point2!T(binding.source.point.x + sourceDx,
                         binding.source.point.y + sourceDy),
                Point2!T(binding.target.point.x + targetDx,
                         binding.target.point.y + targetDy),
                placement);
        }
        if (binding.source.length.value != binding.target.length.value)
        {
            placement = Placement2!T.init;
            return false;
        }
        import std.math.trigonometry : cos, sin;
        alias R = MetricScalar!T;
        const T lx = cast(T)(R(binding.source.length.value) *
            cos(R(binding.source.angle.radians)));
        const T ly = cast(T)(R(binding.source.length.value) *
            sin(R(binding.source.angle.radians)));
        return Placement2!T.tryFromVertexAndEdge(
            binding.source.point, binding.target.point,
            binding.source.point,
            Point2!T(binding.source.point.x + lx,
                     binding.source.point.y + ly),
            binding.target.angle, placement);
    }

    placement = Placement2!T.init;
    return false;
}

/** Resolve two vertex-to-vertex bindings into one placement. */
bool tryResolve(T)(AnchorBinding2!T first,
                   AnchorBinding2!T second,
                   out Placement2!T placement)
    pure nothrow @safe
    if (isGeoScalar!T)
{
    if (first.source.kind != AnchorKind2.vertex ||
        first.target.kind != AnchorKind2.vertex ||
        second.source.kind != AnchorKind2.vertex ||
        second.target.kind != AnchorKind2.vertex)
    {
        placement = Placement2!T.init;
        return false;
    }
    if (first.scalePolicy == ScalePolicy2.uniform ||
        second.scalePolicy == ScalePolicy2.uniform)
        return Placement2!T.tryFromVerticesScaled(
            first.source.point, first.target.point,
            second.source.point, second.target.point, placement);
    return Placement2!T.tryFromVertices(
        first.source.point, first.target.point,
        second.source.point, second.target.point, placement);
}

