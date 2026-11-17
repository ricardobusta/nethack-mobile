#include "mobile.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
extern int total_tiles_used;

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3) return 2;
    int first[256], commands = 0, maps = 0, restored = 0, ended = 0, tile_types = 0, tiles[4096] = {0};
    int restore_messages = 0;
    int64_t latest_turn = 0, inventory_turn = 0;
    for (int i = 0; i < 256; ++i) first[i] = -1;
    if (!nm_start(argv[1], "MobileTest")) return 3;
    time_t deadline = time(NULL) + 60;
    while (time(NULL) < deadline) {
        nm_event e;
        if (!nm_poll(&e)) { usleep(1000); continue; }
        if (e.type == NM_MESSAGE && (getenv("NH_SMOKE_VERBOSE") || strstr(e.text, "error") || strstr(e.text, "Cannot") || strstr(e.text, "Program in disorder"))) fprintf(stderr, "engine: %s\n", e.text);
        if (e.type == NM_MESSAGE && strstr(e.text, "Restoring save file")) ++restore_messages;
        if (e.type == NM_READY) latest_turn = e.values[2];
        if (e.type == NM_GLYPH) {
            ++maps;
            if (e.values[4] < 0 || e.values[4] >= total_tiles_used || e.values[4] >= 4096) { fprintf(stderr, "Invalid tile mapping\n"); nm_stop(); return 9; }
            if (!tiles[e.values[4]]) { tiles[e.values[4]] = 1; ++tile_types; }
        }
        if (e.type == NM_MENU_START) first[e.values[0]] = -1;
        if (e.type == NM_MENU_ITEM && e.values[3] && (first[e.values[0]] < 0 || strstr(e.text, "No, just start play"))) first[e.values[0]] = e.values[1];
        if (e.type == NM_PROMPT) {
            nm_input input = {0}; input.request = e.request; input.type = NM_KEY; input.key = ' ';
            switch (e.values[0]) {
            case 0:
                ++commands;
                if (commands == 1) inventory_turn = latest_turn;
                else if (commands <= 261 && latest_turn != inventory_turn) {
                    fprintf(stderr, "Inventory browsing consumed a game turn\n"); nm_stop(); return 10;
                }
                if (argc == 3 && commands == 3) {
                    puts("CHECKPOINT_READY"); fflush(stdout);
                    for (;;) pause();
                }
                if (commands <= 260) input.key = 'i';
                else if (commands == 261) input.key = '#';
                else if (commands == 262) input.key = 's';
                else if (commands == 263) { nm_suspend(); continue; }
                else if (commands == 264) input.key = 's';
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
                /* Inventory is interactive in 5.0: selecting the first item can
                 * wield/apply it and consume turns. This stress test browses. */
                if (commands > 0 && commands <= 260) input.key = 27;
                else if (first[e.values[2]] >= 0) snprintf(input.text, sizeof input.text, "%d:-1", first[e.values[2]]);
                break;
            case 5:
                input.type = NM_EXTENDED;
                snprintf(input.text, sizeof input.text, "%s", commands >= 265 ? "quit" : "version");
                break;
            case 6: input.key = 27; break;
            }
            nm_input stale = input; stale.request += 100000;
            if (nm_respond(&stale)) { fprintf(stderr, "Accepted stale input\n"); nm_stop(); return 4; }
            if (!nm_respond(&input)) { fprintf(stderr, "Rejected valid input\n"); nm_stop(); return 5; }
        }
        if (e.type == NM_ENDED) {
            if (getenv("NH_SMOKE_VERBOSE")) fprintf(stderr, "Session ended: status=%lld saved=%lld commands=%d\n", e.values[0], e.values[1], commands);
            ++ended;
            if (!restored) {
                if (e.values[1] != 1) { fprintf(stderr, "Session ended without the requested save\n"); nm_stop(); return 11; }
                restored = 1;
                if (!nm_start(argv[1], "MobileTest")) return 6;
            } else {
                nm_stop();
                int success = maps > 100 && commands >= 265 && tile_types >= 5 && restore_messages >= 1;
                printf("Native smoke: %d map events, %d command boundaries, %d sessions; %s.\n", maps, commands, ended, success ? "passed" : "FAILED");
                return success ? 0 : 7;
            }
        }
    }
    fprintf(stderr, "Native smoke timed out\n"); nm_stop(); return 8;
}
