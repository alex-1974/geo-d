# 3D-Shape-Familie für geo3

Diese Spezifikation überträgt die geo-d-Nomenklatur auf dreidimensionale
Shapes. Die Implementierung gehört in geo3, nicht in geo-d.

## Nomenklatur

Eine geschlossene Grundfläche wird gegen den Uhrzeigersinn betrachtet. Bei
geschichteten Körpern gilt:

~~~text
A, B, C, D = Grundfläche
E, F, G, H = parallele Deckfläche
E über A, F über B, G über C, H über D
~~~

Kanten werden über ihre Endvertices benannt: AB, BC, CD, DA, AE, BF, CG, DH.

View-abhängige Namen wie topLeftFront sind nicht Teil der normativen API.

## Primitive Körper

| Shape | Intrinsische Parameter | Konstruktionsfamilien |
| --- | --- | --- |
| Point3 | keine intrinsischen Maße | Koordinate |
| Line3 | Richtung | Punkt+Richtung, zwei Punkte |
| Plane3 | Normale | drei Punkte, Punkt+Normale |
| Segment3 | Länge | Länge, zwei Endpunkte |

## Polyeder

| Shape | Primäre Parameter | Interne Repräsentation |
| --- | --- | --- |
| Tetrahedron3 | sechs Kanten | Kanten + Constraints |
| Cuboid3 | AB, BC, AE | drei Kantenlängen |
| Cube3 | eine Kantenlänge | eine Kantenlänge |
| Prism3 | Grundpolygon + Höhe | Grundshape + Extrusion |
| Pyramid3 | Grundpolygon + Höhe | Grundshape + Apex-Höhe |
| Frustum3 | zwei ähnliche Grundflächen + Höhe | Grundflächen + Höhe |
| RegularPolyhedron3 | Typ + eine Größe | Typ + Kantenlänge |

## Rotationskörper

| Shape | Intrinsische Parameter |
| --- | --- |
| Sphere3 | Radius |
| Ellipsoid3 | Halbachsen x, y, z |
| Cylinder3 | Radius + Höhe |
| Cone3 | Radius + Höhe oder Mantellinie |
| TruncatedCone3 | zwei Radien + Höhe |
| Torus3 | Hauptradius + Rohrradius |
| Capsule3 | Achsenlänge + Radius |

## API-Regeln

Shapes bleiben koordinatenlos und orientierungslos:

~~~d
auto cuboid = Cuboid3!double.fromLengths(
    cuboid.length.ab,
    cuboid.length.bc,
    cuboid.length.ae
);
~~~

Placement verwendet dieselben Begriffe wie in 2D:

~~~text
vertex + vertex
vertex + edge
edge + edge
~~~

In 3D bestimmen drei nicht-kollineare Vertex-Korrespondenzen eine starre
Platzierung. Für uniforme Skalierung werden zusätzlich die Zielabstände
ausgewertet. Eine vollständige affine Transformation verwendet Transform3.

## Gemeinsame Transformationsfamilie

~~~text
Translation3
Rotation3
Scale3
Reflection3
Transform3
AnchorBinding3
~~~

Transform3 ist eine freie Koordinatentransformation. AnchorBinding3 bindet
ein Shape oder einen Polyeder an Zielvertices, Zielkanten oder Zielflächen.

## Implementierungsreihenfolge für geo3

1. Point3, Vector3, Segment3 und Plane3
2. Cuboid3 und Cube3
3. Tetrahedron3
4. Prism3 und Pyramid3
5. Sphere3, Cylinder3 und Cone3
6. Ellipsoid3, Frustum3, Torus3 und Capsule3
7. allgemeine Polyeder und Face-/Hole-Ownership

