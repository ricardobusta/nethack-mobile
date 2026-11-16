/* NetHack Mobile, 2026. Distributed under the NGPL; see LICENSE. */
#include "hack.h"
#include "func_tab.h"
#include "dlb.h"
#include "mobile.h"
#include <pthread.h>
#include <setjmp.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

int nhmain(int, char **);
typedef void (*shim_callback_t)(const char *, void *, const char *, ...);
void shim_graphics_set_callback(shim_callback_t);
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static pthread_t worker;
static int running, joinable, stopping, suspending, answered, interrupted, suspended_saved;
static uint64_t sequence, pending;
static nm_input answer;
static char game_directory[4096], sysconf_file[4096], player_name[64];
static jmp_buf termination;
typedef struct event_node { nm_event event; struct event_node *next; } event_node;
static event_node *head, *tail;
static int window_type[256], next_window;
typedef struct menu_entry { anything id; int selectable; } menu_entry;
static menu_entry *menus[256];
static int menu_count[256], menu_capacity[256];
static char status_names[MAXBLSTATS][64];
static int status_enabled[MAXBLSTATS];

/* Terminal facilities have no role in the embedded mobile window port. */
void intron(void) {}
void introff(void) {}
void check_linux_console(void) {}
void init_linux_cons(void) {}
int dosuspend(void) { nm_suspend(); return ECMD_OK; }

const char *nm_game_directory(void) { return game_directory; }
const char *nm_sysconf_file(void) { return sysconf_file; }

void nm_engine_exit(int status) {
    /* Only compiled engine code calls this, on its own worker thread. */
    longjmp(termination, status + 1);
}

static void push(nm_event e) {
    event_node *node = calloc(1, sizeof *node);
    if (!node) nm_engine_exit(EXIT_FAILURE);
    node->event = e;
    pthread_mutex_lock(&mutex);
    if (tail) tail->next = node; else head = node;
    tail = node;
    pthread_cond_broadcast(&condition);
    pthread_mutex_unlock(&mutex);
}

int nm_poll(nm_event *e) {
    pthread_mutex_lock(&mutex);
    event_node *node = head;
    if (node) {
        *e = node->event;
        head = node->next;
        if (!head) tail = NULL;
        free(node);
    }
    pthread_mutex_unlock(&mutex);
    return node != NULL;
}

static nm_event event(int type, const char *text) {
    nm_event e = {0}; e.type = type;
    if (text) snprintf(e.text, sizeof e.text, "%s", text);
    return e;
}

void error(const char *format, ...) {
    nm_event e = event(NM_MESSAGE, NULL);
    va_list args; va_start(args, format);
    vsnprintf(e.text, sizeof e.text, format, args); va_end(args);
    push(e);
    nh_terminate(EXIT_FAILURE);
}

static nm_input request(const char *kind, const char *prompt, const char *choices, int how, int window) {
    nm_event e = event(NM_PROMPT, prompt);
    e.values[0] = !strcmp(kind, "command") ? 0 : !strcmp(kind, "key") ? 1 :
                  !strcmp(kind, "yesno") ? 2 : !strcmp(kind, "text") ? 3 :
                  !strcmp(kind, "menu") ? 4 : !strcmp(kind, "position") ? 6 : 5;
    e.values[1] = how; e.values[2] = window;
    if (choices) snprintf(e.text + strlen(e.text) + 1, sizeof e.text - strlen(e.text) - 1, "%s", choices);
    pthread_mutex_lock(&mutex);
    pending = ++sequence; answered = 0; e.request = pending;
    pthread_mutex_unlock(&mutex);
    push(e);
    pthread_mutex_lock(&mutex);
    while (!answered && !stopping && !suspending) pthread_cond_wait(&condition, &mutex);
    int stop = stopping, suspend = suspending;
    nm_input result = answer;
    pending = 0; answered = 0;
    pthread_mutex_unlock(&mutex);
    if (stop || suspend) {
        if (program_state.something_worth_saving && !program_state.gameover && strcmp(kind, "command")) {
            nm_input cancel = {0}; cancel.type = NM_KEY; cancel.key = 27;
            return cancel;
        }
        /* Finish through NetHack's own hangup/save path, on the engine thread. */
        if (program_state.something_worth_saving && !program_state.gameover) {
            program_state.done_hup = 1;
            if (dosave0()) {
                suspended_saved = 1;
                clearlocks();
                nh_terminate(EXIT_SUCCESS);
            }
            push(event(NM_MESSAGE, "Save failed. Existing recovery files have been preserved."));
        }
        nh_terminate(stop ? EXIT_FAILURE : EXIT_SUCCESS);
    }
    return result;
}

