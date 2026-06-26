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

## Lizenz

MIT
