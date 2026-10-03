/* Earthworm Jim 2 (SLES-00343) 16:9 widescreen, gameplay only.
 *
 * Selected by the ewj2.enhancement.widescreen package (feature "widescreen").
 * Every hook is identity while the display is 4:3, so disabling the feature
 * plays the original presentation byte-for-byte.
 *
 * Why the game needs help: every level EXE draws its background with the same
 * tile-row routine (two variants: plain tiles, and tiles with flip/priority
 * flags). It walks one map row from the layer's sub-tile start X while
 * `x < 320` (`slti at,t1,320`) — a hard 4:3 cull, so the widescreen margins
 * would stay black. The routine reads a pointer into the FULL level map
 * (scratchpad 0x1F80020C, row stride 0x1F800208), so the neighbouring columns
 * exist. Instead of re-implementing the tile logic, the hook runs the game's
 * own routine two extra times for a 4-column strip on each side (64 px >= the
 * 53 px reveal + 15 px sub-tile scroll) and moves the new packets into place.
 * The native call is untouched, so the 4:3 image is identical.
 */
#include "mod_plugins.h"
#include "gpu.h"
#include "cpu_state.h"

#include <stddef.h>

#define WS_ID "ewj2.widescreen"

#define SCRATCH_MAP_PTR  0x1F80020Cu   /* tile map pointer for this layer/row */
#define SCRATCH_PKT_B    0x1F800210u   /* packet cursor used by variant B */
#define STRIP_COLS       4
#define STRIP_PX         (STRIP_COLS * 16)
#define TILE_PACKET      16u

/* Tile-row routine of every level EXE: {variant A, variant B}. All level EXEs
 * load at 0x80020000, so addresses collide across levels; each call is
 * verified against the routine's code before anything is done. MENU and END
 * are left out on purpose: widescreen is for gameplay only. */
static const uint32_t k_tile_rows[][2] = {
    {0x80042224u, 0x80042320u}, /* L1  TANG   */
    {0x8003B580u, 0x8003B67Cu}, /* L1  GRAN   */
    {0x8003E694u, 0x8003E790u}, /* L2  PUPS   */
    {0x8003E540u, 0x8003E63Cu}, /* L2  PUP2   */
    {0x8003E598u, 0x8003E694u}, /* L2  PUP3   */
    {0x80040E08u, 0x80040F04u}, /* L3  KING   */
    {0x8003F67Cu, 0x8003F778u}, /* L4  COWS   */
    {0x8003D03Cu, 0x8003D138u}, /* L5  INFLT  */
    {0x8003D284u, 0x8003D380u}, /* L5  HAMMER */
    {0x800432E4u, 0x800433E0u}, /* L6  VILLI  */
    {0x8003DD80u, 0x8003DE7Cu}, /* L7  DIRT   */
    {0x8003D030u, 0x8003D12Cu}, /* L8  ATE    */
    {0x8003CEE8u, 0x8003CFE4u}, /* L8  FYAWN  */
    {0x8003D080u, 0x8003D17Cu}, /* L8  FORKED */
    {0x8003E780u, 0x8003E87Cu}, /* L9  ISO    */
    {0x8003EC44u, 0x8003ED40u}, /* L9  DOOR   */
    {0x8003CBB0u, 0x8003CCACu}, /* L10 RJR    */
};

static int in_hook;                 /* the nested original calls run plain */
static uint32_t vblanks, last_tile_vblank;

/* Partial widescreen: levels whose scenery is not drawn by the tile-row
 * routine keep their original 4:3 with no hook at all.
 *   Puppy Love 1-3 (L2\PUPS.PST): full-screen backdrop picture, not tiles.
 *   Flyin' King    (L3\KING.PST): isometric map with its own renderer.
 *   Lorenzo's Soil (L7\DIRT.PST): darkness/light effect that does not
 *                                 survive the native-wide compositor.
 * Each level EXE starts with the name of its picture file at 0x80020000. */
