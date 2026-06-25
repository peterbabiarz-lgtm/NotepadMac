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

## Lizenz

MIT
