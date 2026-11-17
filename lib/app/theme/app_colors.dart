// AppColors (the legacy constants) lives in app_palette.dart next to the
// palette it aliases. This file stays so existing imports keep working, and
// it also exports the palette so a screen can move to `context.palette`
// without touching its imports.
export 'app_palette.dart' show AppColors, AppPalette, PaletteX;