int nm_respond(const nm_input *input) {
    pthread_mutex_lock(&mutex);
    int ok = running && pending && input->request == pending && !answered;
    if (ok) { answer = *input; answer.text[sizeof answer.text - 1] = 0; answered = 1; pthread_cond_broadcast(&condition); }
    pthread_mutex_unlock(&mutex);
    return ok;
}

static void callback(const char *name, void *ret, const char *fmt, ...) {
    va_list a; va_start(a, fmt);
    nm_event e = {0};
    if (!strcmp(name, "shim_init_nhwindows")) {
        iflags.window_inited = TRUE;
        iflags.wc_mouse_support = 1;
        flags.travelcmd = TRUE;
        flags.legacy = FALSE;
    } else if (!strcmp(name, "shim_get_nh_event")) {
        pthread_mutex_lock(&mutex); int cancel = interrupted || stopping || suspending; interrupted = 0; pthread_mutex_unlock(&mutex);
        if (cancel && program_state.something_worth_saving) {
            nomul(0);
            if (go.occupation) stop_occupation();
        }
    } else if (!strcmp(name, "shim_player_selection")) {
        genl_player_setup(80);
    } else if (!strcmp(name, "shim_askname")) {
        snprintf(svp.plname, sizeof svp.plname, "%s", player_name);
    } else if (!strcmp(name, "shim_create_nhwindow")) {
        int type = va_arg(a, int), w = ++next_window;
        if (w >= 256) nm_engine_exit(EXIT_FAILURE);
        window_type[w] = type; *((int *)ret) = w;
        e = event(NM_WINDOW, NULL); e.values[0] = w; e.values[1] = type; push(e);
    } else if (!strcmp(name, "shim_clear_nhwindow") || !strcmp(name, "shim_destroy_nhwindow")) {
        e = event(!strcmp(name, "shim_clear_nhwindow") ? NM_CLEAR : NM_DESTROY, NULL);
        e.values[0] = va_arg(a, int); push(e);
    } else if (!strcmp(name, "shim_putstr")) {
        int w = va_arg(a, int), attr = va_arg(a, int);
        e = event(NM_MESSAGE, va_arg(a, const char *)); e.values[0] = w; e.values[1] = attr; e.values[2] = window_type[w]; push(e);
    } else if (!strcmp(name, "shim_raw_print") || !strcmp(name, "shim_raw_print_bold")) {
        e = event(NM_MESSAGE, va_arg(a, const char *)); push(e);
    } else if (!strcmp(name, "shim_display_file")) {
        const char *filename = va_arg(a, const char *);
        dlb *file = dlb_fopen(filename, "r");
        if (file) {
            char line[BUFSZ]; int w = create_nhwindow(NHW_TEXT);
            while (dlb_fgets(line, sizeof line, file)) putstr(w, ATR_NONE, line);
            dlb_fclose(file); display_nhwindow(w, TRUE); destroy_nhwindow(w);
        }
    } else if (!strcmp(name, "shim_display_nhwindow")) {
        int w = va_arg(a, int), blocking = va_arg(a, int);
        if (blocking) (void)request("key", "Continue", NULL, 0, w);
    } else if (!strcmp(name, "shim_print_glyph")) {
        int w = va_arg(a, int), x = va_arg(a, int), y = va_arg(a, int);
        const glyph_info *g = va_arg(a, const glyph_info *);
        e = event(NM_GLYPH, NULL); e.values[0] = x; e.values[1] = y; e.values[2] = g->ttychar;
        e.values[3] = g->gm.sym.color; e.values[4] = g->gm.tileidx; e.values[5] = g->gm.glyphflags;
        e.values[6] = g->glyph; e.values[7] = w; push(e);
    } else if (!strcmp(name, "shim_curs")) {
        int w = va_arg(a, int), x = va_arg(a, int), y = va_arg(a, int);
        e = event(NM_CURSOR, NULL); e.values[0] = x; e.values[1] = y; e.values[2] = w; push(e);
    } else if (!strcmp(name, "shim_cliparound")) {
        int x = va_arg(a, int), y = va_arg(a, int);
        e = event(NM_CURSOR, NULL); e.values[0] = x; e.values[1] = y; e.values[3] = 1; push(e);
    } else if (!strcmp(name, "shim_start_menu")) {
        int w = va_arg(a, int); menu_count[w] = 0;
        e = event(NM_MENU_START, NULL); e.values[0] = w; push(e);
    } else if (!strcmp(name, "shim_add_menu")) {
        int w = va_arg(a, int); (void)va_arg(a, const glyph_info *);
        const anything *id = va_arg(a, const anything *);
        int ch = va_arg(a, int), group = va_arg(a, int), attr = va_arg(a, int), color = va_arg(a, int);
        const char *text = va_arg(a, const char *); unsigned itemflags = va_arg(a, unsigned);
        if (menu_count[w] == menu_capacity[w]) {
            menu_capacity[w] = menu_capacity[w] ? menu_capacity[w] * 2 : 32;
            menus[w] = realloc(menus[w], sizeof(menu_entry) * menu_capacity[w]);
            if (!menus[w]) nm_engine_exit(EXIT_FAILURE);
        }
        int i = menu_count[w]++; menus[w][i].id = *id; menus[w][i].selectable = id->a_void != NULL;
        e = event(NM_MENU_ITEM, text); e.values[0] = w; e.values[1] = i; e.values[2] = ch;
        e.values[3] = menus[w][i].selectable; e.values[4] = itemflags; e.values[5] = group;
        e.values[6] = attr; e.values[7] = color; push(e);
    } else if (!strcmp(name, "shim_end_menu")) {
        int w = va_arg(a, int); e = event(NM_MENU_END, va_arg(a, const char *)); e.values[0] = w; push(e);
    } else if (!strcmp(name, "shim_select_menu")) {
        int w = va_arg(a, int), how = va_arg(a, int);
        menu_item **selected = va_arg(a, menu_item **); *selected = NULL;
        nm_input input = request("menu", "Choose", NULL, how, w);
        int count = 0;
        if (input.key != 27 && how != PICK_NONE) {
            menu_item *items = (menu_item *)alloc(sizeof(menu_item) * (menu_count[w] + 1));
            char *cursor = input.text, *end;
            while (*cursor) {
                long i = strtol(cursor, &end, 10); if (end == cursor || *end != ':') break;
                cursor = end + 1; long quantity = strtol(cursor, &end, 10);
                if (end == cursor) break;
                if (i >= 0 && i < menu_count[w] && menus[w][i].selectable && (quantity == -1 || quantity > 0)) {
                    int duplicate = 0;
                    for (int j = 0; j < count; ++j) if (!memcmp(&items[j].item, &menus[w][i].id, sizeof(anything))) duplicate = 1;
                    if (!duplicate) { items[count].item = menus[w][i].id; items[count++].count = quantity; }
                }
                if (how == PICK_ONE || *end != ',') break;
                cursor = end + 1;
            }
            if (count) *selected = items; else free(items);
        }
        *((int *)ret) = input.key == 27 ? -1 : count;
    } else if (!strcmp(name, "shim_nhgetch") || !strcmp(name, "shim_nh_poskey")) {
        int position = !strcmp(name, "shim_nh_poskey");
        int command = position && iflags.in_parse && program_state.input_state == commandInp;
        if (command && program_state.something_worth_saving && !program_state.gameover && !gm.multi && !go.occupation) {
            save_currentstate();
        }
        e = event(NM_READY, NULL); e.values[0] = u.ux; e.values[1] = u.uy; e.values[2] = svm.moves; push(e);
        nm_input input = request(command ? "command" : position ? "position" : "key", command ? "Your move" : position ? "Choose a map target, direction, or key" : "Choose a key or direction", NULL, 0, 0);
        if (position && input.type == NM_POSITION && input.x > 0 && input.x < COLNO && input.y >= 0 && input.y < ROWNO) {
            coordxy *x = va_arg(a, coordxy *), *y = va_arg(a, coordxy *); int *mod = va_arg(a, int *);
            *x = input.x; *y = input.y; *mod = CLICK_1; *((int *)ret) = 0;
        } else *((int *)ret) = input.key ? input.key : 27;
    } else if (!strcmp(name, "shim_yn_function")) {
        const char *query = va_arg(a, const char *), *choices = va_arg(a, const char *); int def = va_arg(a, int);
        nm_input input = request("yesno", query, choices, def, 0);
        *((char *)ret) = input.key ? input.key : (def ? def : 27);
    } else if (!strcmp(name, "shim_getlin")) {
        const char *query = va_arg(a, const char *); char *buffer = va_arg(a, char *);
        nm_input input = request("text", query, NULL, 0, 0);
        if (input.key == 27) { buffer[0] = 27; buffer[1] = 0; }
        else snprintf(buffer, BUFSZ, "%.*s", BUFSZ - 1, input.text);
    } else if (!strcmp(name, "shim_get_ext_cmd")) {
        for (int i = 0; extcmdlist[i].ef_txt; ++i) {
            unsigned f = extcmdlist[i].flags;
            if ((f & (INTERNALCMD | CMD_NOT_AVAILABLE)) || ((f & WIZMODECMD) && !wizard)) continue;
            e = event(NM_COMMAND, extcmdlist[i].ef_txt); e.values[0] = i;
            snprintf(e.text + strlen(e.text) + 1, sizeof e.text - strlen(e.text) - 1, "%s", extcmdlist[i].ef_desc); push(e);
        }
        nm_input input = request("extended", "Commands", NULL, 0, 0);
        int chosen = -1;
        for (int i = 0; extcmdlist[i].ef_txt; ++i) if (!strcmp(extcmdlist[i].ef_txt, input.text)) {
            unsigned f = extcmdlist[i].flags;
            if (!(f & (INTERNALCMD | CMD_NOT_AVAILABLE)) && (!(f & WIZMODECMD) || wizard)) chosen = i;
        }
        *((int *)ret) = chosen;
    } else if (!strcmp(name, "shim_status_enablefield")) {
        int field = va_arg(a, int); const char *name_text = va_arg(a, const char *);
        (void)va_arg(a, const char *); int enabled = va_arg(a, int);
        if (field >= 0 && field < MAXBLSTATS) {
            snprintf(status_names[field], sizeof status_names[field], "%s", name_text ? name_text : "");
            status_enabled[field] = enabled;
            if (!enabled) { e = event(NM_STATUS, ""); e.values[0] = field; push(e); }
        }
    } else if (!strcmp(name, "shim_status_update")) {
        int field = va_arg(a, int); void *value = va_arg(a, void *);
        int change = va_arg(a, int), percent = va_arg(a, int), color = va_arg(a, int);
        if (field >= 0 && field != BL_CONDITION && field < MAXBLSTATS && status_enabled[field]) {
            e = event(NM_STATUS, "");
            const char *text = value ? (const char *)value : "";
            if (field == BL_GOLD && strrchr(text, ':')) text = strrchr(text, ':') + 1;
            if (*text) snprintf(e.text, sizeof e.text, "%s: %s", status_names[field], text);
            e.values[0] = field; e.values[1] = percent; e.values[2] = color; push(e);
        } else if (field == BL_CONDITION) {
            static const char *conditions[] = {"Bare-handed", "Blind", "Busy", "Confused", "Deaf", "Iron", "Flying", "Food poisoning", "Glowing hands", "Grabbed", "Hallucinating", "Held", "Ice", "Lava", "Levitating", "Paralyzed", "Riding", "Sleeping", "Sliming", "Slippery", "Petrifying", "Strangled", "Stunned", "Submerged", "Terminally ill", "Tethered", "Trapped", "Unconscious", "Wounded legs", "Holding"};
            unsigned long bits = value ? *(unsigned long *)value : 0;
            e = event(NM_STATUS, NULL); e.values[0] = field;
            for (int i = 0; i < 30; ++i) if (bits & (1UL << i)) {
                if (*e.text) strncat(e.text, ", ", sizeof e.text - strlen(e.text) - 1);
                strncat(e.text, conditions[i], sizeof e.text - strlen(e.text) - 1);
            }
            push(e);
        }
    } else if (!strcmp(name, "shim_message_menu")) {
        int letter = va_arg(a, int), how = va_arg(a, int); const char *text = va_arg(a, const char *);
        *((char *)ret) = request("key", text, NULL, how, 0).key;
    } else if (!strcmp(name, "shim_getmsghistory") || !strcmp(name, "shim_ctrl_nhwindow") || !strcmp(name, "shim_get_color_string")) {
        *((void **)ret) = NULL;
    }
    va_end(a);
}

