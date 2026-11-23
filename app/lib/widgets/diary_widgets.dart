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
    this.onLongPress,
    this.subtitle,
    this.trailing,
  });

  final String name;
  final String handle;
  final String avatarUrl;
  final VoidCallback? onTap;

  /// 길게 누르기 (친구 목록: 신고 · 차단).
  final VoidCallback? onLongPress;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final card = _card();
    if (onLongPress == null) return card;
    return GestureDetector(onLongPress: onLongPress, child: card);
  }

  Widget _card() {
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
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final IconData? icon;

  /// 진행 중이면 글자 왼쪽에 도는 표시를 보여 준다(아이콘 자리).
  final bool loading;

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
              if (loading) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
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

/// wishkit 로고: 앱 아이콘처럼 "wish"의 i 점 대신 별.
///
/// 공유 미리보기 이미지(og-wishkit-star.png)와 **같은 그림**을 쓴다(assets/brand/wishkit-logo.png).
/// 글꼴 위에 별을 따로 그리면 휴대폰마다 글꼴을 그리는 방식이 조금씩 달라 별 간격이 어긋나서,
/// 한 번 그려 둔 그림을 크기만 맞춰 보여 준다. 그림은 Righteous 글꼴 기준
/// 잉크 높이 0.888em · 너비 3.22em(별 너비 0.32em, ı 꼭대기 위 0.05em)이다.
/// [size]는 예전 텍스트 로고의 글자 크기와 같은 뜻이고, 휴대폰 글자 크기 설정도 따른다.
class WishkitLogo extends StatelessWidget {
  const WishkitLogo({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  static const _inkHeight = 0.888; // em
  static const _inkWidth = 3.22; // em
  static const _lineHeight = 1.1; // 예전 텍스트 로고(DiaryTheme.logo)의 줄 높이

  @override
  Widget build(BuildContext context) {
    final em = MediaQuery.textScalerOf(context).scale(size);
    return Semantics(
      label: 'wishkit',
      image: true,
      excludeSemantics: true,
      // 예전 텍스트 로고와 같은 자리·높이를 차지하게(주변 배치가 바뀌지 않게).
      child: SizedBox(
        height: em * _lineHeight,
        width: em * _inkWidth,
        child: Align(
          alignment: Alignment.topLeft,
          child: Image.asset(
            'assets/brand/wishkit-logo.png',
            height: em * _inkHeight,
            width: em * _inkWidth,
            fit: BoxFit.contain,
            color: color ?? DiaryColors.ink,
            colorBlendMode: BlendMode.srcIn,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
