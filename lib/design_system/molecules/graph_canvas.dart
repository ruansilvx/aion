// design_system/molecules/graph_canvas.dart — GraphCanvas pan/zoom node-graph primitive (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// One positioned node on a [GraphCanvas], generic over the caller's own
/// node-data type [T] — this primitive has no knowledge of `DecisionNode`
/// or any other domain type. [position]/[size] are in canvas coordinate
/// space (unaffected by the viewer's current pan/zoom).
class GraphCanvasNode<T> {
  /// Creates a [GraphCanvasNode].
  const GraphCanvasNode({
    required this.id,
    required this.position,
    required this.data,
    this.size = const Size(264, 72),
  });

  /// Stable identity, referenced by [GraphCanvasEdge.fromId]/`.toId`.
  final String id;

  /// Top-left corner in canvas coordinate space.
  final Offset position;

  /// This node's top-left size, used to compute edge anchor points.
  final Size size;

  /// The caller's own data for this node, passed to [GraphCanvas
  /// .nodeBuilder].
  final T data;
}

/// One edge on a [GraphCanvas], connecting [fromId]'s bottom-center to
/// [toId]'s top-center. [dashed]/[muted] together encode Aion's
/// matched-vs-unmatched branch distinction (solid+`primary` vs.
/// dashed+`borderStrong`) without this primitive knowing what a "branch"
/// is.
class GraphCanvasEdge {
  /// Creates a [GraphCanvasEdge].
  const GraphCanvasEdge({
    required this.fromId,
    required this.toId,
    this.dashed = false,
    this.muted = false,
    this.label,
  });

  /// The source node's id.
  final String fromId;

  /// The target node's id.
  final String toId;

  /// `true` renders a dashed line; `false` renders solid.
  final bool dashed;

  /// `true` tints the line/label `textMuted`/`borderStrong` instead of
  /// `primary`.
  final bool muted;

  /// Optional short label rendered at the edge's midpoint.
  final String? label;
}

/// Aion's pan/zoom/node-graph primitive — `InteractiveViewer` (pan/zoom)
/// wrapping a `Stack` of positioned node widgets, with a `CustomPainter`
/// beneath drawing [edges] between node anchor points. Hand-built
/// gestures only (`GestureDetector`/`MouseRegion`), no Material import.
/// Generic over a node/edge model and a per-node content builder — not
/// specific to `DecisionNode`, so it can be reused by any future
/// node-graph feature. Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §1/§5.
class GraphCanvas<T> extends StatefulWidget {
  /// Creates a [GraphCanvas].
  const GraphCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    required this.nodeBuilder,
    this.selectedId,
    this.onNodeTap,
    this.onNodeDragEnd,
    this.emptyState,
  });

  /// Every node to render, positioned in canvas coordinate space.
  final List<GraphCanvasNode<T>> nodes;

  /// Every edge to render beneath [nodes].
  final List<GraphCanvasEdge> edges;

  /// Builds a node's visible content — [nodeBuilder] itself owns the
  /// node's fill/border/shadow chrome, since exactly how a node should
  /// look is entirely caller-specific.
  final Widget Function(BuildContext context, T data, bool selected)
  nodeBuilder;

  /// The currently-selected node's id, if any — passed through to
  /// [nodeBuilder] so the caller can render its own selected-state
  /// treatment.
  final String? selectedId;

  /// Called with a node's id when it's tapped.
  final ValueChanged<String>? onNodeTap;

  /// Called with a node's id and its new canvas-space position once a
  /// drag gesture ends.
  final void Function(String id, Offset newPosition)? onNodeDragEnd;

  /// Rendered centered over the plane, replacing every node, when
  /// [nodes] is empty.
  final Widget? emptyState;

  @override
  State<GraphCanvas<T>> createState() => _GraphCanvasState<T>();
}

