#include "mobile.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int first[256], commands = 0, maps = 0, restored = 0, ended = 0;
    for (int i = 0; i < 256; ++i) first[i] = -1;
    if (!nm_start(argv[1], "MobileTest")) return 3;
    time_t deadline = time(NULL) + 60;
    while (time(NULL) < deadline) {
        nm_event e;
        if (!nm_poll(&e)) { usleep(1000); continue; }
        if (e.type == NM_MESSAGE) fprintf(stderr, "engine: %s\n", e.text);
        if (e.type == NM_GLYPH) ++maps;
        if (e.type == NM_MENU_START) first[e.values[0]] = -1;
        if (e.type == NM_MENU_ITEM && e.values[3] && first[e.values[0]] < 0) first[e.values[0]] = e.values[1];
        if (e.type == NM_PROMPT) {
            nm_input input = {0}; input.request = e.request; input.type = NM_KEY; input.key = ' ';
            switch (e.values[0]) {
            case 0:
                ++commands;
                if (commands == 1) input.key = 'i';
                else if (commands == 2) input.key = '#';
                else if (commands == 3) input.key = 's';
                else if (commands == 4) { nm_suspend(); continue; }
                else if (commands == 5) input.key = 's';
                else { input.key = '#'; }
                break;
            case 2:
                input.key = strchr(e.text, '?') && strstr(e.text, "quit") ? 'y' : (int)e.values[1];
                if (strstr(e.text, "Recover")) input.key = 'r';
                if (!input.key) input.key = 'n';
                break;
            case 3: input.type = NM_TEXT; snprintf(input.text, sizeof input.text, "MobileTest"); break;
            case 4:
                input.type = NM_MENU;
                if (first[e.values[2]] >= 0) snprintf(input.text, sizeof input.text, "%d:-1", first[e.values[2]]);
                break;
            case 5:
                input.type = NM_EXTENDED;
                snprintf(input.text, sizeof input.text, "%s", commands >= 6 ? "quit" : "version");
                break;
            }
            nm_input stale = input; stale.request += 100000;
            if (nm_respond(&stale)) { fprintf(stderr, "Accepted stale input\n"); nm_stop(); return 4; }
            if (!nm_respond(&input)) { fprintf(stderr, "Rejected valid input\n"); nm_stop(); return 5; }
        }
        if (e.type == NM_ENDED) {
            ++ended;
            if (!restored) {
                restored = 1;
                if (!nm_start(argv[1], "MobileTest")) return 6;
            } else {
                nm_stop();
                int success = maps > 100 && commands >= 6;
                printf("Native smoke: %d map events, %d command boundaries, %d sessions; %s.\n", maps, commands, ended, success ? "passed" : "FAILED");
                return success ? 0 : 7;
            }
        }
    }
    fprintf(stderr, "Native smoke timed out\n"); nm_stop(); return 8;
}