static int level_excluded(void) {
    static const char* const k_excluded[] = { "L2\\PUPS", "L3\\KING", "L7\\DIRT" };
    char head[8];
    for (int i = 0; i < 8; i++) head[i] = (char)psx_mod_read_byte(0x80020000u + (uint32_t)i);
    for (size_t e = 0; e < sizeof k_excluded / sizeof k_excluded[0]; e++) {
        const char* s = k_excluded[e];
        int i = 0;
        while (s[i] && s[i] == head[i]) i++;
        if (!s[i]) return 1;
    }
    return 0;
}

/* The first instructions of both variants:
 *   lui t5,0x1F80; lw t5,0x208(t5); lui t3,0x1F80; lw t3,0x200(t3)
 * and, 0x34 bytes in, the 4:3 column cull `slti at,t1,320`. */
static int is_tile_row(uint32_t a) {
    return psx_mod_read_word(a + 0x00u) == 0x3C0D1F80u &&
           psx_mod_read_word(a + 0x04u) == 0x8DAD0208u &&
           psx_mod_read_word(a + 0x08u) == 0x3C0B1F80u &&
           psx_mod_read_word(a + 0x0Cu) == 0x8D6B0200u &&
           psx_mod_read_word(a + 0x34u) == 0x29210140u;
}

/* Variant A (16x16 tiles, `lw t8,4(t7)` at +0x5C) appends packets through
 * *(<state>)+4. Variant B (8x8 tiles with flip/priority flags) appends through
 * three cursors: *(<state>)+0, *(<state>)+4 and scratchpad 0x210. <state> is
 * the word both load with `lui t7,hi; lw t7,lo(t7)` (per-EXE address). Every
 * packet is a 16-byte one-word-tag sprite/rect with X at +8. */
static int tile_width(uint32_t a) {
    return psx_mod_read_word(a + 0x5Cu) == 0x8DF80004u ? 16 : 8;
}

static void packet_cursors(uint32_t a, uint32_t cursors[3]) {
    uint32_t hi = psx_mod_read_word(a + 0x10u) << 16;
    int16_t lo = (int16_t)(psx_mod_read_word(a + 0x14u) & 0xFFFFu);
    uint32_t state = psx_mod_read_word(hi + (uint32_t)(int32_t)lo);
    cursors[0] = state;
    cursors[1] = state + 4u;
    cursors[2] = SCRATCH_PKT_B;
}

static void run_row(CPUState* cpu, uint32_t a, uint32_t ra,
                    uint32_t a0, int32_t x, uint32_t a2) {
    cpu->gpr[4] = a0;
    cpu->gpr[5] = (uint32_t)x;
    cpu->gpr[6] = a2;
    cpu->gpr[31] = ra;
    psx_dispatch_call(cpu, a, ra);
}

/* Draw `cols` map columns starting at `map_col` with the game's own routine.
 * It stops at x >= 320, so it is started at 320 - cols*tw (exactly `cols`
 * columns fit) and every packet it appends is moved by `dx` to the strip's
 * real screen position. */
static void strip(CPUState* cpu, uint32_t a, uint32_t ra, uint32_t a0,
                  uint32_t a2, uint32_t map, int32_t map_col,
                  int32_t x_call, int32_t dx) {
    uint32_t cursor[3], first[3];
    packet_cursors(a, cursor);
    for (int i = 0; i < 3; i++) first[i] = psx_mod_read_word(cursor[i]);
    psx_mod_write_word(SCRATCH_MAP_PTR, map + (uint32_t)(map_col * 2));
    run_row(cpu, a, ra, a0, x_call, a2);
    for (int i = 0; i < 3; i++) {
        uint32_t last = psx_mod_read_word(cursor[i]);
        if (last <= first[i] || last - first[i] > 4096u * TILE_PACKET) continue;
        for (uint32_t p = first[i]; p < last; p += TILE_PACKET) {
            int16_t x = (int16_t)psx_mod_read_half(p + 8u);
            psx_mod_write_half(p + 8u, (uint16_t)(int16_t)(x + dx));
        }
    }
    psx_mod_write_word(SCRATCH_MAP_PTR, map);
}

