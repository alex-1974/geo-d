/** Shared source/target anchor descriptors for geometry registration. */
module geo.anchor_binding;

import geo.measure : Angle, Length;
import geo.placement : ScalePolicy2;
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

