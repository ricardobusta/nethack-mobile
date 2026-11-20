/* Host smoke fixture only; never compiled into the distributed engine bridge. */
static void verify_private_item_payload(void) {
    struct obj fixture = {0};
    fixture.otyp = POT_HEALING;
    fixture.oclass = POTION_CLASS;
    fixture.quan = 1;
    fixture.dknown = 1;
    fixture.blessed = 1;
    fixture.invlet = 'x';
    int original_discovery = objects[POT_HEALING].oc_name_known;
    objects[POT_HEALING].oc_name_known = 0;
    nm_event unknown = event(NM_ITEM, NULL);
    item_payload(&unknown, &fixture);
    int private_ok = !strstr(unknown.text, "healing")
        && !strstr(unknown.text, "blessed") && !strstr(unknown.text, "cursed")
        && unknown.values[2] >= 0 && unknown.values[3] == 1
        && !unknown.values[4] && !unknown.values[5]
        && !unknown.values[6] && !unknown.values[7];
    fixture.known = fixture.bknown = 1;
    objects[POT_HEALING].oc_name_known = 1;
    nm_event known = event(NM_ITEM, NULL);
    item_payload(&known, &fixture);
    objects[POT_HEALING].oc_name_known = original_discovery;
    if (!private_ok || !strstr(known.text, "healing") || !strstr(known.text, "blessed")) {
        fprintf(stderr, "Private item payload failed: unknown=%s known=%s\n", unknown.text, known.text);
        nm_engine_exit(EXIT_FAILURE);
    }
    fprintf(stderr, "Unknown item type and BUC privacy fixture passed.\n");
}