static int tile_row_filter(CPUState* cpu, uint32_t address) {
    if (in_hook || psx_mod_widescreen_x_margin() <= 0 || !is_tile_row(address) ||
        level_excluded())
        return 0;
    last_tile_vblank = vblanks;

    CPUState saved = *cpu;
    uint32_t ra = cpu->gpr[31];
    uint32_t a0 = cpu->gpr[4], a2 = cpu->gpr[6];
    int32_t x0 = (int32_t)cpu->gpr[5];                 /* <= 0: sub-tile scroll */
    uint32_t map = psx_mod_read_word(SCRATCH_MAP_PTR);

    in_hook = 1;
    run_row(cpu, address, ra, a0, x0, a2);             /* the native 4:3 row */
    int32_t tw = tile_width(address);
    if (x0 > -64 && x0 <= 0) {
        int32_t cols = STRIP_PX / tw;
        /* Columns the native call drew: x0, x0+tw, ... while < 320. */
        int32_t n = (320 - x0 + tw - 1) / tw;
        int32_t left = cols, right = cols;
        /* Keep the strips inside the level map, so its edges never show the
         * neighbouring row. Both callers leave the layer's first column in a
         * register: the 16-px caller its scroll X in t0, the 8-px caller its
         * column in t1. Trust it only when it agrees with the call. */
        int32_t width = (int32_t)(psx_mod_read_word(0x1F800208u) / 2u);
        int32_t c0 = -1;
        if (tw == 16 && -(int32_t)(saved.gpr[8] & 15u) == x0)
            c0 = (int32_t)(saved.gpr[8] >> 4);
        else if (tw == 8 && (int32_t)saved.gpr[9] >= 0 && (int32_t)saved.gpr[9] < width)
            c0 = (int32_t)saved.gpr[9];
        if (c0 >= 0 && width > 0 && c0 < width) {
            if (left > c0) left = c0;
            if (right > width - (c0 + n)) right = width - (c0 + n);
        }
        /* Left: map columns -left..-1 at x0-left*tw.. */
        if (left > 0)
            strip(cpu, address, ra, a0, a2, map, -left, 320 - left * tw,
                  x0 - 320);
        /* Right: map columns n..n+right-1 at x0+n*tw.. */
        if (right > 0)
            strip(cpu, address, ra, a0, a2, map, n, 320 - right * tw,
                  x0 + n * tw - (320 - right * tw));
    }
    in_hook = 0;

    /* The routine is a leaf with no return value: hand back the caller's
     * registers it may rely on and return to $ra. */
    uint32_t keep_cycles = cpu->muldiv_ts_done;
    uint32_t keep_gte = cpu->gte_ts_done;
    *cpu = saved;
    if (keep_cycles > cpu->muldiv_ts_done) cpu->muldiv_ts_done = keep_cycles;
    if (keep_gte > cpu->gte_ts_done) cpu->gte_ts_done = keep_gte;
    return 1;
}

/* ---------------------------------------------------------------- HUD --
 * The HUD (head + lives + health at the top left, gun + ammo at the bottom
 * left, level counters at the right) is drawn as ordinary objects, but on
 * screen layer 3 (obj+0x42 >> 5 == 3); world objects use other layers. The
 * object emitter of every level EXE walks the 128 object slots from 127 down
 * to 0 and gives each drawn object the next 20-byte packet, so the packet of
 * every HUD object is known before the emitter fills it. Tagging those packets
 * as edge-anchored HUD makes the native-wide compositor move them with the
 * revealed edge: they keep exactly the distance to the screen edge they had in
 * 4:3. Packets of world objects are untagged, since the slots are reused. */
static const uint32_t k_object_emitters[] = {
    0x8003DC6Cu, /* TANG */  0x80036FC8u, /* GRAN */  0x8003A0DCu, /* PUPS */
    0x80039F88u, /* PUP2 */  0x80039FE0u, /* PUP3 */  0x8003C850u, /* KING */
    0x8003B0C4u, /* COWS */  0x80038A84u, /* INFLT */ 0x80038CCCu, /* HAMMER */
    0x8003ED2Cu, /* VILLI */ 0x800397C8u, /* DIRT */  0x80038A78u, /* ATE */
    0x80038930u, /* FYAWN */ 0x80038AC8u, /* FORKED */0x8003A1C8u, /* ISO */
    0x8003A68Cu, /* DOOR */  0x800385F8u, /* RJR */
};

