// Stub for LexUser which requires windows.h and is Windows-only.
#include <cstddef>
#include <cstdint>
#include "ILexer.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "LexerModule.h"
using namespace Lexilla;

static Scintilla::ILexer5 *UserLexerFactory() { return nullptr; }
// Provide a null placeholder so Lexilla.cxx can link without LexUser.cxx
extern const LexerModule lmUserDefine(SCLEX_USER, UserLexerFactory, "user");
