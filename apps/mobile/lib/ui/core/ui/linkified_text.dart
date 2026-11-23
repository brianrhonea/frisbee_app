import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/invite_links.dart';

/// Matches web addresses in plain text: http(s) links and bare
/// `www.` ones.
final _url = RegExp(r'''(https?://|www\.)[^\s<>"']+''', caseSensitive: false);

/// Trailing punctuation that usually ends the sentence, not the link.
final _trailing = RegExp(r'[.,;:!?)\]]+$');

/// Splits [text] into plain runs and links, as (text, uri) pairs; uri is
/// null for plain runs.
List<(String, Uri?)> splitLinks(String text) {
  final parts = <(String, Uri?)>[];
  var at = 0;
  for (final m in _url.allMatches(text)) {
    var raw = m.group(0)!;
    final tail = _trailing.firstMatch(raw)?.group(0) ?? '';
    raw = raw.substring(0, raw.length - tail.length);
    final uri = Uri.tryParse(raw.startsWith('www.') ? 'https://$raw' : raw);
    if (uri == null || uri.host.isEmpty) continue;
    if (m.start > at) parts.add((text.substring(at, m.start), null));
    parts.add((raw, uri));
    at = m.start + raw.length;
  }
  if (at < text.length) parts.add((text.substring(at), null));
  return parts;
}

/// Selectable text whose web addresses are tappable. Stall 10's own invite
/// links ([InviteLinks]) open in the app; others open in the browser.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.selectable = true,
    this.mentions = const [],
  });

  final String text;
  final TextStyle? style;

  /// @mentions to draw: [start, end) in [text], and whether it's of the
  /// reader (drawn brighter).
  final List<({int start, int end, bool me})> mentions;

  /// False draws plain text, so a long-press reaches the widget around it
  /// (a chat message's actions, where Copy is one).
  final bool selectable;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(Uri uri) {
    final path = InviteLinks.inAppPath(uri);
    if (path != null) {
      context.push(path);
    } else {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  TapGestureRecognizer _recognizer(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final parts = splitLinks(widget.text);
    // Where each part starts in the text, for its mentions.
    final offsets = <int>[];
    var at = 0;
    for (final (text, _) in parts) {
      offsets.add(at);
      at += text.length;
    }
    if (parts.every((p) => p.$2 == null) && widget.mentions.isEmpty) {
      return widget.selectable
          ? SelectableText(widget.text, style: widget.style)
          : Text(widget.text, style: widget.style);
    }
    _disposeRecognizers();
    final span = TextSpan(
      style: widget.style,
      children: [
        for (final (i, (text, uri)) in parts.indexed)
          if (uri == null)
            ..._plain(text, offsets[i])
          else
            TextSpan(
              text: text,
              style: const TextStyle(decoration: TextDecoration.underline),
              mouseCursor: SystemMouseCursors.click,
              recognizer: _recognizer(() => _open(uri)),
            ),
      ],
    );
    return widget.selectable ? SelectableText.rich(span) : Text.rich(span);
  }

  /// A plain run starting at [offset], with its @mentions drawn.
  List<InlineSpan> _plain(String text, int offset) {
    final end = offset + text.length;
    final inside = [
      for (final m in widget.mentions)
        if (m.start >= offset && m.end <= end) m,
    ];
    if (inside.isEmpty) return [TextSpan(text: text)];
    final scheme = Theme.of(context).colorScheme;
    final out = <InlineSpan>[];
    var at = offset;
    for (final m in inside) {
      if (m.start > at) {
        out.add(TextSpan(text: widget.text.substring(at, m.start)));
      }
      out.add(
        TextSpan(
          text: widget.text.substring(m.start, m.end),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
            backgroundColor: scheme.primary.withValues(
              alpha: m.me ? 0.22 : 0.1,
            ),
          ),
        ),
      );
      at = m.end;
    }
    if (at < end) out.add(TextSpan(text: widget.text.substring(at, end)));
    return out;
  }
}
