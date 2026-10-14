// Salva Patitas — tema 3D "plastilina".
// Generado desde el sistema de diseño (tokens.json). No cambies los valores a mano:
// si un color cambia, cámbialo aquí y en ningún otro lado.
//
// Uso:
//   MaterialApp(theme: SpTheme.light(), darkTheme: SpTheme.dark(), ...)
//   final c = context.sp;          // colores
//   Container(decoration: SpDeco.card(c))   // tarjeta 3D
//
// Dependencias: flutter_svg. La fuente Plus Jakarta Sans va empaquetada
// en assets/fonts (no se descarga en tiempo de ejecución: funciona sin señal).

import 'package:flutter/material.dart';

/// Familia declarada en pubspec.yaml (assets/fonts/PlusJakartaSans-*.ttf).
const spFontFamily = 'PlusJakartaSans';

@immutable
class SpColors extends ThemeExtension<SpColors> {
  final Color
  bg; // Fondo de pantalla, casi blanco con un toque menta. Plano; las piezas 3D y las huellitas decorativas van encima.
  final Color surface; // Tarjetas, listas, barra de pestañas.
  final Color
  surfaceSunken; // Campos, burbuja del chevron, estados presionados.
  final Color line; // Divisores de 1px.
  final Color edge; // Canto 3D bajo tarjetas, chips y botones secundarios.
  final Color ink; // Texto principal y cifras.
  final Color inkMuted; // Texto secundario (≥5.4:1 sobre surface y bg).
  final Color inkFaint; // Solo íconos inactivos y chevrons.
  final Color
  primary; // El verde nuevo: esmeralda menta, vivo y fresco. Relleno de botón principal, héroe y pestaña activa. Texto encima: on-primary (oscuro).
  final Color
  primaryLight; // Arriba del degradado del héroe y brillo de piezas verdes.
  final Color primaryEdge; // Canto 3D bajo piezas verdes.
  final Color
  primaryStrong; // Texto y enlaces verdes sobre surface o primary-soft (Ver todas, Gestionar).
  final Color
  onPrimary; // Texto e íconos sobre primary: verde casi negro (6:1 / 9.2:1). Más moderno que el blanco.
  final Color
  primarySoft; // Fondo de chips seleccionados y estados verdes suaves.
  final Color mintLight; // Brillo de baldosas menta.
  final Color mint; // Baldosa menta (huellita, En cuidado).
  final Color mintDeep; // Sombra de baldosas menta.
  final Color peach; // Baldosa durazno (perros, Subir lote).
  final Color peachDeep; // Sombra de la baldosa durazno.
  final Color peachInk; // Texto sobre peach (5.8:1 / 8.2:1).
  final Color lilac; // Baldosa lila (gatos, Subir uno, Solicitudes).
  final Color lilacDeep; // Sombra de la baldosa lila.
  final Color lilacInk; // Texto sobre lilac.
  final Color sky; // Baldosa cielo (conejos, otras especies).
  final Color skyDeep; // Sombra de la baldosa cielo.
  final Color skyInk; // Texto sobre sky.
  final Color butter; // Baldosa mantequilla (casa, adoptados, hogares de paso).
  final Color butterDeep; // Sombra de la baldosa mantequilla.
  final Color butterInk; // Texto sobre butter.
  final Color
  accent; // Coral para insignias Nuevo/Urgente y punto de notificación.
  final Color accentSoft; // Fondo de insignia suave.
  final Color accentInk; // Texto sobre accent-soft.
  final Color onAccent; // Texto sobre accent (insignia Nuevo).
  final Color danger; // Solo acciones destructivas y errores.
  final Color dangerSoft; // Fondo de errores.

  const SpColors({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.line,
    required this.edge,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.primary,
    required this.primaryLight,
    required this.primaryEdge,
    required this.primaryStrong,
    required this.onPrimary,
    required this.primarySoft,
    required this.mintLight,
    required this.mint,
    required this.mintDeep,
    required this.peach,
    required this.peachDeep,
    required this.peachInk,
    required this.lilac,
    required this.lilacDeep,
    required this.lilacInk,
    required this.sky,
    required this.skyDeep,
    required this.skyInk,
    required this.butter,
    required this.butterDeep,
    required this.butterInk,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.onAccent,
    required this.danger,
    required this.dangerSoft,
  });

