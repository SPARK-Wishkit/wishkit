import 'package:flutter/material.dart';

import '../theme/diary_theme.dart';

/// Plain white sheet. Kept under its old name so call sites don't change.
class DiaryGridPaper extends StatelessWidget {
  const DiaryGridPaper({
    super.key,
    required this.child,
    this.color = DiaryColors.paper,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = DiaryTheme.radius,
    this.border,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double borderRadius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        // [border] (old thick gray frame) is intentionally no longer drawn.
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Flat white page body (formerly a bordered notebook sheet).
/// [folderColor] / [border] are kept for older call sites but no longer drawn.
class SpiralNotebook extends StatelessWidget {
  const SpiralNotebook({
    super.key,
    required this.child,
    this.folderColor = DiaryColors.folderBlue,
    this.border,
  });

  final Widget child;
  final Color folderColor;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: DiaryColors.paper, child: child);
  }
}

/// 8px gray band between page sections.
class SectionBand extends StatelessWidget {
  const SectionBand({super.key, this.height = 8});

  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: const ColoredBox(color: DiaryColors.band));
}

/// Settings-style row: icon · label · (trailing) · chevron, hairline below.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.compact = false,
    this.height,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  /// Shorter row (44px, 14pt) for secondary menus.
  final bool compact;

  /// 줄 높이를 직접 정할 때(기본: compact 44, 아니면 54).
  final double? height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height ?? (compact ? 44 : 54),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DiaryColors.line)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 18 : 20, color: DiaryColors.ink),
              SizedBox(width: compact ? 10 : 12),
            ],
            Expanded(
              child: Text(
                label,
                style: DiaryTheme.ui(compact ? 14 : 15, weight: FontWeight.w500),
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
            Icon(
              Icons.chevron_right,
              size: compact ? 18 : 20,
              color: DiaryColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

/// Square checkbox (black fill when checked).
class SelectBox extends StatelessWidget {
  const SelectBox({super.key, required this.checked, this.size = 22});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? DiaryColors.ink : DiaryColors.paper,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? DiaryColors.ink : DiaryColors.inkSoft,
          width: 1.4,
        ),
      ),
      child: checked
          ? Icon(Icons.check, size: size - 6, color: DiaryColors.paper)
          : null,
    );
  }
}

class MineBadge extends StatelessWidget {
  const MineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DiaryColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '나',
        style: DiaryTheme.body(10, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// Flat list row (Musinsa-style): no card, hairline divider underneath.
/// A non-white [backgroundColor] (e.g. "my" feed entries) tints the row.
class WhiteProductCard extends StatelessWidget {
  const WhiteProductCard({
    super.key,
    required this.child,
    this.indexColor,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.backgroundColor = DiaryColors.white,
  });

  final Widget child;
  final Color? indexColor;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: backgroundColor,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DiaryColors.line)),
            ),
            child: Row(
              children: [
                if (indexColor != null)
                  Container(
                    width: 3,
                    height: 36,
                    margin: const EdgeInsets.only(right: 10),
                    color: indexColor,
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name + handle row shared by friend / follower / following lists.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    required this.handle,
    required this.avatarUrl,
    this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String name;
  final String handle;
  final String avatarUrl;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return WhiteProductCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: DiaryColors.surfaceSoft,
            backgroundImage: NetworkImage(avatarUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(15, weight: FontWeight.w700),
                ),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(13, color: DiaryColors.inkSoft),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Musinsa-style button: black fill (primary) or white with hairline outline.
/// [color] is kept for older call sites but no longer used.
class DiaryButton extends StatelessWidget {
  const DiaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.color = DiaryColors.folderBlue,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final IconData? icon;

  bool get _disabled => onPressed == null;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color borderColor;
    if (filled) {
      bg = _disabled ? DiaryColors.tabIdle : DiaryColors.ink;
      fg = _disabled ? DiaryColors.inkSoft : DiaryColors.white;
      borderColor = bg;
    } else {
      bg = DiaryColors.white;
      fg = _disabled ? DiaryColors.inkSoft : DiaryColors.ink;
      borderColor = DiaryColors.lineStrong;
    }
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DiaryTheme.radius),
      side: BorderSide(color: borderColor),
    );
    return Material(
      color: bg,
      shape: shape,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: OneLineText(
                  label,
                  textAlign: TextAlign.center,
                  style: DiaryTheme.body(15, weight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Password field with a small trailing eye to show/hide the value.
class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: hidden,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          tooltip: hidden ? '비밀번호 보기' : '비밀번호 숨기기',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => hidden = !hidden),
          icon: Icon(
            hidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: DiaryColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Label that must stay on one line: shrinks to fit instead of wrapping.
class OneLineText extends StatelessWidget {
  const OneLineText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  Alignment get _alignment => switch (textAlign) {
        TextAlign.center => Alignment.center,
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: _alignment,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

String formatWon(int price) {
  final s = price.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final reverse = s.length - i;
    buf.write(s[i]);
    if (reverse > 1 && reverse % 3 == 1) buf.write(',');
  }
  return '${buf.toString()}원';
}

/// "방금 · N분 전 · N시간 전 · N일 전", 일주일이 넘으면 날짜로 보여준다.
String relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${t.year}.${t.month}.${t.day}';
}