#define OBJ_SLOTS   128u
#define OBJ_SIZE    128u
#define HUD_LAYER   3u

static void hud_anchor(CPUState* cpu, uint32_t a) {
    if (psx_mod_widescreen_x_margin() <= 0 || level_excluded()) return;
    /* addiu sp,sp,-136; sw ra,132(sp); ... ori s1,zero,0x7F */
    if (psx_mod_read_word(a) != 0x27BDFF78u || psx_mod_read_word(a + 4u) != 0xAFBF0084u)
        return;
    int16_t gp_off = 0;
    uint32_t tab_hi = 0, have = 0;
    int16_t tab_lo = 0;
    for (uint32_t i = 0; i < 40u; i++) {
        uint32_t w = psx_mod_read_word(a + i * 4u);
        if ((w >> 16) == 0x8F82u && !(have & 1u)) { gp_off = (int16_t)w; have |= 1u; }  /* lw v0,off(gp) */
        if ((w >> 16) == 0x3C03u && !(have & 2u)) { tab_hi = w << 16; have |= 2u; }    /* lui v1,hi */
        if ((w >> 16) == 0x2463u && !(have & 4u)) { tab_lo = (int16_t)w; have |= 4u; } /* addiu v1,v1,lo */
    }
    if (have != 7u) return;
    uint32_t table = tab_hi + (uint32_t)(int32_t)tab_lo;
    uint32_t packet = psx_mod_read_word(cpu->gpr[28] + (uint32_t)(int32_t)gp_off) + 248u;
    for (int32_t slot = (int32_t)OBJ_SLOTS - 1; slot >= 0; slot--) {
        uint32_t obj = table + (uint32_t)slot * OBJ_SIZE;
        if (psx_mod_read_byte(obj) == 0 || psx_mod_read_byte(obj + 8u) != 0 ||
            (psx_mod_read_byte(obj + 1u) & 0x80u))
            continue;                                   /* not drawn this frame */
        int edge = 0;
        if ((psx_mod_read_byte(obj + 0x42u) >> 5) == HUD_LAYER) {
            int16_t sx = (int16_t)psx_mod_read_half(obj + 0x2Cu);
            edge = sx < 107 ? -1 : (sx >= 213 ? 1 : 0);
        }
        psx_mod_tag_hud_primitive(packet, edge);
        packet += 20u;
    }
}

static void count_vblank(void) { vblanks++; }

/* Gameplay only: MENU (title, options, debug menu), the ending, transition
 * pictures and anything else that is not drawing a level tilemap keep the
 * original 4:3 presentation. */
static int ewj2_native_scene(void) {
    if (psx_mod_read_word(0x80020000u) == 0x30314C5Cu)  /* "\L10" = MENU.EXE */
        return 1;
    if (level_excluded())
        return 1;
    return vblanks - last_tile_vblank > 4u;
}

static void ewj2_widescreen_activate(void) {
    for (size_t i = 0; i < sizeof k_tile_rows / sizeof k_tile_rows[0]; i++) {
        (void)psx_mod_register_function_filter_plugin(WS_ID, k_tile_rows[i][0], tile_row_filter);
        (void)psx_mod_register_function_filter_plugin(WS_ID, k_tile_rows[i][1], tile_row_filter);
    }
    for (size_t i = 0; i < sizeof k_object_emitters / sizeof k_object_emitters[0]; i++)
        (void)psx_mod_register_function_entry_plugin(WS_ID, k_object_emitters[i], hud_anchor);
    (void)psx_mod_register_vblank_plugin(WS_ID, count_vblank);
    gpu_ws_set_native_scene_predicate(ewj2_native_scene);
    (void)psx_mod_set_fixed_display_aspect(16u, 9u);
}

PSX_MOD_CONSTRUCTOR(ewj2_register_widescreen_plugin) {
    (void)psx_mod_register_activation_plugin(WS_ID, ewj2_widescreen_activate);
}