  static const light = SpColors(
    bg: Color(0xFFF4F8F6),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDF3F0),
    line: Color(0xFFE2EAE6),
    edge: Color(0xFFD6E4DD),
    ink: Color(0xFF14201B),
    inkMuted: Color(0xFF56665F),
    inkFaint: Color(0xFF7D8B85),
    primary: Color(0xFF22C08A),
    primaryLight: Color(0xFF5FE0B0),
    primaryEdge: Color(0xFF129968),
    primaryStrong: Color(0xFF087A51),
    onPrimary: Color(0xFF053322),
    primarySoft: Color(0xFFDCF7EC),
    mintLight: Color(0xFFEFFCF6),
    mint: Color(0xFFC4F3DE),
    mintDeep: Color(0xFF7DDCB4),
    peach: Color(0xFFFFE3D1),
    peachDeep: Color(0xFFF7B08A),
    peachInk: Color(0xFF8A3D16),
    lilac: Color(0xFFEBE4FF),
    lilacDeep: Color(0xFFBBA8F6),
    lilacInk: Color(0xFF5A3FB0),
    sky: Color(0xFFDCEFFF),
    skyDeep: Color(0xFF94C8F5),
    skyInk: Color(0xFF1F5F99),
    butter: Color(0xFFFFF3C4),
    butterDeep: Color(0xFFF2CF5B),
    butterInk: Color(0xFF7A5A00),
    accent: Color(0xFFFF7A59),
    accentSoft: Color(0xFFFFE9E2),
    accentInk: Color(0xFFA63D1F),
    onAccent: Color(0xFF3D1206),
    danger: Color(0xFFC23B2A),
    dangerSoft: Color(0xFFFBEAE7),
  );

  static const dark = SpColors(
    bg: Color(0xFF0E1311),
    surface: Color(0xFF161D1A),
    surfaceSunken: Color(0xFF1C2420),
    line: Color(0xFF26302B),
    edge: Color(0xFF070A09),
    ink: Color(0xFFEDF3F0),
    inkMuted: Color(0xFFA3B3AC),
    inkFaint: Color(0xFF7F8F88),
    primary: Color(0xFF3EE0A1),
    primaryLight: Color(0xFF7CF0C4),
    primaryEdge: Color(0xFF1F9E6E),
    primaryStrong: Color(0xFF6FF0BD),
    onPrimary: Color(0xFF042A1C),
    primarySoft: Color(0xFF143528),
    mintLight: Color(0xFF2F6B52),
    mint: Color(0xFF22513E),
    mintDeep: Color(0xFF153A2C),
    peach: Color(0xFF4A2C1F),
    peachDeep: Color(0xFFA8603F),
    peachInk: Color(0xFFFFC4A3),
    lilac: Color(0xFF2F2750),
    lilacDeep: Color(0xFF6D58B8),
    lilacInk: Color(0xFFCDBFFF),
    sky: Color(0xFF1C3348),
    skyDeep: Color(0xFF3D78AD),
    skyInk: Color(0xFFA9D6FF),
    butter: Color(0xFF3D3417),
    butterDeep: Color(0xFFA88A2A),
    butterInk: Color(0xFFFFE48A),
    accent: Color(0xFFFF9B80),
    accentSoft: Color(0xFF3A2119),
    accentInk: Color(0xFFFFB39F),
    onAccent: Color(0xFF3D1206),
    danger: Color(0xFFF08470),
    dangerSoft: Color(0xFF341A16),
  );

  @override
  SpColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceSunken,
    Color? line,
    Color? edge,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? primary,
    Color? primaryLight,
    Color? primaryEdge,
    Color? primaryStrong,
    Color? onPrimary,
    Color? primarySoft,
    Color? mintLight,
    Color? mint,
    Color? mintDeep,
    Color? peach,
    Color? peachDeep,
    Color? peachInk,
    Color? lilac,
    Color? lilacDeep,
    Color? lilacInk,
    Color? sky,
    Color? skyDeep,
    Color? skyInk,
    Color? butter,
    Color? butterDeep,
    Color? butterInk,
    Color? accent,
    Color? accentSoft,
    Color? accentInk,
    Color? onAccent,
    Color? danger,
    Color? dangerSoft,
  }) => SpColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    line: line ?? this.line,
    edge: edge ?? this.edge,
    ink: ink ?? this.ink,
    inkMuted: inkMuted ?? this.inkMuted,
    inkFaint: inkFaint ?? this.inkFaint,
    primary: primary ?? this.primary,
    primaryLight: primaryLight ?? this.primaryLight,
    primaryEdge: primaryEdge ?? this.primaryEdge,
    primaryStrong: primaryStrong ?? this.primaryStrong,
    onPrimary: onPrimary ?? this.onPrimary,
    primarySoft: primarySoft ?? this.primarySoft,
    mintLight: mintLight ?? this.mintLight,
    mint: mint ?? this.mint,
    mintDeep: mintDeep ?? this.mintDeep,
    peach: peach ?? this.peach,
    peachDeep: peachDeep ?? this.peachDeep,
    peachInk: peachInk ?? this.peachInk,
    lilac: lilac ?? this.lilac,
    lilacDeep: lilacDeep ?? this.lilacDeep,
    lilacInk: lilacInk ?? this.lilacInk,
    sky: sky ?? this.sky,
    skyDeep: skyDeep ?? this.skyDeep,
    skyInk: skyInk ?? this.skyInk,
    butter: butter ?? this.butter,
    butterDeep: butterDeep ?? this.butterDeep,
    butterInk: butterInk ?? this.butterInk,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    accentInk: accentInk ?? this.accentInk,
    onAccent: onAccent ?? this.onAccent,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
  );

  @override
  SpColors lerp(ThemeExtension<SpColors>? other, double t) {
    if (other is! SpColors) return this;
    final o = other;
    return SpColors(
      bg: Color.lerp(bg, o.bg, t)!,
      surface: Color.lerp(surface, o.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, o.surfaceSunken, t)!,
      line: Color.lerp(line, o.line, t)!,
      edge: Color.lerp(edge, o.edge, t)!,
      ink: Color.lerp(ink, o.ink, t)!,
      inkMuted: Color.lerp(inkMuted, o.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, o.inkFaint, t)!,
      primary: Color.lerp(primary, o.primary, t)!,
      primaryLight: Color.lerp(primaryLight, o.primaryLight, t)!,
      primaryEdge: Color.lerp(primaryEdge, o.primaryEdge, t)!,
      primaryStrong: Color.lerp(primaryStrong, o.primaryStrong, t)!,
      onPrimary: Color.lerp(onPrimary, o.onPrimary, t)!,
      primarySoft: Color.lerp(primarySoft, o.primarySoft, t)!,
      mintLight: Color.lerp(mintLight, o.mintLight, t)!,
      mint: Color.lerp(mint, o.mint, t)!,
      mintDeep: Color.lerp(mintDeep, o.mintDeep, t)!,
      peach: Color.lerp(peach, o.peach, t)!,
      peachDeep: Color.lerp(peachDeep, o.peachDeep, t)!,
      peachInk: Color.lerp(peachInk, o.peachInk, t)!,
      lilac: Color.lerp(lilac, o.lilac, t)!,
      lilacDeep: Color.lerp(lilacDeep, o.lilacDeep, t)!,
      lilacInk: Color.lerp(lilacInk, o.lilacInk, t)!,
      sky: Color.lerp(sky, o.sky, t)!,
      skyDeep: Color.lerp(skyDeep, o.skyDeep, t)!,
      skyInk: Color.lerp(skyInk, o.skyInk, t)!,
      butter: Color.lerp(butter, o.butter, t)!,
      butterDeep: Color.lerp(butterDeep, o.butterDeep, t)!,
      butterInk: Color.lerp(butterInk, o.butterInk, t)!,
      accent: Color.lerp(accent, o.accent, t)!,
      accentSoft: Color.lerp(accentSoft, o.accentSoft, t)!,
      accentInk: Color.lerp(accentInk, o.accentInk, t)!,
      onAccent: Color.lerp(onAccent, o.onAccent, t)!,
      danger: Color.lerp(danger, o.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, o.dangerSoft, t)!,
    );
  }
}

