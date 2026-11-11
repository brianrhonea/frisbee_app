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
  });

  final String text;
  final TextStyle? style;

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
    if (parts.every((p) => p.$2 == null)) {
      return widget.selectable
          ? SelectableText(widget.text, style: widget.style)
          : Text(widget.text, style: widget.style);
    }
    _disposeRecognizers();
    final span = TextSpan(
      style: widget.style,
      children: [
        for (final (text, uri) in parts)
          if (uri == null)
            TextSpan(text: text)
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
}
