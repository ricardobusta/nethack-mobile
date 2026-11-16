#ifndef NH_MOBILE_H
#define NH_MOBILE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum nm_event_type {
    NM_MESSAGE = 1, NM_WINDOW, NM_CLEAR, NM_DESTROY, NM_GLYPH, NM_CURSOR,
    NM_MENU_START, NM_MENU_ITEM, NM_MENU_END, NM_STATUS, NM_COMMAND,
    NM_PROMPT, NM_ENDED, NM_READY
};
enum nm_input_type { NM_KEY = 1, NM_POSITION, NM_TEXT, NM_MENU, NM_EXTENDED };
/* All payloads are copied, including strings. No engine pointers cross threads. */
typedef struct nm_event {
    int type;
    uint64_t request;
    int64_t values[8];
    char text[4096];
} nm_event;
typedef struct nm_input {
    uint64_t request;
    int type, key, x, y, mod;
    char text[4096];
} nm_input;
int nm_start(const char *directory, const char *name);
int nm_poll(nm_event *event);
int nm_respond(const nm_input *input);
void nm_suspend(void);
void nm_stop(void);
int nm_running(void);
#ifdef __cplusplus
}
#endif
#endif
