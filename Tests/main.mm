// Test runner entry point. Each suite is a plain function declared below and
// defined in its own *Tests.mm file. Exits non-zero if any check failed.
#import "NMTest.h"

int nm_checks = 0;
int nm_failed = 0;

extern void runLogParserTests(void);
extern void runConfigParserTests(void);
extern void runDocumentTests(void);
extern void runDiffEngineTests(void);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("NotepadMac unit tests\n");
        printf("LogParser\n");    runLogParserTests();
        printf("ConfigParser\n"); runConfigParserTests();
        printf("Document\n");     runDocumentTests();
        printf("DiffEngine\n");   runDiffEngineTests();

        printf("\n%d checks, %d failed\n", nm_checks, nm_failed);
        if (nm_failed == 0) printf("\xE2\x9C\x93 all tests passed\n");
        return nm_failed ? 1 : 0;
    }
}
