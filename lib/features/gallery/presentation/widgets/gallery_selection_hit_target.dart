import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class GallerySelectionHitTarget extends SingleChildRenderObjectWidget {
  const GallerySelectionHitTarget({
    super.key,
    required this.assetId,
    required super.child,
  });

  final String assetId;

  @override
  RenderGallerySelectionHitTarget createRenderObject(BuildContext context) {
    return RenderGallerySelectionHitTarget(assetId);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderGallerySelectionHitTarget renderObject,
  ) {
    renderObject.assetId = assetId;
  }
}

class RenderGallerySelectionHitTarget extends RenderProxyBox {
  RenderGallerySelectionHitTarget(this._assetId);

  String _assetId;

  String get assetId => _assetId;

  set assetId(String value) {
    if (value == _assetId) {
      return;
    }
    _assetId = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }

    final bool childHit = hitTestChildren(result, position: position);
    if (hitTestSelf(position) || childHit) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
