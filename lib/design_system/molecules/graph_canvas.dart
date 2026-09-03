// design_system/molecules/graph_canvas.dart — GraphCanvas pan/zoom node-graph primitive (design-system layer).

import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_shadows.dart';
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

/// The side of a 24px lattice cell nearest [value] — shared by [GraphCanvas]'s
/// own node-drag snapping and available to callers that want to pre-snap a
/// manually-set position before storing it. Added for `AIO-181` (`/verify` fix
/// pass 2).
double snapToGraphCanvasLattice(double value) => (value / 24).round() * 24.0;

/// Aion's pan/zoom/node-graph primitive — `InteractiveViewer` (pan/zoom)
/// wrapping a `Stack` of positioned node widgets, with a `CustomPainter`
/// beneath drawing [edges] between node anchor points, and a 24px dot grid
/// painted in canvas space beneath that (design.md §1.1) so it pans and zooms
/// with the plane and doubles as pan/zoom feedback. Hand-built gestures only
/// (`GestureDetector`/`MouseRegion`/`Listener`), no Material import. Generic
/// over a node/edge model and a per-node content builder — not specific to
/// `DecisionNode`, so it can be reused by any future node-graph feature. Added
/// for `AIO-181`; see its linked Documentation page, §1/§5 (`/verify` fix pass
/// 2 added the dot grid, cursor states, drag-settle animation, and the zoom
/// cluster's shadow/readout/ keyboard-zoom/double-tap-fit/disabled-at-bounds
/// states — see [_GraphCanvasState]/[_ZoomCluster]'s own dartdocs).
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
  /// look is entirely caller-specific. [hovered]/[dragging] let the
  /// caller render design.md §1.2.1's hover/dragging node states; neither
  /// implies [selected].
  final Widget Function(
    BuildContext context,
    T data,
    bool selected,
    bool hovered,
    bool dragging,
  )
  nodeBuilder;

  /// The currently-selected node's id, if any — passed through to
  /// [nodeBuilder] so the caller can render its own selected-state
  /// treatment.
  final String? selectedId;

  /// Called with a node's id when it's tapped.
  final ValueChanged<String>? onNodeTap;

  /// Called with a node's id and its new canvas-space position, already
  /// snapped to the 24px lattice, once a drag gesture's settle animation
  /// finishes. A caller with nowhere to persist a manual position (e.g.
  /// one that always re-derives [nodes] from an auto-layout) can simply
  /// omit this — the drag still visually snaps and settles, it just
  /// reverts to [nodes]' own position on the next rebuild.
  final void Function(String id, Offset newPosition)? onNodeDragEnd;

  /// Rendered centered over the plane, replacing every node, when
  /// [nodes] is empty.
  final Widget? emptyState;

  @override
  State<GraphCanvas<T>> createState() => _GraphCanvasState<T>();
}

/// See [GraphCanvas]'s own dartdoc for the primitive's overall shape.
/// Beyond pan/zoom/select, this state owns: [_isPanning] (drives the
/// plane's `grab`/`grabbing` cursor per design.md §1.1), [_scale]
/// (mirrors [_transformationController]'s current zoom — drives the dot
/// grid's `scale < 0.6` fade, the zoom-cluster readout, and its
/// zoom-in/zoom-out disabled-at-bounds states), and the drag-settle
/// animation (`_draggingId`/`_dragPosition` track a live drag exactly as
/// before; once released, [_settleDrag] snaps the drop point to the 24px
/// lattice and tweens into it over 120ms before calling
/// [GraphCanvas.onNodeDragEnd] with the final, already-snapped position).
class _GraphCanvasState<T> extends State<GraphCanvas<T>>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.4;
  static const double _maxScale = 2.0;

  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _settleController;
  String? _draggingId;
  Offset? _dragPosition;
  bool _isPanning = false;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final newScale = _transformationController.value.getMaxScaleOnAxis();
    if ((newScale - _scale).abs() > 0.001) {
      setState(() => _scale = newScale);
    }
  }

  void _zoomBy(double factor) {
    final current = _transformationController.value.clone();
    final newScale = (current.getMaxScaleOnAxis() * factor).clamp(
      _minScale,
      _maxScale,
    );
    final scaleFactor = newScale / current.getMaxScaleOnAxis();
    _transformationController.value = current
      ..scaleByDouble(scaleFactor, scaleFactor, 1, 1);
  }

  void _resetView() {
    _transformationController.value = Matrix4.identity();
  }

  /// Snaps [rawPosition] to the 24px lattice and tweens the dragged
  /// node's visual position into that snapped point over 120ms
  /// (`Curves.easeOut`), then reports the final snapped position via
  /// [GraphCanvas.onNodeDragEnd] and clears the drag-override entirely —
  /// design.md §1.1's "snapped to the 24px lattice on release
  /// (`AnimatedPositioned`, 120ms `Curves.easeOut`)".
  void _settleDrag(String id, Offset rawPosition) {
    final target = Offset(
      snapToGraphCanvasLattice(rawPosition.dx),
      snapToGraphCanvasLattice(rawPosition.dy),
    );
    final start = rawPosition;
    _settleController
      ..stop()
      ..value = 0;
    void tick() {
      final t = Curves.easeOut.transform(_settleController.value);
      setState(() => _dragPosition = Offset.lerp(start, target, t));
    }

    _settleController.addListener(tick);
    _settleController.forward().whenCompleteOrCancel(() {
      _settleController.removeListener(tick);
      if (!mounted) return;
      setState(() {
        _draggingId = null;
        _dragPosition = null;
      });
      widget.onNodeDragEnd?.call(id, target);
    });
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
              cursor: _isPanning
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: Listener(
                onPointerSignal: (event) => _handlePointerSignal(event),
                child: GestureDetector(
                  onDoubleTap: _resetView,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(600),
                    minScale: _minScale,
                    maxScale: _maxScale,
                    onInteractionStart: (_) =>
                        setState(() => _isPanning = true),
                    onInteractionEnd: (_) => setState(() => _isPanning = false),
                    child: SizedBox(
                      width: 2400,
                      height: 1600,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _GridPainter(
                                scale: _scale,
                                colors: c,
                                isDark: t.isDark,
                              ),
                            ),
                          ),
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
                              child: _CanvasNodeGesture<T>(
                                node: node,
                                selected: node.id == widget.selectedId,
                                dragging: node.id == _draggingId,
                                nodeBuilder: widget.nodeBuilder,
                                onTap: () => widget.onNodeTap?.call(node.id),
                                onPanStart: () =>
                                    setState(() => _draggingId = node.id),
                                onPanUpdate: (delta) => setState(() {
                                  _dragPosition =
                                      (_dragPosition ?? node.position) + delta;
                                }),
                                onPanEnd: () => _settleDrag(
                                  node.id,
                                  _dragPosition ?? node.position,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
              scale: _scale,
              minScale: _minScale,
              maxScale: _maxScale,
              onZoomOut: () => _zoomBy(1 / 1.1),
              onZoomIn: () => _zoomBy(1.1),
              onFit: _resetView,
            ),
          ),
        ],
      ),
    );
  }

  /// `Ctrl`/`⌘` + scroll continuously zooms, centered on the current
  /// view — design.md §1.6's "Zoom step" row. A plain scroll (no
  /// modifier) is left to [InteractiveViewer]'s own pan-by-scroll
  /// handling, unchanged.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final isZoomModifierDown =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isZoomModifierDown) return;
    final factor = math.exp(-event.scrollDelta.dy / 200);
    _zoomBy(factor);
  }
}

