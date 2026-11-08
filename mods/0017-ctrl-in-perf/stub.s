        | Mod 0017 - CTRL IN drives a performance macro.
        |
        | adc_pedal_update (0x4013f1c8), called from the audio interrupt at
        | 0x40120e94, leaves each CTRL IN port's value, 0..0x7fff after its
        | mode's mapping, at 0x8000fcf8 + 4p. The port's engine record
        | (0x8000fd00 + 40p) holds its mode at +0: 0 OFF, 1 CV, 2 EXPR, 3 FSW.
        | CV puts CV ZERO LEVEL at 0x4000 and CV MAX LEVEL at 0x7fff; EXPR puts
        | its range at 0..0x7fff.
        |
        | A performance macro's value is engine state only: the target words
        | at 0x8000e57c + 2k, 0..0x7f00 (knob value << 8), written by the knob,
        | the pads and CC 35..47 through 0x4011f698, and read back by the PERF
        | mode pad LEDs (PerformanceView's draw, 0x400ce238). Each block the
        | engine glides its working copy toward them and applies the locks.
        |
        | The CV always wins: for a port in CV or EXPR mode with a PERF DEST,
        | the macro's target is written every block, CV ZERO..MAX (or the EXPR
        | range) mapping to 0..127. The step written changes only when the port
        | moves by more than HYST from the centre of the current step, so ADC
        | noise never moves it.
        |
        | PERF DEST is kept in the persisted gap at 0x405c8e84, which only the
        | power-fail save and the boot restore touch (emulator survey,
        | 2026-11-01): a tag, a version byte, then one byte per port, 0 OFF or
        | 1..12 PF1..PF12. A bad tag or version reads as OFF for both ports; the
        | first change writes a fresh record.

        .include "symbols.inc"

        .equ    RESUME,         0x40120ea4        | past the displaced lea
        .equ    PORT_VALUE,     0x8000fcf8        | longs, per port, 0..0x7fff
        .equ    PORT_RECORD,    0x8000fd00        | engine records, mode long at +0
        .equ    PORT_STRIDE,    40
        .equ    MODE_CV,        1
        .equ    MODE_EXPR,      2
        .equ    PERF_TARGET,    0x8000e57c        | words, per macro, 0..0x7f00
        .equ    HYST,           192               | 0.75 of a 256-wide step
        .equ    PORTS,          2
        .equ    DESTS,          12

        .equ    CFG,            0x405c8e84        | the persisted gap
        .equ    CFG_TAG,        0x43495046        | "CIPF"
        .equ    CFG_VER,        1
        .equ    CFG_DEST,       5                 | + port: 0 OFF, 1..12

        | ControlInputConfig (the CONTROL INPUT 1/2 page). rebuild (0x40131496)
        | builds the items for the port's mode and converges at 0x40131962,
        | which restores the cursor and returns. Each item is four
        | std::function objects - label, an empty one, the value drawer, the
        | value changer - a 0x54-byte MenuItem, and an append through the
        | view's vtable +8, as AudioRoutingMenuView's.
        .equ    MENU_RESUME,    0x40131968
        .equ    MENU_ITEM_CTOR, 0x40072f50
        .equ    FN_DTOR,        0x401709c6        | std::function's destructor
        .equ    VIEW_PORT,      432
        .equ    VIEW_MODE,      436               | the working record's mode
        .equ    VIEW_INVALIDATE, 0x40078514       | (view + 56)
        .equ    TEXT_PRINTF,    0x400712d4        | (canvas, font, x, y, align, fmt, ...)
        .equ    CI_FONT,        0x417e3884        | the page's value font
        .equ    FMT_S,          0x402410a4        | "%s"

        .text

        | ------------------------------------------------------------------
        | ctrl_in_perf: over `lea 0x800067de,%a4`, after adc_pedal_update has
        | returned and its arguments are popped. d0, d1, a0 and a1 are written
        | before they are read on the way to the next call, so they are free;
        | d2..d4 are saved.
        | ------------------------------------------------------------------
        .align  2
ctrl_in_perf:
        lea     -12(%sp),%sp
        movem.l %d2-%d4,(%sp)
        moveq   #0,%d2                            | port
1:      move.l  %d2,%d0
        bsr.w   cip_dest
        move.l  %d0,%d4                           | 0 OFF, 1..12
        lea     last_step,%a1
        lea     (%a1,%d2.l*2),%a1
        tst.l   %d4
        beq.s   7f
        lea     PORT_RECORD,%a0
        tst.l   %d2
        beq.s   2f
        lea     PORT_STRIDE(%a0),%a0