class _GraphCanvasState<T> extends State<GraphCanvas<T>> {
  final TransformationController _transformationController =
      TransformationController();
  String? _draggingId;
  Offset? _dragPosition;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final current = _transformationController.value.clone();
    final newScale = (current.getMaxScaleOnAxis() * factor).clamp(0.4, 2.0);
    final scaleFactor = newScale / current.getMaxScaleOnAxis();
    _transformationController.value = current
      ..scaleByDouble(scaleFactor, scaleFactor, 1, 1);
  }

  void _resetView() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final positions = {
      for (final node in widget.nodes)
        node.id: node.id == _draggingId
            ? (_dragPosition ?? node.position)
            : node.position,
    };
    final sizes = {for (final node in widget.nodes) node.id: node.size};

    return DecoratedBox(
      decoration: BoxDecoration(color: c.background),
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: InteractiveViewer(
                transformationController: _transformationController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(600),
                minScale: 0.4,
                maxScale: 2.0,
                child: SizedBox(
                  width: 2400,
                  height: 1600,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _EdgePainter(
                            edges: widget.edges,
                            positions: positions,
                            sizes: sizes,
                            colors: c,
                            isDark: t.isDark,
                          ),
                        ),
                      ),
                      for (final node in widget.nodes)
                        Positioned(
                          left: positions[node.id]!.dx,
                          top: positions[node.id]!.dy,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => widget.onNodeTap?.call(node.id),
                            onPanStart: (_) =>
                                setState(() => _draggingId = node.id),
                            onPanUpdate: (details) => setState(() {
                              _dragPosition =
                                  (_dragPosition ?? node.position) +
                                  details.delta;
                            }),
                            onPanEnd: (_) {
                              final finalPosition =
                                  _dragPosition ?? node.position;
                              setState(() {
                                _draggingId = null;
                                _dragPosition = null;
                              });
                              widget.onNodeDragEnd?.call(
                                node.id,
                                finalPosition,
                              );
                            },
                            child: widget.nodeBuilder(
                              context,
                              node.data,
                              node.id == widget.selectedId,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.nodes.isEmpty && widget.emptyState != null)
            Positioned.fill(child: Center(child: widget.emptyState)),
          Positioned(
            left: 16,
            bottom: 16,
            child: _ZoomCluster(
              onZoomOut: () => _zoomBy(1 / 1.1),
              onZoomIn: () => _zoomBy(1.1),
              onFit: _resetView,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints every [GraphCanvasEdge] beneath [GraphCanvas]'s nodes in one
/// pass — an orthogonal path from each source node's bottom-center to its
/// target's top-center, solid or dashed per [GraphCanvasEdge.dashed].
class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.edges,
    required this.positions,
    required this.sizes,
    required this.colors,
    required this.isDark,
  });

  final List<GraphCanvasEdge> edges;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  final AionColors colors;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final fromPos = positions[edge.fromId];
      final toPos = positions[edge.toId];
      final fromSize = sizes[edge.fromId];
      final toSize = sizes[edge.toId];
      if (fromPos == null || toPos == null) continue;

      final start = Offset(
        fromPos.dx + (fromSize?.width ?? 0) / 2,
        fromPos.dy + (fromSize?.height ?? 0),
      );
      final end = Offset(toPos.dx + (toSize?.width ?? 0) / 2, toPos.dy);

      final color = edge.muted ? colors.borderStrong : colors.primary;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, start.dy + 28)
        ..lineTo(end.dx, start.dy + 28)
        ..lineTo(end.dx, end.dy);

      if (edge.dashed) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      // Arrowhead at the target's top edge.
      final arrow = Path()
        ..moveTo(end.dx - 4, end.dy - 5)
        ..lineTo(end.dx + 4, end.dy - 5)
        ..lineTo(end.dx, end.dy)
        ..close();
      canvas.drawPath(arrow, Paint()..color = color);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.isDark != isDark;
  }
}

/// The bottom-left zoom-out/fit/zoom-in cluster, rendered outside the
/// `InteractiveViewer` so it never itself scales. Per design.md §1.6.
class _ZoomCluster extends StatelessWidget {
  const _ZoomCluster({
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomButton(label: '−', onTap: onZoomOut),
            _ZoomButton(label: '⤢', onTap: onFit),
            _ZoomButton(label: '+', onTap: onZoomIn),
          ],
        ),
      ),
    );
  }
}

/// One button in [_ZoomCluster] — a small square tap target with a
/// centered glyph, matching every other small icon-button primitive in
/// this app (hand-built, no Material `IconButton`).
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Text(
                label,
                style: AionText.bodySm.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
