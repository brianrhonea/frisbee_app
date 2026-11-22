import 'package:flutter/material.dart';

/// One "Photos +" button for a post's photos: it asks Take photo or
/// Upload photos (straight to the library when there's no camera). Posts
/// take up to their limit; the composer keeps the first ones that fit.
class AddPhotosButton extends StatelessWidget {
  const AddPhotosButton({
    super.key,
    required this.onTakePhoto,
    required this.onUpload,
    required this.canUseCamera,
    this.enabled = true,
    this.label = 'Photos',
    this.style,
  });

  final VoidCallback onTakePhoto;
  final VoidCallback onUpload;
  final bool canUseCamera;
  final bool enabled;

  /// E.g. "Photos" or "Photos (1/4)".
  final String label;
  final ButtonStyle? style;

  Widget _button(VoidCallback? onPressed) => TextButton.icon(
    style: style,
    onPressed: onPressed,
    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 2),
        const Icon(Icons.add, size: 16),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!enabled) return _button(null);
    if (!canUseCamera) return _button(onUpload);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo_camera_outlined),
          onPressed: onTakePhoto,
          child: const Text('Take photo'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo_library_outlined),
          onPressed: onUpload,
          child: const Text('Upload photos'),
        ),
      ],
      builder: (context, menu, _) =>
          _button(() => menu.isOpen ? menu.close() : menu.open()),
    );
  }
}