static void *run_engine(void *unused) {
    int code = setjmp(termination);
    if (!code) {
        shim_graphics_set_callback(callback);
        char *argv[] = {"nethack-mobile", "-u", player_name, NULL};
        nhmain(3, argv);
    }
    for (int i = 0; i < 256; ++i) { free(menus[i]); menus[i] = NULL; menu_count[i] = menu_capacity[i] = 0; }
    pthread_mutex_lock(&mutex); running = 0; pending = 0; pthread_mutex_unlock(&mutex);
    nm_event e = event(NM_ENDED, NULL); e.values[0] = code ? code - 1 : 0; e.values[1] = suspended_saved; push(e);
    return NULL;
}

int nm_running(void) { pthread_mutex_lock(&mutex); int result = running; pthread_mutex_unlock(&mutex); return result; }
void nm_suspend(void) { pthread_mutex_lock(&mutex); suspending = 1; pthread_cond_broadcast(&condition); pthread_mutex_unlock(&mutex); }
void nm_interrupt(void) { pthread_mutex_lock(&mutex); interrupted = 1; pthread_mutex_unlock(&mutex); }
void nm_stop(void) {
    pthread_mutex_lock(&mutex); stopping = 1; pthread_cond_broadcast(&condition); pthread_mutex_unlock(&mutex);
    if (joinable) { pthread_join(worker, NULL); joinable = 0; }
}
int nm_start(const char *directory, const char *name) {
    if (nm_running() || !directory || !name || strlen(directory) >= sizeof game_directory - 2) return 0;
    if (joinable) { pthread_join(worker, NULL); joinable = 0; }
    snprintf(game_directory, sizeof game_directory, "%s/", directory);
    snprintf(sysconf_file, sizeof sysconf_file, "%s/sysconf", directory);
    const char *installation[] = {"perm", "record", "logfile", "xlogfile"};
    for (int i = 0; i < 4; ++i) {
        char path[4096]; snprintf(path, sizeof path, "%s/%s", directory, installation[i]);
        FILE *file = fopen(path, "ab");
        if (!file) return 0;
        fclose(file);
    }
    snprintf(player_name, sizeof player_name, "%s", name);
    next_window = 0; memset(window_type, 0, sizeof window_type);
    nm_event stale; while (nm_poll(&stale)) {}
    memset(status_names, 0, sizeof status_names); memset(status_enabled, 0, sizeof status_enabled);
    pthread_mutex_lock(&mutex); stopping = suspending = answered = interrupted = suspended_saved = 0; pending = 0; running = 1; pthread_mutex_unlock(&mutex);
    if (pthread_create(&worker, NULL, run_engine, NULL)) { pthread_mutex_lock(&mutex); running = 0; pthread_mutex_unlock(&mutex); return 0; }
    joinable = 1; return 1;
}