2:      move.l  (%a0),%d3                         | mode
        lea     PORT_VALUE,%a0
        move.l  (%a0,%d2.l*4),%d0                 | 0..0x7fff
        moveq   #MODE_EXPR,%d1
        cmp.l   %d1,%d3
        beq.s   3f
        moveq   #MODE_CV,%d1
        cmp.l   %d1,%d3
        bne.s   7f                                | OFF or FSW
        sub.l   #0x4000,%d0                       | CV: ZERO..MAX to 0..0x7fff
        bpl.s   2f
        moveq   #0,%d0
2:      add.l   %d0,%d0
        cmp.l   #0x7fff,%d0
        ble.s   3f
        move.l  #0x7fff,%d0
3:      mvs.w   (%a1),%d1                         | last step, -1 none
        bmi.s   4f
        lsl.l   #8,%d1
        add.l   #128,%d1                          | centre of that step
        sub.l   %d0,%d1
        bpl.s   5f
        neg.l   %d1
5:      cmp.l   #HYST,%d1
        ble.s   6f                                | within the dead band: keep the step
4:      lsr.l   #8,%d0                            | 0..127
        move.w  %d0,(%a1)
6:      mvz.w   (%a1),%d0
        lsl.l   #8,%d0
        lea     PERF_TARGET - 2,%a0
        move.w  %d0,(%a0,%d4.l*2)                 | every block: the CV wins
        bra.s   8f
7:      moveq   #-1,%d0                           | not driving: forget the step
        move.w  %d0,(%a1)
8:      addq.l  #1,%d2
        moveq   #PORTS,%d0
        cmp.l   %d0,%d2
        blt.w   1b
        movem.l (%sp),%d2-%d4
        lea     12(%sp),%sp
        lea     0x800067de,%a4                    | displaced
        jmp     RESUME

        | cip_dest(d0 = port) -> d0 = 0 OFF or 1..12. Uses d1 and a0.
        .align  2
cip_dest:
.if P_PROBE
        moveq   #P_PROBE_PORT,%d1
        cmp.l   %d1,%d0
        bne.s   1f
        moveq   #P_PROBE_PERF + 1,%d0
        rts
1:
.endif
        lea     CFG,%a0
        move.l  (%a0),%d1
        cmp.l   #CFG_TAG,%d1
        bne.s   8f
        mvz.b   4(%a0),%d1
        cmp.l   #CFG_VER,%d1
        bne.s   8f
        mvz.b   CFG_DEST(%a0,%d0.l),%d0
        moveq   #DESTS,%d1
        cmp.l   %d1,%d0
        bhi.s   8f
        rts
8:      moveq   #0,%d0
        rts

        | ------------------------------------------------------------------
        | cip_menu: over `moveal %a2@,%a0; clrl %sp@-; movel %d6,%sp@-` where
        | rebuild's mode branches converge. a2 the view, d6 the cursor; past
        | here rebuild uses nothing else and its epilogue restores d2..d7 and
        | a2..fp, so the stub may use them. Appends PERF DEST in CV and EXPR.
        | ------------------------------------------------------------------
        .align  2
cip_menu:
        move.l  VIEW_MODE(%a2),%d0
        subq.l  #MODE_CV,%d0
        moveq   #MODE_EXPR - MODE_CV,%d1
        cmp.l   %d1,%d0
        bhi.w   9f                                | OFF or FSW: no item
        lea     -64(%sp),%sp                      | four std::function, 16 B each:
        move.l  %sp,%a3                           | +0 data, +4, +8 manager, +12 invoker
        moveq   #15,%d1
        move.l  %a3,%a0
1:      clr.l   (%a0)+
        subq.l  #1,%d1
        bpl.s   1b
        move.l  %a2,(%a3)                         | label, the view in place
        move.l  #cip_mgr,%d0
        move.l  %d0,8(%a3)
        move.l  #cip_label,%d0
        move.l  %d0,12(%a3)
        move.l  %a2,32(%a3)                       | drawer
        move.l  #cip_mgr,%d0
        move.l  %d0,40(%a3)
        move.l  #cip_draw,%d0
        move.l  %d0,44(%a3)
        move.l  %a2,48(%a3)                       | changer
        move.l  #cip_mgr,%d0
        move.l  %d0,56(%a3)
        move.l  #cip_change,%d0
        move.l  %d0,60(%a3)
        pea     0x54
        jsr     mem_new
        addq.l  #4,%sp
        move.l  %d0,%d7
        pea     0x8
        pea     -1
        pea     48(%a3)
        pea     32(%a3)
        pea     16(%a3)
        pea     (%a3)
        move.l  %d7,-(%sp)
        jsr     MENU_ITEM_CTOR
        lea     28(%sp),%sp
        move.l  (%a2),%a0
        move.l  8(%a0),%a0                        | append
        move.l  %d7,-(%sp)
        move.l  %a2,-(%sp)
        jsr     (%a0)
        addq.l  #8,%sp
        moveq   #3,%d2