/// Wraps one node's content with its tap/drag gestures and hover tracking, and
/// computes the `move` cursor design.md §1.1 specifies for a node's drag area.
/// Split out of [_GraphCanvasState.build] purely so hover state
/// (`MouseRegion.onEnter`/`.onExit`) doesn't force the whole canvas to rebuild
/// on every node hover change. Added for `AIO-181` (`/verify` fix pass 2).
class _CanvasNodeGesture<T> extends StatefulWidget {
  const _CanvasNodeGesture({
    required this.node,
    required this.selected,
    required this.dragging,
    required this.nodeBuilder,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final GraphCanvasNode<T> node;
  final bool selected;
  final bool dragging;
  final Widget Function(
    BuildContext context,
    T data,
    bool selected,
    bool hovered,
    bool dragging,
  )
  nodeBuilder;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  State<_CanvasNodeGesture<T>> createState() => _CanvasNodeGestureState<T>();
}

class _CanvasNodeGestureState<T> extends State<_CanvasNodeGesture<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.move,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: (_) => widget.onPanStart(),
        onPanUpdate: (details) => widget.onPanUpdate(details.delta),
        onPanEnd: (_) => widget.onPanEnd(),
        child: widget.nodeBuilder(
          context,
          widget.node.data,
          widget.selected,
          _hovered,
          widget.dragging,
        ),
      ),
    );
  }
}

/// Paints the 24px dot-grid lattice beneath every [GraphCanvas] node/edge, in
/// canvas space (so it pans/zooms with the plane) — design.md §1.1. Hidden
/// below `scale < 0.6`, since the dots alias into noise at low zoom. Added for
/// `AIO-181` (`/verify` fix pass 2).
class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.scale,
    required this.colors,
    required this.isDark,
  });

  final double scale;
  final AionColors colors;
  final bool isDark;

  static const double _spacing = 24;
  static const double _dotDiameter = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale < 0.6) return;
    final paint = Paint()
      ..color = colors.borderStrong.withValues(alpha: isDark ? 0.55 : 0.45);
    for (var y = 0.0; y < size.height; y += _spacing) {
      for (var x = 0.0; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _dotDiameter / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.isDark != isDark;
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
/// `/verify` fix pass 2 added the shadow, the live percentage [readout],
/// and disabling zoom-out/zoom-in at [minScale]/[maxScale].
class _ZoomCluster extends StatelessWidget {
  const _ZoomCluster({
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final double scale;
  final double minScale;
  final double maxScale;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
        boxShadow: AionShadows.card(c, t.isDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomButton(
              label: '−',
              enabled: scale > minScale + 0.001,
              onTap: onZoomOut,
            ),
            _ZoomButton(label: '⤢', enabled: true, onTap: onFit),
            SizedBox(
              width: 44,
              child: Center(
                child: Text(
                  '${(scale * 100).round()}%',
                  style: AionText.key.copyWith(color: c.textMuted),
                ),
              ),
            ),
            _ZoomButton(
              label: '+',
              enabled: scale < maxScale - 0.001,
              onTap: onZoomIn,
            ),
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
  const _ZoomButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Text(
                label,
                style: AionText.bodySm.copyWith(
                  color: enabled
                      ? c.textSecondary
                      : c.textMuted.withValues(alpha: 0.45),
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