extension SpContext on BuildContext {
  // Sin el `!`: un widget montado fuera de SpTheme (los tests de widgets
  // arman su propio MaterialApp) cae a los colores claros en vez de romper.
  SpColors get sp => Theme.of(this).extension<SpColors>() ?? SpColors.light;
}

/// Fondos de los avisos de abajo (SnackBar). Reemplazan a msgExito,
/// msgError y msgAdvertencia de theme.dart con colores del tema.
extension SpAvisos on SpColors {
  Color get msgExito => primaryStrong;
  Color get msgError => danger;
  Color get msgAdvertencia => accentInk;
}

/// Espacios (px lógicos).
class SpSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s6 = 24.0, s8 = 32.0;

  /// Margen lateral de todas las pantallas.
  static const screen = 16.0;
}

/// Radios.
class SpRadius {
  static const sm = 12.0; // baldosas de ícono
  static const md = 16.0; // botones, campos
  static const lg = 24.0; // tarjetas
  static const xl = 28.0; // héroe, accesos grandes
  static const full = 999.0;
}

/// Tonos pastel por animalito. Cada pieza "sp-tone" usa uno.
enum SpTone { mint, peach, lilac, sky, butter }

class SpToneColors {
  final Color fill, deep, ink, highlight;
  const SpToneColors(this.fill, this.deep, this.ink, this.highlight);
  static SpToneColors of(SpColors c, SpTone t) {
    switch (t) {
      case SpTone.mint:
        return SpToneColors(c.mint, c.mintDeep, c.primaryStrong, c.mintLight);
      case SpTone.peach:
        return SpToneColors(c.peach, c.peachDeep, c.peachInk, c.surface);
      case SpTone.lilac:
        return SpToneColors(c.lilac, c.lilacDeep, c.lilacInk, c.surface);
      case SpTone.sky:
        return SpToneColors(c.sky, c.skyDeep, c.skyInk, c.surface);
      case SpTone.butter:
        return SpToneColors(c.butter, c.butterDeep, c.butterInk, c.surface);
    }
  }
}

