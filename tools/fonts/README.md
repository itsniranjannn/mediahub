# Fonts

The app bundles four open-licensed (SIL OFL 1.1, no Reserved Font Name) families; see `docs/DESIGN.md` section 5 for
roles. Licences are in `assets/fonts/licenses/`, embedded in `lib/app/theme/font_licenses.dart` and registered on the
app's licences page.

| Family | Files in `assets/fonts/` | Source |
|---|---|---|
| Fraunces | `Fraunces-SemiBold.ttf`, `Fraunces-Bold.ttf` (static instances) | github.com/google/fonts `ofl/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf` |
| Poppins (Latin + Devanagari) | `Poppins-{Regular,Medium,SemiBold,Bold}.ttf` (unmodified) | github.com/google/fonts `ofl/poppins/` |
| DM Mono | `DMMono-{Regular,Medium}.ttf` (unmodified) | github.com/google/fonts `ofl/dmmono/` |
| Great Vibes (the author's signature only) | `GreatVibes-Regular.ttf` (unmodified, 447 KB) | github.com/google/fonts `ofl/greatvibes/` |

Licence files: `ofl/fraunces/OFL.txt` as `Fraunces-OFL.txt`, `ofl/poppins/OFL.txt` as `Poppins-OFL.txt`,
`ofl/dmmono/OFL.txt` as `DMMono-OFL.txt`, `ofl/greatvibes/OFL.txt` as `GreatVibes-OFL.txt`.

## Rebuilding the Fraunces instances

```sh
python -m venv ftvenv && ftvenv/bin/pip install fonttools   # Windows: ftvenv\Scripts\pip
fonttools varLib.instancer "Fraunces[SOFT,WONK,opsz,wght].ttf" wght=600 opsz=72 SOFT=50 WONK=0 --static -o Fraunces-SemiBold.ttf
fonttools varLib.instancer "Fraunces[SOFT,WONK,opsz,wght].ttf" wght=700 opsz=72 SOFT=50 WONK=0 --static -o Fraunces-Bold.ttf
```

Built on 2026-11-20 with fontTools 4.x. Sizes: Fraunces 73 KB each, Poppins 156-160 KB each, DM Mono 50 KB each;
about 0.9 MB in total (the previous Unbounded / Anek Devanagari / Atkinson Hyperlegible Next / Mukta set was 2.9 MB).
