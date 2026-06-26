# NotepadMac

Ein nativer macOS Text-Editor inspiriert von [Notepad++](https://notepad-plus-plus.org/), gebaut auf [Scintilla](https://www.scintilla.org/) und [Lexilla](https://www.scintilla.org/Lexilla.html).

## Features

- Multi-Tab-Editing
- Syntax-Highlighting für 50+ Sprachen (C/C++, Python, JavaScript, Rust, Go, Bash, SQL, HTML, CSS, JSON, YAML, …)
- Automatischer Dark Mode
- Find & Replace
- Gehe zu Zeile (⌘G)
- Schriftgröße anpassen (⌘+ / ⌘− / ⌘0)
- Word Wrap umschalten
- Zuletzt geöffnete Dateien
- Session-Wiederherstellung beim nächsten Start
- Statusleiste mit Zeile, Spalte, Encoding und Sprache
- **Auto-Save** beim Fokusverlust (nur bereits gespeicherte Dateien)
- **Dateivergleich** (Ansicht → Dateien vergleichen…) – vertikale Split-Ansicht mit farbiger Diff-Hervorhebung (grün = hinzugefügt, rot = gelöscht, orange = geändert) und synchronem Scrollen
- **Brace-Matching** – passende Klammern `{[()]}` werden beim Cursor farbig hervorgehoben (blau = gefunden, rot = kein Match)
- **Linienlängen-Guide** (Ansicht → Edge Column at 80) – vertikale Orientierungslinie bei Spalte 80, umschaltbar
- **EOL-Konvertierung** (Format → Line Endings) – zwischen Unix (LF), Windows (CRLF) und Classic Mac (CR) konvertieren; aktueller Modus in der Statusleiste sichtbar
- **Tab-Close-Buttons** – jeder Tab hat ein × direkt auf dem Tab zum sofortigen Schließen; × erscheint immer auf dem aktiven Tab und bei Hover auf inaktiven Tabs
- **Datei-Drag-and-Drop** – Dateien aus dem Finder direkt ins Editor-Fenster ziehen zum Öffnen
- **Erweiterte Suche & Ersetzen** – Inline-Suchleiste (⌘F) mit Regex, Ganzwort- und Groß-/Kleinschreibung-Optionen, Einzelersetzung, Treffer-Zähler und Live-Hervorhebung aller Treffer
- **Automatische/umschaltbare Zeichenkodierung** – BOM-Erkennung (UTF-8/16/32) plus Foundation-Heuristik beim Öffnen; per Statusleisten-Button oder Format-Menü umschaltbar (Konvertieren / Neu laden): UTF-8, UTF-8 BOM, UTF-16 LE/BE, ISO Latin-1, Windows-1250/1251/1252, Shift-JIS, EUC-JP, Mac Roman
- **Code-Faltung** (Ansicht → Falten umschalten ⌘. / Alle falten / Alle entfalten) – auch per Klick auf den Faltungsrand
- **Spaltenmodus / Blockauswahl** (Ansicht → Spaltenmodus ⌥⌘B) – rechteckige Selektion und spaltenweises Bearbeiten; alternativ per ⌥-Ziehen

## Installation

1. Neueste Version unter [Releases](https://github.com/peterbabiarz-lgtm/NotepadMac/releases) herunterladen
2. ZIP entpacken und `NotepadMac.app` nach `/Applications` ziehen
3. Beim ersten Start: **Rechtsklick → Öffnen** (Gatekeeper-Warnung, da nicht notarisiert)

**Voraussetzungen:** macOS 13 Ventura oder neuer, Apple Silicon (ARM64)

## Als Standard-Editor setzen

Rechtsklick auf eine Textdatei im Finder → **Informationen** → **Öffnen mit** → NotepadMac auswählen → **„Alle ändern…"**

Oder mit `duti` für alle Textdateien auf einmal:

```bash
brew install duti
duti -s com.notepadmac.app public.plain-text all
duti -s com.notepadmac.app public.source-code all
```

## Selbst bauen

Voraussetzungen: Xcode Command Line Tools, der Notepad++-Quellcode im Nachbarverzeichnis (für Scintilla/Lexilla):

```bash
# Notepad++-Quellcode herunterladen (enthält Scintilla + Lexilla)
curl -L https://github.com/notepad-plus-plus/notepad-plus-plus/archive/refs/tags/v8.9.6.4.tar.gz | tar xz

# NotepadMac bauen
git clone https://github.com/peterbabiarz-lgtm/NotepadMac
cd NotepadMac
make
open build/NotepadMac.app
```

## Entstehungsgeschichte

Dieses Projekt wurde vollständig von **[Claude](https://claude.ai) (Anthropic)** — konkret dem Modell **Claude Sonnet 4.6** — in einer einzigen Konversation generiert.

### Ausgangspunkt

Der Nutzer fragte, ob der Quellcode von Notepad++ 8.9.6.4 auf macOS portiert werden könnte. Claude schlug drei Optionen vor:

1. Win32-Code direkt portieren (sehr aufwändig)
2. Cross-Platform-Framework (Qt, wxWidgets)
3. Neue native macOS-App mit Scintilla als Editor-Kern

Der Nutzer wählte **Option 3**.

### Was Claude generiert hat

- Die gesamte App-Architektur (AppDelegate, WindowController, EditorViewController, Document, FindReplacePanel, LexerManager, ThemeManager)
- Das Makefile zum Bauen von Scintilla, Lexilla und der App aus dem Quellcode
- `LexUserStub.cxx` als Ersatz für das Windows-only `LexUser.cxx`
- Die `Info.plist` mit 40+ deklarierten Dateitypen

### Aufgetretene Probleme und Lösungen

Im Verlauf der Konversation wurden mehrere nicht-triviale Probleme diagnostiziert und behoben:

| Problem | Ursache | Lösung |
|---------|---------|--------|
| Keine Menüpunkte sichtbar | `NSApplicationMain` ohne NIB instanziiert AppDelegate nicht | Manuelles App-Setup in `main.mm` |
| Crash bei File › New | Scintilla feuert `SCN_UPDATEUI` synchron während `drawRect:`, UI-Mutation re-entrant | `dispatch_async` auf Main Queue |
| Crash bei File › New (2) | `NSTabViewItem.viewController` ist nil wenn `.view` direkt gesetzt wird → `setLabel:nil` → `NSCalendarDate`-Exception | EVC als `.identifier` statt `.viewController` speichern |
| `lmUserDefine` Linker-Fehler | `LexUser.cxx` benötigt `windows.h` | Stub mit `extern const LexerModule` |
| Header-Reihenfolge | `Lexilla.h` benötigt `ILexer.h` zuvor | Include-Reihenfolge korrigiert |

### Code-Review durch Opus

Nach der Implementierung wurde ein automatisches Code-Review durchgeführt, das 9 Bugs identifizierte:

- Crash durch `NSNotFound`-Index in `closeTabAtIndex:`
- O(n)-Puffer-Kopie bei jedem Tastendruck (lazy gelöst)
- `SCN_UPDATEUI` feuerte bei jeder Cursorbewegung
- Encoding-Fehler öffnete Dateien lautlos leer
- Statusleiste zeigte hardcodiert „UTF-8"
- `saveSession` via `performSelector:` auf privater Methode
- Unsafe Casts ohne Typprüfung
- `hex()` ignorierte Rückgabewert von `scanHexInt:`
- Finder-Fehler beim Öffnen wurde verschluckt

Alle 9 wurden in v1.1.0 behoben.

### Code-Review v1.4.1

Ein zweites Code-Review (13 Findings) wurde in v1.4.1 vollständig behoben:

| # | Datei | Problem | Schwere |
|---|-------|---------|---------|
| 1 | `SearchEngine.mm` | `usedEncoding:nil` → Crash (EXC_BAD_ACCESS auf macOS ≤12) | Kritisch |
| 2 | `WindowController.mm` | Verschachtelte `runModal`-Aufrufe beim Schließen ungespeicherter Untitled-Tabs | Kritisch |
| 3 | `DiffEngine.mm` | Deadlock bei Diff-Output >64 KB (Pipe-Puffer-Overflow) | Hoch |
| 4 | `DiffEngine.mm` | Race Condition: fixe Temp-Pfade bei parallelen Vergleichen | Hoch |
| 5 | `LexerManager.mm` | Dangling `const char*` aus `UTF8String` einer autoreleased NSString | Hoch |
| 6 | `Document.mm` | `allowLossyConversion:YES` korrumpierte Unicode-Zeichen lautlos beim Speichern | Hoch |
| 7 | `DiffEngine.mm` | `launchAndReturnError:` Fehler wurde ignoriert → stille Fehler | Mittel |
| 8 | `DiffEngine.mm` | Temporäre Diff-Dateien wurden nie gelöscht (Disk-Leak) | Mittel |
| 9 | `EditorViewController.mm` | `goToLine:` setzte First Responder auf Container statt inneren Editor-View | Mittel |
| 10 | `EditorViewController.mm` | `colorUsingColorSpace:` Nil-Dereference ohne nil-Guard | Mittel |
| 11 | `WindowController.mm` | Ungeprüfter Cast auf Tab-Identifier in `updateCurrentTabTitle`/`saveSession` | Mittel |
| 12 | `WindowController.mm` | Notification-Observer `NMOpenFileAtLine` wurde in `dealloc` nie entfernt | Mittel |
| 13 | `CompareViewController.mm` | Gleiche `colorUsingColorSpace:` Nil-Dereference wie #10 | Mittel |

### Code-Review v1.6.1

Ein drittes Code-Review (5 Findings) wurde in v1.6.1 vollständig behoben:

| # | Datei | Problem | Schwere |
|---|-------|---------|---------|
| 1 | `WindowController.mm` | `autoSaveAll` aktualisierte `item.label` ohne `syncTabBar` → Tab-Titel zeigte nach dem Auto-Save weiterhin das •-Symbol | Hoch |
| 2 | `TabBarView.mm` | `NSTrackingActiveInKeyWindow` → Hover-Effekt fror ein wenn das Fenster den Fokus verlor | Mittel |
| 3 | `WindowController.mm` | `syncTabBar` wurde bei jedem Tab-Klick doppelt aufgerufen (NSTabView-Delegate feuert synchron) | Mittel |
| 4 | `WindowController.mm` | `syncTabBar` speicherte `NSNotFound` (= NSIntegerMax) als `selectedIndex` wenn kein Tab selektiert war → kein Tab erschien visuell ausgewählt | Niedrig |
| 5 | `TabBarView.mm` | `_hoveredIndex` wurde nach dem Schließen eines Tabs nicht zurückgesetzt → Hover-Highlight auf nicht mehr existierendem Tab | Niedrig |

### Code-Review v1.7.1

Ein viertes Code-Review (12 Findings) über die neu hinzugefügten Features Zeichenkodierung (v1.7.0), Code-Faltung und Spaltenmodus wurde in v1.7.1 vollständig behoben:

| # | Datei | Problem | Schwere |
|---|-------|---------|---------|
| 1 | `WindowController.mm` | `validateMenuItem:` rief C++ `directCall` durch nil-`evc` auf (kein Tab offen) → Crash beim Öffnen des View-Menüs | Kritisch |
| 2 | `Document.mm` | UTF-16/UTF-32-BOM wurde beim Speichern stillschweigend gelöscht – nur UTF-8-BOM wurde korrekt zurückgeschrieben | Hoch |
| 3 | `Document.mm` | BOM-Datei mit ungültigem Body öffnete lautlos als leeres Dokument ohne Fehlermeldung statt Fallback auf andere Encodings | Hoch |
| 4 | `Document.mm` | `saveToURL:` nutzte `allowLossyConversion:YES` im UTF-8-BOM-Pfad, `NO` im Non-BOM-Pfad → BOM-Dateien korrumpierten Zeichen lautlos | Hoch |
| 5 | `WindowController.mm` | `menuConvertToEncoding:` testete `evc.document.content` (veralteter Snapshot) statt `[evc currentContent]` (Live-Text) → falsche Validierung bei ungespeicherten Änderungen | Mittel |
| 6 | `EditorViewController.mm` | `columnMode`-Getter erkannte `SC_SEL_THIN` (3) nicht → Checkmark verschwand nach kollabierter Rechteck-Selektion, Toggle invertierte statt abzuschalten | Mittel |
| 7 | `Document.mm` | Foundation-Heuristik las Datei ein zweites Mal vom Disk (TOCTOU) – ersetzt durch `+stringEncodingForData:` auf bereits geladenem NSData | Mittel |
| 8 | `Document.mm` | `saveToURL:` mutierte `_encoding`/`_hasBOM` beim Encoding-Fallback, aber `saveDocument:` rief nie `updateStatusBar` auf → Encoding-Label in Statusleiste veraltert | Mittel |
| 9 | `WindowController.mm` | `showEncodingMenu:` griff ohne nil-Guard auf `evc.document` zu → falscher Menüzustand ohne offenen Tab | Mittel |
| 10 | `WindowController.mm` | `menuReloadWithEncoding:` rief nach erfolgreichem Reload nie `updateCurrentTabTitle` auf → •-Symbol blieb im Tab-Titel | Niedrig |
| 11 | `WindowController.mm` | `saveDocument:` rief nach erfolgreichem Speichern nie `updateStatusBar` auf → Encoding-Label nach manuellem Encoding-Wechsel + Speichern veraltet | Niedrig |
| 12 | `WindowController.mm` | `validateMenuItem:` setzte `item.state` für `menuConvertToEncoding:` und `menuToggleColumnMode:` vor dem nil-Check auf `evc` | Niedrig |

### Refactoring v1.7.2

Wartbarkeits- und Performance-Verbesserung der Encoding-Funktionen (minimale, gezielte Änderungen):

| Bereich | Änderung |
|---------|----------|
| Wartbarkeit | Encoding-Menü-Aufbau (4× dupliziert) in einen gemeinsamen Helfer `addEncodingItemsToMenu:action:` zusammengefasst; Checkmark/Enable-Status wird zentral über `validateMenuItem:` aufgelöst statt an mehreren Stellen dupliziert |
| Performance | `menuConvertToEncoding:` nutzt `canBeConvertedToEncoding:` statt eine vollständige `NSData`-Kopie des Dokuments zu allokieren und sofort zu verwerfen (spürbar bei großen Dateien) |

## Lizenz

MIT