/// Recetas 3D. El volumen siempre son 3 capas:
///  1) brillo arriba (borde superior blanco translúcido),
///  2) canto sólido abajo (BoxShadow sin blur, offset (0, 4)),
///  3) sombra difusa suave.
/// Al presionar: bajar 4px (Transform.translate) y quitar las sombras.
class SpDeco {
  /// Blanco de los brillos 3D y de las huellitas sobre el verde. Es igual en
  /// claro y en oscuro (es luz, no fondo), por eso no está en SpColors.
  static const shine = Color(0xFFFFFFFF);

  static bool _dark(SpColors c) => c.bg.computeLuminance() < .2;

  /// Tarjeta blanca tipo plastilina.
  static BoxDecoration card(SpColors c, {double radius = SpRadius.lg}) =>
      BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: _dark(c) ? .06 : .9),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(color: c.edge, offset: const Offset(0, 4)),
          BoxShadow(
            color: (_dark(c) ? Colors.black : const Color(0xFF145038))
                .withValues(alpha: _dark(c) ? .6 : .22),
            offset: const Offset(0, 14),
            blurRadius: 28,
            spreadRadius: -10,
          ),
        ],
      );

  /// Botón principal / pestaña activa / héroe verde.
  static BoxDecoration primary(
    SpColors c, {
    double radius = SpRadius.md,
    bool gradient = false,
  }) => BoxDecoration(
    color: gradient ? null : c.primary,
    gradient: gradient
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.primaryLight, c.primary],
            stops: const [0, .65],
          )
        : null,
    borderRadius: BorderRadius.circular(radius),
    border: Border(
      top: BorderSide(color: Colors.white.withValues(alpha: .3), width: 2),
    ),
    boxShadow: [
      BoxShadow(color: c.primaryEdge, offset: const Offset(0, 4)),
      BoxShadow(
        color: c.primary.withValues(alpha: .45),
        offset: const Offset(0, 10),
        blurRadius: 18,
        spreadRadius: -6,
      ),
    ],
  );

  /// Botón secundario, chips, buscador.
  static BoxDecoration soft(SpColors c, {double radius = SpRadius.md}) =>
      BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: c.edge, offset: const Offset(0, 4))],
      );

  /// Baldosa pastel con degradado radial (mini cifras, accesos, fotos sin imagen).
  static BoxDecoration tone(
    SpColors c,
    SpTone t, {
    double radius = SpRadius.lg,
  }) {
    final k = SpToneColors.of(c, t);
    return BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-.45, -.7),
        radius: 1.3,
        colors: [k.highlight, k.fill, k.deep],
        stops: const [0, .45, 1.2],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: .7), width: 2),
      ),
      boxShadow: [
        BoxShadow(color: k.deep, offset: const Offset(0, 4)),
        BoxShadow(
          color: k.deep.withValues(alpha: .6),
          offset: const Offset(0, 12),
          blurRadius: 22,
          spreadRadius: -12,
        ),
      ],
    );
  }

  /// Campo de texto hundido.
  static BoxDecoration sunken(SpColors c, {double radius = SpRadius.md}) =>
      BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      );
}

