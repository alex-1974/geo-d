/*
 * Independent CGAL/EPECK regularized Boolean-set oracle for geo-d Issue #49.
 *
 * Diagnostic research code only. It is not linked by geo-d and introduces no
 * package/runtime dependency.
 */

#include <CGAL/Boolean_set_operations_2.h>
#include <CGAL/Exact_predicates_exact_constructions_kernel.h>
#include <CGAL/Polygon_2.h>
#include <CGAL/Polygon_with_holes_2.h>
#include <CGAL/number_utils.h>

#include <cmath>
#include <cstddef>
#include <iostream>
#include <iterator>
#include <list>
#include <stdexcept>
#include <string>
#include <vector>


using Kernel =
    CGAL::Exact_predicates_exact_constructions_kernel;

using FT =
    Kernel::FT;

using Point =
    Kernel::Point_2;

using Polygon =
    CGAL::Polygon_2<Kernel>;

using PolygonWithHoles =
    CGAL::Polygon_with_holes_2<Kernel>;


enum class Operation
{
    unionSet,
    intersection,
    differenceAB,
    differenceBA,
    symmetricDifference,
};


enum class Location
{
    outside,
    boundary,
    inside,
};


static const char* operationName(
    Operation operation
)
{
    switch (operation)
    {
        case Operation::unionSet:
            return "union";

        case Operation::intersection:
            return "intersection";

        case Operation::differenceAB:
            return "difference_ab";

        case Operation::differenceBA:
            return "difference_ba";

        case Operation::symmetricDifference:
            return "symmetric_difference";
    }

    throw std::logic_error(
        "unreachable operation"
    );
}


static Polygon rectangle(
    int x0,
    int y0,
    int x1,
    int y1,
    bool counterClockwise = true
)
{
    Polygon polygon;

    if (counterClockwise)
    {
        polygon.push_back(Point(x0, y0));
        polygon.push_back(Point(x1, y0));
        polygon.push_back(Point(x1, y1));
        polygon.push_back(Point(x0, y1));
    }
    else
    {
        polygon.push_back(Point(x0, y0));
        polygon.push_back(Point(x0, y1));
        polygon.push_back(Point(x1, y1));
        polygon.push_back(Point(x1, y0));
    }

    return polygon;
}


static PolygonWithHoles withoutHoles(
    Polygon exterior
)
{
    if (
        exterior.orientation() ==
        CGAL::CLOCKWISE
    )
    {
        exterior.reverse_orientation();
    }

    return PolygonWithHoles(
        exterior
    );
}


static PolygonWithHoles withHole(
    Polygon exterior,
    Polygon hole
)
{
    if (
        exterior.orientation() ==
        CGAL::CLOCKWISE
    )
    {
        exterior.reverse_orientation();
    }

    if (
        hole.orientation() ==
        CGAL::COUNTERCLOCKWISE
    )
    {
        hole.reverse_orientation();
    }

    std::vector<Polygon> holes = {
        std::move(hole),
    };

    return PolygonWithHoles(
        exterior,
        holes.begin(),
        holes.end()
    );
}


static FT absoluteArea(
    const Polygon& polygon
)
{
    FT area =
        polygon.area();

    if (area < FT(0))
        area = -area;

    return area;
}


static Location classifyPolygonWithHoles(
    const PolygonWithHoles& polygon,
    const Point& query
)
{
    const auto exteriorSide =
        polygon.outer_boundary()
            .bounded_side(query);

    if (
        exteriorSide ==
        CGAL::ON_BOUNDARY
    )
    {
        return Location::boundary;
    }

    if (
        exteriorSide ==
        CGAL::ON_UNBOUNDED_SIDE
    )
    {
        return Location::outside;
    }

    for (
        auto hole = polygon.holes_begin();
        hole != polygon.holes_end();
        ++hole
    )
    {
        const auto holeSide =
            hole->bounded_side(query);

        if (
            holeSide ==
            CGAL::ON_BOUNDARY
        )
        {
            return Location::boundary;
        }

        if (
            holeSide ==
            CGAL::ON_BOUNDED_SIDE
        )
        {
            return Location::outside;
        }
    }

    return Location::inside;
}


static Location classifySet(
    const std::list<PolygonWithHoles>& result,
    const Point& query
)
{
    bool inside = false;

    for (
        const auto& component :
        result
    )
    {
        const auto location =
            classifyPolygonWithHoles(
                component,
                query
            );

        if (
            location ==
            Location::boundary
        )
        {
            return Location::boundary;
        }

        if (
            location ==
            Location::inside
        )
        {
            inside = true;
        }
    }

    return
        inside
            ? Location::inside
            : Location::outside;
}


static char locationCode(
    Location location
)
{
    switch (location)
    {
        case Location::outside:
            return 'O';

        case Location::boundary:
            return 'B';

        case Location::inside:
            return 'I';
    }

    throw std::logic_error(
        "unreachable location"
    );
}


