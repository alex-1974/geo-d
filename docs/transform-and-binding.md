# Transformation und Andocken

## Freie Transformation

`Transform2` verändert Koordinaten unabhängig von einem Zielobjekt:

```d
auto transform = Transform2!double.rotation(
    Rotation2!double.fromDegrees(45));
auto result = polygon.transform(transform);
```

Die API unterstützt Translation, Rotation, uniforme und unabhängige
Skalierung, Spiegelung, Scherung und affine Komposition.

## Andocken

Ein `AnchorBinding2` registriert Quell- und Zielanker. Daraus werden
Translation, Rotation und — bei ausreichender Information — Skalierung
berechnet:

```d
auto binding = bind(
    sourceEdge(source, 1),
    targetEdge(target, 3),
    ScalePolicy2.uniform);

auto attached = source.attachTo(binding);
```

Ein einzelnes Vertex-zu-Vertex-Paar bestimmt nur Translation. Für Rotation
sind zwei Vertex-Korrespondenzen oder eine gerichtete Kante erforderlich.

## Legacy-API

`VertexPlacement2` und `EdgeAngle2` bleiben vorläufig kompatibel. Neue API
soll `Anchor2`, `AnchorBinding2` und die benannten Factory-Funktionen nutzen.