/// Tipografía: Plus Jakarta Sans.
class SpText {
  static TextStyle _b(
    double size,
    double height,
    FontWeight w, [
    double ls = 0,
  ]) => TextStyle(
    fontFamily: spFontFamily,
    fontSize: size,
    height: height / size,
    fontWeight: w,
    letterSpacing: ls * size,
  );
  static final display = _b(28, 34, FontWeight.w800, -.02);
  static final screen = _b(26, 32, FontWeight.w800, -.02); // título de pantalla
  static final title = _b(22, 28, FontWeight.w700, -.01);
  static final stat = _b(24, 28, FontWeight.w800, -.02);
  static final section = _b(
    19,
    24,
    FontWeight.w800,
    -.01,
  ); // títulos con huellita
  static final headline = _b(17, 24, FontWeight.w600);
  static final body = _b(15, 22, FontWeight.w500);
  static final label = _b(13, 18, FontWeight.w600);
  static final caption = _b(12, 16, FontWeight.w500);
}

class SpTheme {
  static ThemeData _base(SpColors c, Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: c.primary, brightness: b)
        .copyWith(
          primary: c.primary,
          onPrimary: c.onPrimary,
          surface: c.surface,
          onSurface: c.ink,
          error: c.danger,
        ),
    fontFamily: spFontFamily,
    textTheme: ThemeData(brightness: b).textTheme.apply(
      fontFamily: spFontFamily,
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
    extensions: [c],
    // Avisos de abajo: el texto va siempre en el color del fondo, que
    // contrasta con los tres fondos de aviso (msgExito/msgError/
    // msgAdvertencia) en claro y en oscuro.
    // Campos de texto hundidos (`SpDeco.sunken`): gris menta claro dentro de
    // las tarjetas blancas, sin borde, y verde al escribir. Lo toman todos los
    // TextField que no pongan su propio estilo.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceSunken,
      hintStyle: TextStyle(
        fontFamily: spFontFamily,
        color: c.inkFaint,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpRadius.md),
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(
        fontFamily: spFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.bg,
      ),
      actionTextColor: c.bg,
    ),
  );
  static ThemeData light() => _base(SpColors.light, Brightness.light);
  static ThemeData dark() => _base(SpColors.dark, Brightness.dark);
}
