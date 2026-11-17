# Fonts

The app bundles five open-licensed (SIL OFL 1.1) families; see `docs/DESIGN.md` section 5 for roles.
Licences are in `assets/fonts/licenses/` and are registered on the app's licences page.

| Family | Files in `assets/fonts/` | Source |
|---|---|---|
| Unbounded | `Unbounded-SemiBold.ttf`, `Unbounded-Bold.ttf` (Latin subset) | github.com/googlefonts/unbounded `fonts/ttf/` |
| Anek Devanagari, width pinned to 112.5 | `AnekDevanagariWide-SemiBold.ttf`, `AnekDevanagariWide-Bold.ttf` (static instances) | github.com/google/fonts `ofl/anekdevanagari/AnekDevanagari[wdth,wght].ttf` |
| Atkinson Hyperlegible Next | `AtkinsonHyperlegibleNext-{Regular,Medium,SemiBold,Bold}.ttf` | github.com/googlefonts/atkinson-hyperlegible-next `fonts/ttf/` |
| Mukta | `Mukta-{Regular,Medium,SemiBold,Bold}.ttf` (Devanagari + ASCII subset) | github.com/google/fonts `ofl/mukta/` |
| DM Mono | `DMMono-{Regular,Medium}.ttf` | github.com/google/fonts `ofl/dmmono/` |

## Rebuilding the processed files

```sh
python -m venv ftvenv && ftvenv/bin/pip install fonttools brotli   # Windows: ftvenv\Scripts\pip
fonttools varLib.instancer "AnekDevanagari[wdth,wght].ttf" wdth=112.5 wght=600 -o AnekDevanagariWide-SemiBold.ttf
fonttools varLib.instancer "AnekDevanagari[wdth,wght].ttf" wdth=112.5 wght=700 -o AnekDevanagariWide-Bold.ttf
for f in Unbounded-SemiBold Unbounded-Bold; do
  pyftsubset $f.ttf --unicodes="U+0000-024F,U+2000-206F,U+20B9,U+2122,U+2190-2199,U+2212" --layout-features='*' --output-file=out/$f.ttf
done
for w in Regular Medium SemiBold Bold; do
  pyftsubset Mukta-$w.ttf --unicodes="U+0020-007E,U+00A0,U+0900-097F,U+1CD0-1CFF,U+200B-200D,U+20B9,U+25CC,U+A8E0-A8FF" --layout-features='*' --output-file=out/Mukta-$w.ttf
done
```

Built on 2026-11-17 with fontTools 4.68.0. Sizes: Anek 426 KB + 427 KB, Unbounded 199 KB + 203 KB, Mukta 327-349 KB each,
Atkinson 65-67 KB each, DM Mono 50 KB each; 2.9 MB in total.
