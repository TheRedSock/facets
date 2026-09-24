# Facets — optional merge-window review

You are the sole reviewer for this prototype. Nothing in this form blocks the
engineering work. You do not need to test everything, produce a verdict, or
represent other players. Record uncertainty and unexpected behavior freely.

This build contains the P2 room with repeated interventions. P3 families,
expedition rewards/carry and disk Continue are still future work.

## Start here

Use the review launcher in the delivered folder. Its README identifies the
tested graphics profiles and any unresolved environment limitation. Choose
**Practice · redirect a merge** for the guided board, or **Play · merge
interventions** for the normal timed room. **Play · original P2** and the earlier
intervention comparison are retained controls.

The practice board has no deadline. **Pass window** advances its default path;
**Restart** resets the same arrangement. This is an assisted learning mode,
not a demonstration of reaction-time difficulty.

Count rows from the top and columns from the left, beginning at 1:

1. Swap the gem in row 4, column 4 one cell left. The new upgraded gem appears
   in row 4, column 3, with a pending automatic match below it.
2. Move that upgraded gem one cell left again. This redirects it into a
   four-gem match in column 2. The pending three-gem match in column 3 is denied.
3. Restart, repeat only the first swap, then press **Pass window**. Compare the
   automatic three-gem result with the redirection. Redirection costs another
   Work and the stronger match earns one more Craft in this fixture.

In the normal room, every merge provides about one third of a second for another
legal adjacent swap anywhere on the board. That swap costs 1 Work, just like a
move made after settling. A new merge provides another window; there is no
one-intervention cap. You can also make an unrelated legal match elsewhere.
If you do nothing, an automatic match resolves next when one exists; otherwise
gravity continues. Invalid swaps spend nothing and do not extend the window.

Try mouse dragging or select a gem with Enter, move the cursor with an arrow,
then press Enter again. Focus loss pauses timed input as an assisted attempt;
use **Pause / resume** after returning. Reduced motion preserves the normal
window duration. Restart/menu are available throughout.

## Optional notes

- Build / launcher / window size:
- What did you try? Practice redirection, automatic comparison, timed play,
  a match elsewhere, repeated interventions, or something else:
- What did you expect, and what actually happened?
- Was it clear which gems were selectable while another match animated?
- Did an intended swap fail to register, or an unintended swap occur?
- Any hesitation, visual confusion, uncomfortable timing, or surprising cost?
- Anything you liked, disliked, or remain unsure about:

A short description of the preceding move is useful for a bug report. A seed,
reproduction sequence or recording helps if convenient; none is required.

## Buffered input in this update

During swap or gravity motion, make one complete drag or keyboard swap. Cyan outlines and a connecting line show the pending pair. The game follows those gems and tries once at the next merge window or equilibrium; it cancels without cost if they disappear or the swap is no longer legal. A newer completed gesture replaces it. Escape, right-click or Cancel selection clears it. The actual swap uses its normal animation and normal cost.

Unaffordable tools are disabled. Click an active tool again or use Escape/Cancel to return to swaps. Promotion and rubble sounds are restored, including reduced-motion cue summaries.

Optional notes: Did the queued pair match your intent? Was a cancellation understandable? Were the restored sounds clear?

