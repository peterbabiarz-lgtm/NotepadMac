# NotepadMac — Makefile
# Builds a native macOS .app bundle using Scintilla + Lexilla from the
# sibling notepad-plus-plus-8.9.6.4 directory.

# ── Paths ────────────────────────────────────────────────────────────────────
SRC_DIR     := $(CURDIR)/Sources
NPP_DIR     := $(CURDIR)/../notepad-plus-plus-8.9.6.4
SCI_DIR     := $(NPP_DIR)/scintilla
LEX_DIR     := $(NPP_DIR)/lexilla
BUILD_DIR   := $(CURDIR)/build
APP_DIR     := $(BUILD_DIR)/NotepadMac.app
CONTENTS    := $(APP_DIR)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RES_DIR     := $(CONTENTS)/Resources

# ── Compiler ─────────────────────────────────────────────────────────────────
CXX         := clang++
CXXFLAGS    := -std=c++17 -O2 -fPIC \
               -I$(SCI_DIR)/include \
               -I$(SCI_DIR)/src \
               -I$(SCI_DIR)/cocoa \
               -I$(LEX_DIR)/include \
               -I$(LEX_DIR)/lexlib \
               -I$(LEX_DIR)/src \
               -I$(LEX_DIR)/access \
               -DSCI_LEXER \
               -DSTATIC_BUILD \
               -fobjc-arc

OBJCXXFLAGS := $(CXXFLAGS) -x objective-c++
WARNINGS    := -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
               -Wno-c99-designator

LDFLAGS     := -framework Cocoa \
               -framework AppKit \
               -framework Carbon \
               -framework IOKit \
               -framework QuartzCore

OBJ_DIR     := $(BUILD_DIR)/obj

# ── Source lists ─────────────────────────────────────────────────────────────

# Scintilla core (.cxx → compiled as C++)
SCI_SRCS := $(wildcard $(SCI_DIR)/src/*.cxx)

# Scintilla Cocoa (.mm → compiled as ObjC++)
SCI_COCOA_SRCS := \
    $(SCI_DIR)/cocoa/ScintillaCocoa.mm \
    $(SCI_DIR)/cocoa/PlatCocoa.mm \
    $(SCI_DIR)/cocoa/ScintillaView.mm \
    $(SCI_DIR)/cocoa/InfoBar.mm

# Lexilla: core + lexlib + all lexers (excluding Windows-only LexUser)
LEX_SRCS := \
    $(LEX_DIR)/src/Lexilla.cxx \
    $(wildcard $(LEX_DIR)/lexlib/*.cxx) \
    $(filter-out $(LEX_DIR)/lexers/LexUser.cxx, $(wildcard $(LEX_DIR)/lexers/*.cxx))

# Our app sources: .mm files + LexUserStub.cxx
APP_SRCS    := $(wildcard $(SRC_DIR)/*.mm)
APP_CXX_SRC := $(SRC_DIR)/LexUserStub.cxx

# ── Object files ─────────────────────────────────────────────────────────────
sci_obj     = $(OBJ_DIR)/sci/$(notdir $(1:.cxx=.o))
sci_coc_obj = $(OBJ_DIR)/sci_coc/$(notdir $(1:.mm=.o))
lex_obj     = $(OBJ_DIR)/lex/$(notdir $(1:.cxx=.o))
app_obj     = $(OBJ_DIR)/app/$(notdir $(1:.mm=.o))

SCI_OBJS     := $(foreach f,$(SCI_SRCS),$(call sci_obj,$(f)))
SCI_COC_OBJS := $(foreach f,$(SCI_COCOA_SRCS),$(call sci_coc_obj,$(f)))
LEX_OBJS     := $(foreach f,$(LEX_SRCS),$(call lex_obj,$(f)))
APP_OBJS     := $(foreach f,$(APP_SRCS),$(call app_obj,$(f)))
APP_CXX_OBJ  := $(OBJ_DIR)/app/LexUserStub.o

ALL_OBJS := $(SCI_OBJS) $(SCI_COC_OBJS) $(LEX_OBJS) $(APP_OBJS) $(APP_CXX_OBJ)

# ── Targets ──────────────────────────────────────────────────────────────────
.PHONY: all clean run

all: $(APP_DIR)/Contents/MacOS/NotepadMac $(CONTENTS)/Info.plist

# Always copy Info.plist so version changes take effect without a full relink
$(CONTENTS)/Info.plist: Resources/Info.plist | dirs
	cp $< $@

# Link
$(APP_DIR)/Contents/MacOS/NotepadMac: $(ALL_OBJS) | dirs
	@echo "[LINK] NotepadMac"
	$(CXX) $(ALL_OBJS) $(LDFLAGS) -o $@
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@echo ""
	@echo "✓ Built: $(APP_DIR)"
	@echo "  Run with:  open $(APP_DIR)"
	@echo "  Or:        make run"

run: all
	open $(APP_DIR)

# ── Compile rules ─────────────────────────────────────────────────────────────

# Scintilla core (C++)
$(OBJ_DIR)/sci/%.o: $(SCI_DIR)/src/%.cxx | dirs
	@echo "[CXX] $<"
	$(CXX) $(CXXFLAGS) $(WARNINGS) -c $< -o $@

# Scintilla Cocoa (ObjC++)
$(OBJ_DIR)/sci_coc/%.o: $(SCI_DIR)/cocoa/%.mm | dirs
	@echo "[OBJCXX] $<"
	$(CXX) $(OBJCXXFLAGS) $(WARNINGS) -c $< -o $@

# Lexilla (C++)
$(OBJ_DIR)/lex/%.o: $(LEX_DIR)/src/%.cxx | dirs
	@echo "[CXX] $<"
	$(CXX) $(CXXFLAGS) $(WARNINGS) -c $< -o $@

$(OBJ_DIR)/lex/%.o: $(LEX_DIR)/lexlib/%.cxx | dirs
	@echo "[CXX] $<"
	$(CXX) $(CXXFLAGS) $(WARNINGS) -c $< -o $@

$(OBJ_DIR)/lex/%.o: $(LEX_DIR)/lexers/%.cxx | dirs
	@echo "[CXX] $<"
	$(CXX) $(CXXFLAGS) $(WARNINGS) -c $< -o $@

# App (ObjC++)
$(OBJ_DIR)/app/%.o: $(SRC_DIR)/%.mm | dirs
	@echo "[OBJCXX] $<"
	$(CXX) $(OBJCXXFLAGS) $(WARNINGS) -I$(SRC_DIR) -c $< -o $@

# App C++ stubs (same include path as lexers)
$(OBJ_DIR)/app/LexUserStub.o: $(SRC_DIR)/LexUserStub.cxx | dirs
	@echo "[CXX] $<"
	$(CXX) $(CXXFLAGS) $(WARNINGS) -c $< -o $@

# ── Directory setup ───────────────────────────────────────────────────────────
dirs:
	@mkdir -p $(OBJ_DIR)/sci $(OBJ_DIR)/sci_coc $(OBJ_DIR)/lex $(OBJ_DIR)/app
	@mkdir -p $(MACOS_DIR) $(RES_DIR)

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned."