static std::list<PolygonWithHoles> applyOperation(
    Operation operation,
    const PolygonWithHoles& first,
    const PolygonWithHoles& second
)
{
    std::list<PolygonWithHoles> result;

    switch (operation)
    {
        case Operation::unionSet:
        {
            const std::vector<PolygonWithHoles> input = {
                first,
                second,
            };

            CGAL::join(
                input.begin(),
                input.end(),
                std::back_inserter(result)
            );

            break;
        }

        case Operation::intersection:
            CGAL::intersection(
                first,
                second,
                std::back_inserter(result)
            );
            break;

        case Operation::differenceAB:
            CGAL::difference(
                first,
                second,
                std::back_inserter(result)
            );
            break;

        case Operation::differenceBA:
            CGAL::difference(
                second,
                first,
                std::back_inserter(result)
            );
            break;

        case Operation::symmetricDifference:
            CGAL::symmetric_difference(
                first,
                second,
                std::back_inserter(result)
            );
            break;
    }

    return result;
}


static void emitOperation(
    const std::string& name,
    Operation operation,
    const PolygonWithHoles& first,
    const PolygonWithHoles& second
)
{
    const auto result =
        applyOperation(
            operation,
            first,
            second
        );

    std::size_t holeCount = 0;
    FT area = FT(0);

    for (
        const auto& component :
        result
    )
    {
        area +=
            absoluteArea(
                component.outer_boundary()
            );

        for (
            auto hole = component.holes_begin();
            hole != component.holes_end();
            ++hole
        )
        {
            ++holeCount;

            area -=
                absoluteArea(
                    *hole
                );
        }
    }

    const double area2Double =
        CGAL::to_double(
            area * FT(2)
        );

    const long long area2 =
        std::llround(
            area2Double
        );

    if (
        area2Double !=
        static_cast<double>(
            area2
        )
    )
    {
        throw std::runtime_error(
            "fixture area is not exactly integral"
        );
    }

    std::cout
        << name
        << "|op="
        << operationName(operation)
        << "|cgal_polygons_with_holes="
        << result.size()
        << "|holes="
        << holeCount
        << "|area2="
        << area2
        << "|grid=";

    for (
        int y = -2;
        y < 13;
        ++y
    )
    {
        for (
            int x = -1;
            x < 16;
            ++x
        )
        {
            std::cout
                << locationCode(
                    classifySet(
                        result,
                        Point(x, y)
                    )
                );
        }
    }

    std::cout << '\n';
}


static void emitCase(
    const std::string& name,
    const PolygonWithHoles& first,
    const PolygonWithHoles& second
)
{
    const Operation operations[] = {
        Operation::unionSet,
        Operation::intersection,
        Operation::differenceAB,
        Operation::differenceBA,
        Operation::symmetricDifference,
    };

    for (
        const auto operation :
        operations
    )
    {
        emitOperation(
            name,
            operation,
            first,
            second
        );
    }
}


int main()
{
    emitCase(
        "disjoint",
        withoutHoles(
            rectangle(0, 0, 4, 4)
        ),
        withoutHoles(
            rectangle(10, 0, 14, 4)
        )
    );

    emitCase(
        "overlap",
        withoutHoles(
            rectangle(0, 0, 4, 4)
        ),
        withoutHoles(
            rectangle(2, -1, 6, 3)
        )
    );

    emitCase(
        "containment",
        withoutHoles(
            rectangle(0, 0, 10, 10)
        ),
        withoutHoles(
            rectangle(2, 2, 4, 4)
        )
    );

    emitCase(
        "identical",
        withoutHoles(
            rectangle(0, 0, 5, 5)
        ),
        withoutHoles(
            rectangle(0, 0, 5, 5)
        )
    );

    emitCase(
        "adjacent",
        withoutHoles(
            rectangle(0, 0, 4, 2)
        ),
        withoutHoles(
            rectangle(4, 0, 8, 2)
        )
    );

    emitCase(
        "point_touch",
        withoutHoles(
            rectangle(0, 0, 2, 2)
        ),
        withoutHoles(
            rectangle(2, 2, 4, 4)
        )
    );

    emitCase(
        "donut_fill",
        withHole(
            rectangle(0, 0, 10, 10),
            rectangle(
                3,
                3,
                7,
                7,
                false
            )
        ),
        withoutHoles(
            rectangle(3, 3, 7, 7)
        )
    );

    emitCase(
        "donut_island",
        withHole(
            rectangle(0, 0, 10, 10),
            rectangle(
                2,
                2,
                8,
                8,
                false
            )
        ),
        withoutHoles(
            rectangle(4, 4, 6, 6)
        )
    );

    emitCase(
        "plus",
        withoutHoles(
            rectangle(0, 3, 10, 5)
        ),
        withoutHoles(
            rectangle(4, 0, 6, 8)
        )
    );

    return 0;
}
