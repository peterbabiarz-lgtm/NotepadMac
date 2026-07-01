#import "NMTest.h"
#import "DiffEngine.h"

// End-to-end: these actually invoke /usr/bin/diff (always present on macOS) and
// assert that the normal-diff output is classified into the right hunk types.

static void test_identical_no_hunks(void) {
    NM_EXPECT_EQ_INT([DiffEngine diffLeft:@"a\nb\nc\n" right:@"a\nb\nc\n"].count, 0);
}

static void test_added_line(void) {
    NSArray<DiffHunk *> *h = [DiffEngine diffLeft:@"a\nb\n" right:@"a\nb\nc\n"];
    NM_EXPECT_EQ_INT(h.count, 1);
    NM_EXPECT_EQ_INT(h[0].type, DiffHunkTypeAdded);
}

static void test_deleted_line(void) {
    NSArray<DiffHunk *> *h = [DiffEngine diffLeft:@"a\nb\nc\n" right:@"a\nc\n"];
    NM_EXPECT_EQ_INT(h.count, 1);
    NM_EXPECT_EQ_INT(h[0].type, DiffHunkTypeDeleted);
}

static void test_changed_line(void) {
    NSArray<DiffHunk *> *h = [DiffEngine diffLeft:@"a\nb\nc\n" right:@"a\nB\nc\n"];
    NM_EXPECT_EQ_INT(h.count, 1);
    NM_EXPECT_EQ_INT(h[0].type, DiffHunkTypeChanged);
}

void runDiffEngineTests(void) {
    NM_RUN(test_identical_no_hunks);
    NM_RUN(test_added_line);
    NM_RUN(test_deleted_line);
    NM_RUN(test_changed_line);
}
