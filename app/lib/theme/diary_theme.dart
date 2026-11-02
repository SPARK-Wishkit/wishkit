import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Black & white diary / scrapbook palette.
class DiaryColors {
  /// App canvas behind paper/folders
  static const canvas = Color(0xFFF2F2F2);
  static const paper = Color(0xFFFFFFFF);

  /// Soft gray fill for banners, thumbnails and idle tabs (mockup 2026-11).
  static const surfaceSoft = Color(0xFFF3F3F3);
  static const tabIdle = Color(0xFFE6E6E6);

  /// Hairline border for cards and checkboxes.
  static const line = Color(0xFFE8E8E8);
  static const lineStrong = Color(0xFFD4D4D4);

  /// Thick section separator (the gray band between blocks on Musinsa).
  static const band = Color(0xFFF4F4F4);

  /// Point color — discount rate / savings only.
  static const sale = Color(0xFFE0322B);
  static const grid = Color(0xFFC2C2C2);
  static const white = Color(0xFFFFFFFF);
  /// Light greige for "my" feed cards — a wash of the app taupe, still readable.
  static const mineCard = Color(0xFFE0E0E0);
  static const ink = Color(0xFF000000);
  static const inkMuted = Color(0xFF3A3A3A);
  static const inkSoft = Color(0xFF6E6E6E);

  /// Neutral file/folder colors (from reference palette)
  static const fileTaupe = Color(0xFFB4B4B4);
  static const fileStone = Color(0xFFC6C6C6);
  static const fileCream = Color(0xFFCECECE);
  static const fileSand = Color(0xFFBCBCBC);
  static const fileMauve = Color(0xFFCACACA);

  /// Extra neutrals in the same family (avoid clash when many lists)
  static const fileWarmGray = Color(0xFFB8B8B8);
  static const fileMist = Color(0xFFD4D4D4);
  static const fileClay = Color(0xFFC0C0C0);

  static const folderBlue = fileCream;
  static const folderPeach = fileSand;
  static const folderYellow = fileStone;
  static const folderLilac = fileMauve;
  static const folderMint = fileWarmGray;
  static const folderPink = fileClay;

  static const accent = Color(0xFF000000);
  static const pin = Color(0xFF000000);

  /// Pool used when creating new lists (prefer unused first).
  static const fileColors = [
    fileTaupe,
    fileStone,
    fileCream,
    fileSand,
    fileMauve,
    fileWarmGray,
    fileMist,
    fileClay,
  ];

  /// Alias kept for older call sites.
  static const pastels = fileColors;
}

class DiaryTheme {
  /// Corner radius for buttons, inputs and thumbnails on list screens.
  static const double radius = 4;

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DiaryColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DiaryColors.accent,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
        brightness: Brightness.light,
        surface: DiaryColors.paper,
      ),
    );

    // UI default: clean gothic (Noto Sans KR). Jua is kept only for the logo.
    final uiText = GoogleFonts.notoSansKrTextTheme(base.textTheme).apply(
      bodyColor: DiaryColors.ink,
      displayColor: DiaryColors.ink,
    );

    return base.copyWith(
      textTheme: uiText,
      primaryTextTheme: uiText,
      // Musinsa-style controls: square-ish (4px), black primary, hairline outline.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DiaryColors.ink,
          foregroundColor: DiaryColors.white,
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: ui(13, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DiaryColors.ink,
          minimumSize: const Size(0, 36),
          side: const BorderSide(color: DiaryColors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: ui(13, weight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: DiaryColors.line,
        thickness: 1,
        space: 1,
      ),
      // Sub-pages: white bar, centred bold title, hairline underneath.
      appBarTheme: AppBarTheme(
        backgroundColor: DiaryColors.white,
        foregroundColor: DiaryColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        shape: const Border(bottom: BorderSide(color: DiaryColors.line)),
        titleTextStyle: ui(17, weight: FontWeight.w700),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DiaryColors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: DiaryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DiaryColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        titleTextStyle: ui(17, weight: FontWeight.w700),
        contentTextStyle: ui(14, color: DiaryColors.inkMuted),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DiaryColors.ink,
          textStyle: ui(14, weight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        hintStyle: ui(14, color: DiaryColors.inkSoft),
        labelStyle: ui(14, color: DiaryColors.inkSoft),
        floatingLabelStyle: ui(13, color: DiaryColors.ink),
        // Only `border` here (not enabled/focusedBorder) so fields that pass
        // `border: InputBorder.none` still render borderless.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: DiaryColors.lineStrong),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: DiaryColors.inkSoft, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DiaryColors.ink
              : DiaryColors.white,
        ),
        checkColor: const WidgetStatePropertyAll(DiaryColors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(DiaryColors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DiaryColors.ink
              : DiaryColors.lineStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: DiaryColors.ink,
        contentTextStyle: ui(14, color: DiaryColors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DiaryColors.white,
        selectedColor: DiaryColors.ink,
        side: const BorderSide(color: DiaryColors.lineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        labelStyle: ui(14, weight: FontWeight.w600),
        showCheckmark: false,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DiaryColors.ink,
      ),
    );
  }

  /// Rounded UI font for labels, tabs, buttons, banners (not product data).
  /// [size] is a design-pixel value at 390pt width; [DiaryScale] scales the tree.
  static TextStyle ui(
    double size, {
    Color? color,
    FontWeight? weight,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? DiaryColors.ink,
      height: 1.3,
    );
  }

  /// Page titles — heavy, tight gothic (Musinsa-style).
  static TextStyle display(double size, {Color? color, FontWeight? weight}) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w800,
      color: color ?? DiaryColors.ink,
      height: 1.15,
      letterSpacing: -0.6,
    );
  }

  /// The "wishkit" wordmark only (Righteous — chosen 2026-11).
  static TextStyle logo(double size, {Color? color}) {
    return GoogleFonts.righteous(
      fontSize: size,
      fontWeight: FontWeight.w400,
      color: color ?? DiaryColors.ink,
      height: 1.1,
    );
  }

  /// Parsed product info (store, name, price) — keep clean gothic.
  static TextStyle product(
    double size, {
    Color? color,
    FontWeight? weight,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? DiaryColors.ink,
      height: 1.35,
    );
  }

  /// Backward-compatible alias → UI font.
  static TextStyle body(
    double size, {
    Color? color,
    FontWeight? weight,
  }) =>
      ui(size, color: color, weight: weight);
}
