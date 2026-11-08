        | Mod 0018 - scenes that set the track mutes.
        |
        | With SCENE held, FUNC + T1..T13 toggles that track in the edited
        | scene's mute mask (T13 is FX). The first toggle marks the scene as one
        | that sets mutes. While FUNC is held in scene edit, T1..T13 show the
        | edited scene's mask.
        |
        | Engaging a marked scene replaces the mutes with its mask. Engaging an
        | unmarked scene, or none, puts back the mutes from before the first
        | scene. A mute changed by hand or by MIDI while a scene is engaged goes
        | into that saved state as well. <CLEAR> drops the edited scene's mask
        | and mark; <CLEAR ALL> drops every scene's.
        |
        | Every mute change goes through track_mute_set with echo 0, so the
        | notice and the screens follow and nothing is sent out.
        |
        | The marks and masks live in the current kit's record in the stored
        | project image, in bytes stock never reads or writes, so they persist
        | with the project and follow kit changes. Edits to them are saved at
        | once: RELOAD does not revert them. Layout, per record:
        |   +0x832          marks, bit s: scene s sets mutes
        |   +0x834 + 2s     scene s's mask, s = 0..6
        |   +0x902 + 2s-14  scene s's mask, s = 7..11
        |   +0x90c          TAG once written; a record without it reads empty
        |
        | Hooks: SceneEditView's key and LED slots, the two clear invokers, and
        | the entries of kit_scene_set_active and track_mute_set.

        .include "symbols.inc"

        .equ    EDITED_SCENE,   192               | SceneEditView: scene 0..11
        .equ    EDIT_KIT,       176               | SceneEditView: the working kit
        .equ    TRACKS,         13
        .equ    LED_ON_MODE,    1                 | as the playhead
        .equ    LED_ON_COLOUR,  6
        .equ    LED_ON_LEVEL,   15
        .equ    MARKS_OFF,      KIT_SPARE_A
        .equ    MASKS_A,        KIT_SPARE_A+2     | scenes 0..6
        .equ    MASKS_B,        KIT_SPARE_B-14    | scenes 7..11, as MASKS_A
        .equ    TAG_OFF,        KIT_SPARE_B+10
        .equ    TAG,            0x53
        .equ    KIT_INDEX_VT,   108               | working KitSlot: current index

        .text

        | The scene-edit hooks, in cave18; the rest is in cave10.
        .section .sme,"ax"

        | ------------------------------------------------------------------
        | sm_keys(SceneEditView *, KeyEvent *): SceneEditView's vtable slot 2.
        | FUNC + trig 1..13 is taken, press and release alike; a fresh press
        | toggles. Everything else goes to stock.
        | ------------------------------------------------------------------
        .align  2
sm_keys:
        move.l  8(%sp),%a0
        move.l  12(%a0),%d0                       | key code
        moveq   #TRACKS-1,%d1
        cmp.l   %d0,%d1
        bcs.s   9f                                | not a trig 1..13
        move.l  16(%a0),%d1                       | event flags
        btst    #1,%d1
        beq.s   9f                                | no FUNC
        btst    #0,%d1
        beq.s   1f                                | release: taken, no action
        btst    #3,%d1
        bne.s   1f
        move.l  %d0,-(%sp)
        move.l  8(%sp),-(%sp)
        bsr     sm_toggle
        addq.l  #8,%sp
1:      moveq   #1,%d0
        rts
9:      jmp     scene_edit_keys

        | ------------------------------------------------------------------
        | sm_toggle(SceneEditView *, int track): flips the track in the edited
        | scene's mask and marks the scene. If that scene is engaged, the mutes
        | follow at once.
        | ------------------------------------------------------------------
        .align  2