2:      move.l  %d2,%d0
        lsl.l   #4,%d0
        pea     (%a3,%d0.l)
        jsr     FN_DTOR
        addq.l  #4,%sp
        subq.l  #1,%d2
        bpl.s   2b
        lea     64(%sp),%sp
9:      move.l  (%a2),%a0                         | displaced
        clr.l   -(%sp)
        move.l  %d6,-(%sp)
        jmp     MENU_RESUME

        | cip_label(a0 = the std::string to construct) -> d0 = a0, as stock's
        | label invokers.
        .align  2
cip_label:
        link.w  %fp,#-4
        move.l  %d2,-(%sp)
        pea     -1(%fp)
        pea     txt_label
        move.l  %a0,%d2
        move.l  %a0,-(%sp)
        jsr     std_string_from_cstr
        lea     12(%sp),%sp
        move.l  %d2,%d0
        move.l  -8(%fp),%d2
        unlk    %fp
        rts

        | cip_draw(functor, item, canvas, x, y): OFF or PFn, drawn as the page
        | draws MODE (0x4013118e).
        .align  2
cip_draw:
        move.l  4(%sp),%a0
        move.l  (%a0),%a0                         | the view
        move.l  VIEW_PORT(%a0),%d0
        bsr.w   cip_dest
        tst.l   %d0
        bne.s   1f
        pea     txt_off
        pea     FMT_S
        bra.s   2f
1:      move.l  %d0,-(%sp)
        pea     txt_pf
2:      pea     0x4
        move.l  32(%sp),%d0                       | y
        addq.l  #2,%d0
        move.l  %d0,-(%sp)
        move.l  32(%sp),%d0                       | x
        add.l   #19,%d0
        move.l  %d0,-(%sp)
        pea     CI_FONT
        move.l  36(%sp),-(%sp)                    | canvas
        jsr     TEXT_PRINTF
        lea     28(%sp),%sp
        rts

        | cip_change(functor, item, delta): PERF DEST of the view's port, 0..12,
        | in the gap, writing a fresh record first if there is none. Then the
        | view is invalidated: the value is not a stock setting, so no setter's
        | notification redraws it.
        .align  2
cip_change:
        move.l  4(%sp),%a0
        move.l  (%a0),%a1                         | the view
        move.l  12(%sp),%d1                       | delta
        beq.s   9f
        lea     CFG,%a0
        move.l  (%a0),%d0
        cmp.l   #CFG_TAG,%d0
        bne.s   1f
        mvz.b   4(%a0),%d0
        cmp.l   #CFG_VER,%d0
        beq.s   2f
1:      move.l  #CFG_TAG,(%a0)                    | a fresh record, both ports OFF
        moveq   #CFG_VER,%d0
        move.b  %d0,4(%a0)
        clr.b   5(%a0)
        clr.b   6(%a0)
        clr.b   7(%a0)
2:      move.l  VIEW_PORT(%a1),%d0
        lea     CFG_DEST(%a0,%d0.l),%a0
        mvz.b   (%a0),%d0
        add.l   %d1,%d0
        bpl.s   3f
        moveq   #0,%d0
3:      moveq   #DESTS,%d1
        cmp.l   %d1,%d0
        ble.s   4f
        move.l  %d1,%d0
4:      move.b  %d0,(%a0)
        pea     56(%a1)
        jsr     VIEW_INVALIDATE
        addq.l  #4,%sp
9:      rts

        | cip_mgr(dest, source, op): the std::function manager for a functor
        | stored in place - the view pointer. 0 names the type (this routine's
        | address stands in for its typeinfo), 1 answers the functor's address,
        | 2 copies the pointer, 3 has nothing to free.
        .align  2
cip_mgr:
        move.l  4(%sp),%a0                        | dest
        move.l  12(%sp),%d0                       | op
        bne.s   1f
        move.l  #cip_mgr,(%a0)
        bra.s   9f
1:      subq.l  #1,%d0
        bne.s   2f
        move.l  8(%sp),(%a0)
        bra.s   9f
2:      subq.l  #1,%d0
        bne.s   9f
        move.l  8(%sp),%a1
        move.l  (%a1),(%a0)
9:      moveq   #0,%d0
        rts

txt_label:
        .asciz  "PERF DEST"
txt_off:
        .asciz  "OFF"
txt_pf:
        .asciz  "PF%d"

        | ------------------------------------------------------------------
        | State, written at run time: each port's last step, -1 none.
        | ------------------------------------------------------------------
        .align  2
last_step:
        .short  -1, -1
