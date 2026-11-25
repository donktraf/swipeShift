# SwipeShift Design System (Etappe 1: Fundament)

Neues System unter `DS.*`. Das alte `SS`-Theme (utils/Theme.swift) bleibt bis zur Umstellung der Screens bestehen und wird abgeloest.

## Tokens
- **Farben** `DS.Color.*` (DSColor.swift): bg, surface, surface2, border, text, text2, muted, primary, onPrimary, primarySoft, primaryText, success/successSoft, warning/warningSoft, danger/dangerSoft. Alle dynamisch (hell/dunkel). Markenfarbe nur in `Brand` aendern. `DS.Tone` (primary/success/warning/danger/neutral) liefert foreground + soft.
- **Schrift** Plus Jakarta Sans (OFL, `Resources/Fonts/`, statische Gewichte 400/500/600/700/800, registriert via `UIAppFonts` in `Info.plist`). Nutzung: `.dsFont(.display|.title|.headline|.body|.callout|.caption|.sectionLabel)`. Sonderfaelle: `DS.Font.make(size, weight, relativeTo:)`. Skaliert mit Dynamic Type, Fallback auf Systemschrift. Pruefen: `DS.Font.isBrandFontAvailable`.
- **Abstaende** `DS.Spacing`: 4/8/12/16/20/24/32 (xxs...xxl), `screenEdge` 20, `inset` 16.
- **Radien** `DS.Radius`: control 12, button 14, card 16, tile 16, sheet 24, pill 999.
- **Schatten** `.dsCardShadow()`. **Motion** `DS.Motion.standard/.snappy`, `.dsAnimation(_, value:)` (respektiert Reduce Motion). **Haptik** `DS.Haptics.light/medium/selection/success/warning`.

## Komponenten (jeweils mit #Preview hell+dunkel)
| Datei | Inhalt |
|---|---|
| DSLayout | `DSSection`, `DSRow`, `DSToggleRow`, `DSIconTile`, `DSCard`, `DSTile`, `DSDivider` |
| DSButtons | `.buttonStyle(.ds(.primary/.secondary/.soft/.destructiveSoft, size: .large/.medium))`, `.dsPressable`, `DSIconButton` |
| DSBadge | `DSBadge(_, .today/.upcoming/.completed/.cancelled/.draft/.published/.inProgress/.tone(_))`, `DSChip`, `DSAvatar` |
| DSFields | `DSTextField`, `DSTextEditor` (Zeichenlimit optional), `DSStepper` |
| DSFeedback | `DSProgressSteps`, `.dsSkeleton(isLoading)`, `DSSkeletonBlock`, `DSEmptyState` |

## Regeln
1. **Flach** fuer Formulare und Einstellungen: `DSSection` (Label) + `DSRow`/Felder mit Trennlinien, keine Box.
2. **Karte** (`DSCard`) nur fuer antippbare Inhalte (Job, Bewerber, Chat).
3. **Kachel** (`DSTile`) fuer Kennzahlen.
4. Abstaende nur aus dem 4er-Raster (`DS.Spacing`), Bildschirmrand 20.
5. In neuen Views keine hartcodierten Farben, Schriftgroessen, Radien oder Abstaende; immer Tokens.
6. Interaktive Elemente min. 44pt; Animationen ueber `DS.Motion`/`dsAnimation`; Haptik ueber `DS.Haptics`.
7. Hintergrund neuer Screens: `.dsBackground()` (nicht `SS.background()`).