sm_toggle:
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        move.l  16(%sp),%a2
        move.l  20(%sp),%d2                       | track
        move.l  EDITED_SCENE(%a2),%d3
        jsr     sm_open
        beq.s   9f                                | no kit record
        move.w  MARKS_OFF(%a0),%d1
        bset    %d3,%d1
        move.w  %d1,MARKS_OFF(%a0)
        move.l  %d3,%d0
        bsr     sm_mask_ptr
        move.w  (%a0),%d1
        bchg    %d2,%d1
        move.w  %d1,(%a0)
        move.l  EDIT_KIT(%a2),-(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        cmp.l   %d3,%d0
        bne.s   9f
        jsr     sm_ensure_saved
        move.l  %d3,%d0
        bsr     sm_mask_of
        jsr     sm_apply
9:      movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | sm_leds(SceneEditView *, uint32 *regions): SceneEditView's vtable
        | slot 5. With FUNC held it takes the trig LEDs first: T1..T13 lit for
        | the tracks the edited scene mutes, the rest off. Then stock, which
        | takes the pads and leaves the trig region claimed.
        | ------------------------------------------------------------------
        .align  2
sm_leds:
        move.l  8(%sp),%a0
        moveq   #LED_REGION_TRIGS,%d0
        and.l   (%a0),%d0
        beq.s   9f
        pea     KEY_FUNC
        jsr     is_key_held
        addq.l  #4,%sp
        tst.l   %d0
        beq.s   9f
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        move.l  16(%sp),%a0
        move.l  EDITED_SCENE(%a0),%d0
        bsr     sm_mask_of                        | unmarked: 0, all off
        move.l  %d0,%d3
        jsr     led_manager
        move.l  %d0,%a2
        moveq   #0,%d2
2:      btst    %d2,%d3
        beq.s   3f
        pea     LED_ON_LEVEL
        pea     LED_ON_COLOUR
        pea     LED_ON_MODE
        bra.s   4f
3:      clr.l   -(%sp)
        clr.l   -(%sp)
        clr.l   -(%sp)
4:      move.l  %d2,-(%sp)
        move.l  %a2,-(%sp)
        jsr     led_set
        lea     20(%sp),%sp
        addq.l  #1,%d2
        moveq   #16,%d0
        cmp.l   %d2,%d0
        bne.s   2b
        move.l  20(%sp),%a0
        moveq   #~LED_REGION_TRIGS,%d0
        and.l   %d0,(%a0)                         | the views below skip them
        movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
9:      jmp     scene_edit_leds

        | ------------------------------------------------------------------
        | sm_clear(std::_Any_data *): in place of <CLEAR>'s invoker. Drops the
        | edited scene's mask and mark; if that scene is engaged, the saved
        | mutes come back. Then stock clears the locks.
        | ------------------------------------------------------------------
        .align  2
sm_clear:
        lea     -8(%sp),%sp
        movem.l %d2/%a2,(%sp)
        move.l  12(%sp),%a0
        move.l  (%a0),%a0
        move.l  (%a0),%a2                         | the SceneEditView
        move.l  EDITED_SCENE(%a2),%d2
        jsr     sm_marks
        bclr    %d2,%d0
        beq.s   9f                                | it set no mutes
        move.w  %d0,MARKS_OFF(%a0)
        move.l  %d2,%d0
        bsr     sm_mask_ptr
        clr.w   (%a0)
        move.l  EDIT_KIT(%a2),-(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        cmp.l   %d2,%d0
        bne.s   9f
        jsr     sm_restore
9:      movem.l (%sp),%d2/%a2
        lea     8(%sp),%sp
        jmp     scene_edit_clear_invoker

        | ------------------------------------------------------------------
        | sm_clear_all(std::_Any_data *): in place of <CLEAR ALL>'s invoker.
        | ------------------------------------------------------------------
        .align  2
sm_clear_all:
        lea     -8(%sp),%sp
        movem.l %d2/%a2,(%sp)
        move.l  12(%sp),%a0
        move.l  (%a0),%a0
        move.l  (%a0),%a2
        jsr     sm_marks
        move.l  %d0,%d2                           | the marks before
        beq.s   9f                                | none set mutes
        clr.b   TAG_OFF(%a0)                      | reads empty, zeroed on next use
        move.l  EDIT_KIT(%a2),-(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        tst.l   %d0
        bmi.s   9f
        btst    %d0,%d2
        beq.s   9f
        jsr     sm_restore
9:      movem.l (%sp),%d2/%a2
        lea     8(%sp),%sp
        jmp     scene_edit_clear_all_invoker

        | sm_mask_ptr: a0 a record, d0 scene 0..11 -> a0 the scene's mask.
        | Calls nothing; clobbers d0 and d1.
        .align  2
sm_mask_ptr:
        add.l   %d0,%d0
        moveq   #14,%d1
        cmp.l   %d1,%d0
        bcs.s   1f
        add.l   #MASKS_B,%d0
        bra.s   2f
1:      add.l   #MASKS_A,%d0
2:      add.l   %d0,%a0
        rts

        | sm_mask_of: d0 scene 0..11 -> d0 its mask, zero-extended; 0 if the
        | scene sets no mutes.
        .align  2
sm_mask_of:
        move.l  %d0,-(%sp)
        jsr     sm_marks
        move.l  (%sp)+,%d1
        btst    %d1,%d0
        beq.s   8f
        move.l  %d1,%d0
        bsr     sm_mask_ptr
        moveq   #0,%d0
        move.w  (%a0),%d0
        rts
8:      moveq   #0,%d0
        rts

        .text

        | ------------------------------------------------------------------
        | ksa_hook: the entry of kit_scene_set_active(kit, scene, echo).
        | Runs stock, then sets the mutes for the scene that is engaged after
        | it, read back so stock's guard and range check decide. Entering a
        | scene from none first saves the mutes as they are.
        | ------------------------------------------------------------------
        .align  2
ksa_hook:
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        move.l  16(%sp),%a2                       | kit
        move.l  %a2,-(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        move.l  %d0,%d3                           | the scene before
        bpl.s   1f
        clr.b   sm_valid
        bsr     sm_ensure_saved
1:      move.l  24(%sp),-(%sp)                    | echo
        move.l  24(%sp),-(%sp)                    | scene
        move.l  24(%sp),-(%sp)                    | kit
        bsr     ksa_stock
        lea     12(%sp),%sp
        move.l  %a2,-(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        cmp.l   %d3,%d0
        beq.s   9f                                | nothing changed
        move.l  %d0,%d2
        bmi.s   5f
        bsr     sm_marks
        btst    %d2,%d0
        beq.s   6f
        bsr     sm_ensure_saved
        move.l  %d2,%d0
        jsr     sm_mask_of
        bsr     sm_apply
        bra.s   9f
6:      bsr     sm_restore                        | an unmarked scene
        bra.s   9f
5:      bsr     sm_restore                        | none
        clr.b   sm_valid
9:      movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        rts

        .align  2
ksa_stock:
        lea     -28(%sp),%sp                      | displaced
        movem.l %d2-%d4/%a2-%a5,(%sp)             | displaced
        jmp     kit_scene_set_active_body

        | ------------------------------------------------------------------
        | tms_hook: the entry of track_mute_set(set, track, mute, echo). A
        | change from outside this mod while a scene is engaged also goes into
        | the saved mutes, so disengaging keeps it.
        | ------------------------------------------------------------------
        .align  2
tms_hook:
        tst.b   sm_busy
        bne.s   9f
        tst.b   sm_valid
        beq.s   9f
        move.l  8(%sp),%d0                        | track
        moveq   #TRACKS-1,%d1
        cmp.l   %d0,%d1
        bcs.s   9f
        jsr     project_singleton
        move.l  %d0,-(%sp)
        jsr     project_kit
        move.l  %d0,(%sp)
        jsr     kit_scene_active
        addq.l  #4,%sp
        tst.l   %d0
        bmi.s   9f
        move.l  8(%sp),%d0
        move.l  sm_saved,%d1
        bclr    %d0,%d1
        tst.b   15(%sp)                           | mute
        beq.s   1f
        bset    %d0,%d1
1:      move.l  %d1,sm_saved
9:      link.w  %fp,#-48                          | displaced
        movem.l %d2-%d6/%a2-%a5,(%sp)             | displaced
        jmp     track_mute_set_body

        | ------------------------------------------------------------------
        | Helpers. Each may clobber d0, d1, a0 and a1 only.
        | ------------------------------------------------------------------

        | sm_record: a0 and d0 the current kit's stored record, or 0 (Z set)
        | when the working kit has no index 0..127.
        .align  2
sm_record:
        jsr     project_singleton
        move.l  %d0,%a0
        lea     PROJECT_WORKING_KIT(%a0),%a0
        move.l  %a0,-(%sp)
        move.l  (%a0),%a1
        move.l  KIT_INDEX_VT(%a1),%a1
        jsr     (%a1)
        addq.l  #4,%sp
        moveq   #127,%d1
        cmp.l   %d0,%d1
        bcs.s   8f
        move.l  #STORED_KIT_SIZE,%d1
        mulu.l  %d1,%d0
        add.l   #PROJECT_IMAGE+STORED_KITS,%d0
        move.l  %d0,%a0
        rts
8:      moveq   #0,%d0
        move.l  %d0,%a0
        rts

        | sm_marks: d0 the current kit's marks, zero-extended, a0 its record.
        | 0 when there is no record or it was never written.
        .align  2
sm_marks:
        bsr     sm_record
        beq.s   8f
        move.b  TAG_OFF(%a0),%d1
        cmp.b   #TAG,%d1
        bne.s   8f
        moveq   #0,%d0
        move.w  MARKS_OFF(%a0),%d0
        rts
8:      moveq   #0,%d0
        rts

        | sm_open: a0 and d0 the current kit's record, tagged and zeroed on
        | first use; 0 (Z set) when there is none.
        .align  2
sm_open:
        bsr     sm_record
        beq.s   9f
        move.b  TAG_OFF(%a0),%d1
        cmp.b   #TAG,%d1
        beq.s   9f
        lea     KIT_SPARE_A(%a0),%a1
        moveq   #15,%d0
1:      clr.b   (%a1)+
        subq.l  #1,%d0
        bpl.s   1b
        lea     KIT_SPARE_B(%a0),%a1
        moveq   #9,%d0
2:      clr.b   (%a1)+
        subq.l  #1,%d0
        bpl.s   2b
        moveq   #TAG,%d1
        move.b  %d1,TAG_OFF(%a0)
9:      move.l  %a0,%d0
        rts

        | sm_settings: d0 the project settings object track_mute_set takes.
        .align  2
sm_settings:
        jsr     project_singleton
        move.l  %d0,-(%sp)
        jsr     track_selection
        addq.l  #4,%sp
        rts

        | sm_ensure_saved: if nothing is saved, saves the mutes as they are.
        .align  2
sm_ensure_saved:
        tst.b   sm_valid
        bne.s   9f
        bsr     sm_settings
        move.l  %d0,-(%sp)
        jsr     mute_mask_get
        addq.l  #4,%sp
        move.l  %d0,sm_saved
        moveq   #1,%d0
        move.b  %d0,sm_valid
9:      rts

        | sm_restore: if mutes are saved, puts them back.
        .align  2
sm_restore:
        tst.b   sm_valid
        beq.s   9f
        move.l  sm_saved,%d0
        bsr     sm_apply
9:      rts

        | sm_apply: d0 the mask to set. Changes only the tracks that differ,
        | through track_mute_set with echo 0, marked busy so tms_hook lets
        | them through.
        .align  2
sm_apply:
        lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        move.l  %d0,%d3                           | wanted
        bsr     sm_settings
        move.l  %d0,%a2
        move.l  %a2,-(%sp)
        jsr     mute_mask_get
        addq.l  #4,%sp
        move.l  %d0,%d4                           | as it is
        eor.l   %d3,%d4                           | the tracks to change
        moveq   #1,%d0
        move.b  %d0,sm_busy
        moveq   #0,%d2
1:      btst    %d2,%d4
        beq.s   3f
        clr.l   -(%sp)                            | echo 0
        moveq   #0,%d0
        btst    %d2,%d3
        beq.s   2f
        moveq   #1,%d0
2:      move.l  %d0,-(%sp)
        move.l  %d2,-(%sp)
        move.l  %a2,-(%sp)
        jsr     track_mute_set
        lea     16(%sp),%sp
3:      addq.l  #1,%d2
        moveq   #TRACKS,%d0
        cmp.l   %d2,%d0
        bne.s   1b
        clr.b   sm_busy
        movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | Written at run time.
        | ------------------------------------------------------------------
        .align  2
sm_saved:
        .long   0                                 | the mutes to come back to
sm_valid:
        .byte   0                                 | sm_saved holds something
sm_busy:
        .byte   0                                 | this mod is changing mutes
