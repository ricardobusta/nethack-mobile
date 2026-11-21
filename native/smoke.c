#include "mobile.h"
#include "quantity.h"
#include <limits.h>
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
extern int total_tiles_used;

int main(int argc, char **argv) {
    long numeric; char maximum[64]; snprintf(maximum, sizeof maximum, "%ld", LONG_MAX);
    assert(nm_parse_quantity("0", &numeric) && numeric == 0);
    assert(nm_parse_quantity("42", &numeric) && numeric == 42);
    assert(nm_parse_quantity(maximum, &numeric) && numeric == LONG_MAX);
    assert(!nm_parse_quantity("999999999999999999999999", &numeric));
    assert(!nm_parse_quantity("-1", &numeric) && !nm_parse_quantity("2x", &numeric));
    assert(!nm_parse_quantity("", &numeric) && !nm_parse_quantity("1.5", &numeric));
    assert(nm_choice_key(27, "ynq", 'y') == 'q');
    assert(nm_choice_key(27, "yn", 'y') == 'n');
    assert(nm_choice_key(27, "abc", 'b') == 'b');
    assert(nm_choice_key(13, "yn", 'y') == 'y');
    assert(nm_choice_key('Y', "yn", 'n') == 'y');
    assert(nm_choice_key('N', "ynNaq", 'n') == 'N');
    assert(nm_choice_key('Y', NULL, 0) == 'Y');
    if (argc < 2 || argc > 3) return 2;
    if (argc == 3 && !strcmp(argv[2], "--retired")) {
        if (nm_start(argv[1], "MobileTest")) { nm_stop(); return 15; }
        puts("Retired postmortem directory refused: no dead restore."); return 0;
    }
    int first[256], commands = 0, maps = 0, restored = 0, ended = 0, tile_types = 0, tiles[4096] = {0};
    int restore_messages = 0, postmortem = 0, postmortem_prompts = 0, normalized_outcome = 0;
    int64_t latest_turn = 0, inventory_turn = 0;
    int level_identity_received = 0;
    int death_checkpoint = argc == 3 && !strcmp(argv[2], "--death-checkpoint");
    int death_test = death_checkpoint || (argc == 3 && !strcmp(argv[2], "--death"));
    int checkpoint = argc == 3 && !strcmp(argv[2], "--checkpoint");
    int save_failure = argc == 3 && !strcmp(argv[2], "--save-failure");
    int failure_reported = 0;
    char save_directory[4096]; snprintf(save_directory, sizeof save_directory, "%s/save", argv[1]);
    for (int i = 0; i < 256; ++i) first[i] = -1;
    if (!nm_start(argv[1], "MobileTest")) return 3;
    time_t deadline = time(NULL) + (death_test ? 120 : 60);
    while (time(NULL) < deadline) {
        nm_event e;
        if (!nm_poll(&e)) { usleep(1000); continue; }
        if (e.type == NM_MESSAGE && (getenv("NH_SMOKE_VERBOSE") || strstr(e.text, "error") || strstr(e.text, "Cannot") || strstr(e.text, "Program in disorder"))) fprintf(stderr, "engine: %s\n", e.text);
        if (e.type == NM_MESSAGE && strstr(e.text, "Restoring save file")) ++restore_messages;
        if (e.type == NM_MESSAGE && strstr(e.text, "Save failed.")) failure_reported = 1;
        if (e.type == NM_OUTCOME) {
            normalized_outcome = 1;
            if (!*e.text || (e.values[0] == 13 && strcmp(e.text, "quit"))) {
                fprintf(stderr, "Incorrect normalized outcome: %s\n", e.text); nm_stop(); return 16;
            }
        }
        if (e.type == NM_PHASE && e.values[0] == NM_POSTMORTEM) { postmortem = 1; nm_suspend(); }
        if (e.type == NM_READY) {
            latest_turn = e.values[2];
            if (e.values[5]) {
                assert(e.values[3] >= 0 && e.values[4] > 0);
                level_identity_received = 1;
            }
        }
        if (e.type == NM_GLYPH) {
            ++maps;
            if (e.values[4] < 0 || e.values[4] >= total_tiles_used || e.values[4] >= 4096) { fprintf(stderr, "Invalid tile mapping\n"); nm_stop(); return 9; }
            if (!tiles[e.values[4]]) { tiles[e.values[4]] = 1; ++tile_types; }
        }
        if (e.type == NM_MENU_START) first[e.values[0]] = -1;
        if (e.type == NM_MENU_ITEM && e.values[3] && (first[e.values[0]] < 0 || strstr(e.text, "No, just start play"))) first[e.values[0]] = e.values[1];
        if (e.type == NM_PROMPT) {

            if (postmortem) {
                nm_suspend(); usleep(10000); ++postmortem_prompts;
                if (death_checkpoint) {
                    puts("DEATH_CHECKPOINT_READY"); fflush(stdout);
                    for (;;) pause();
                }
            }
            nm_input input = {0}; input.request = e.request; input.type = NM_KEY; input.key = ' ';
            switch (e.values[0]) {
            case 0:
                assert(level_identity_received);
                ++commands;
                if (death_test) { input.key = (commands % 2) ? 'm' : '.'; break; }
                if (commands == 1) inventory_turn = latest_turn;
                else if (latest_turn != inventory_turn) {
                    fprintf(stderr, "Inventory browsing consumed a game turn\n"); nm_stop(); return 10;
                }
                if (checkpoint && commands == 3) {
                    puts("CHECKPOINT_READY"); fflush(stdout);
                    for (;;) pause();
                }
                if (commands <= 260) input.key = 'i';
                else if (commands == 261) input.key = '#';
                else if (commands == 262) input.key = 'i';
                else if (commands == 263) {
                    if (save_failure && chmod(save_directory, 0500)) { nm_stop(); return 12; }
                    nm_suspend(); continue;
                }
                else if (commands == 264) input.key = 'i';
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
                if ((commands > 0 && commands <= 260) || commands == 262 || commands == 264) input.key = 27;
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
            if (death_test) {
                nm_stop();
                int success = normalized_outcome && postmortem && postmortem_prompts > 0 && !e.values[1] && !nm_start(argv[1], "MobileTest");
                printf("Death disclosure background test: %d command inputs, %d prompts, no dead save; %s.\n", commands, postmortem_prompts, success ? "passed" : "FAILED");
                return success ? 0 : 14;
            }
            if (!restored) {
                if (save_failure) {
                    chmod(save_directory, 0700);
                    if (e.values[1] != 0 || !failure_reported) { fprintf(stderr, "Failed save was incorrectly confirmed or not reported\n"); nm_stop(); return 13; }
                } else if (e.values[1] != 1) { fprintf(stderr, "Session ended without the requested save\n"); nm_stop(); return 11; }
                restored = 1;
                if (!nm_start(argv[1], "MobileTest")) return 6;
            } else {
                nm_stop();
                int success = normalized_outcome && postmortem && postmortem_prompts > 0 && e.values[1] == 0 && maps > 100 && commands >= 265 && tile_types >= 5 && restore_messages >= 1;
                printf("Native smoke: %d map events, %d command boundaries, %d sessions; %s.\n", maps, commands, ended, success ? "passed" : "FAILED");
                return success ? 0 : 7;
            }
        }
    }
    fprintf(stderr, "Native smoke timed out\n"); nm_stop(); return 8;
}
