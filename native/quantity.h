#ifndef NM_QUANTITY_H
#define NM_QUANTITY_H
#include <errno.h>
#include <stdlib.h>
#include <string.h>
/* PC numeric answers are nonnegative decimal longs; zero means No. */
static int nm_parse_quantity(const char *text, long *result) {
    if (!text || !*text) return 0;
    for (const char *p = text; *p; ++p) if (*p < '0' || *p > '9') return 0;
    char *end;
    errno = 0;
    long value = strtol(text, &end, 10);
    if (errno || *end || value < 0) return 0;
    *result = value;
    return 1;
}
/* Match the PC yes/no prompt's Escape/default and case behavior. */
static int nm_choice_key(int key, const char *choices, int def) {
    if (!choices || !*choices) return key;
    int preserve_case = 0;
    for (const char *p = choices; *p; ++p)
        if (*p >= 'A' && *p <= 'Z') preserve_case = 1;
    if (!preserve_case && key >= 'A' && key <= 'Z') key += 'a' - 'A';
    if (key == 27) return strchr(choices, 'q') ? 'q' : strchr(choices, 'n') ? 'n' : def;
    if (key == 13 || key == 10 || key == ' ') return def;
    return key;
}
#endif
