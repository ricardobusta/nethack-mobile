#ifndef NH_MOBILE_H
#define NH_MOBILE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum nm_event_type {
    NM_MESSAGE = 1, NM_WINDOW, NM_CLEAR, NM_DESTROY, NM_GLYPH, NM_CURSOR,
    NM_MENU_START, NM_MENU_ITEM, NM_MENU_END, NM_STATUS, NM_COMMAND,
    NM_PROMPT, NM_ENDED, NM_READY, NM_PHASE, NM_MENU_GLYPH, NM_CHARACTER, NM_EQUIPMENT, NM_ITEM, NM_MENU_CONTEXT, NM_OUTCOME
};
enum nm_phase { NM_STARTING, NM_PLAYING, NM_SUSPENDED, NM_POSTMORTEM, NM_FINISHED, NM_ERROR };
enum nm_input_type { NM_KEY = 1, NM_POSITION, NM_TEXT, NM_MENU, NM_EXTENDED };
/* Additive payloads (v = values):
 * PHASE: v[0] phase, v[1] initial outcome, text initial cause.
 * OUTCOME: v[0] normalized upstream game_end_types, text final cause.
 * CHARACTER: text known identity fields; EQUIPMENT: v[0]=-1 resets, else
 *   v[2] appearance tile, v[3] quantity, v[4] equipped; text doname().
 * MENU_GLYPH: v[0] window, v[1] index, v[2] tile, v[3] tty character.
 * ITEM: v[0] window, v[1] index, v[2..4] as equipment; text doname().
 * MENU_CONTEXT: v[0] window, v[1] inventory=1/actions=2; item v[2..4].
 * PROMPT kind 7 adds numeric entry; response TEXT carries a decimal long.
 * All payloads are copied, including strings. No engine pointers cross threads. */
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
void nm_interrupt(void);
void nm_stop(void);
int nm_running(void);
#ifdef __cplusplus
}
#endif
#endif
