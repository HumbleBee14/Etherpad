package com.humblebee.etherpad.ui

import android.util.Log
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.synth.Presets

private const val TAG = "EtherUI"

/**
 * State holder for the touch surface. Holds the visible per-slot finger
 * positions and the live note count (used to draw the pitch grid). Sized
 * for [Presets.MAX_TOUCHES] simultaneous fingers.
 */
internal class TouchState {
    /** Visible finger positions, indexed by slot. Compose-observable so the
     *  Canvas redraws when they change. */
    val live: SnapshotStateMap<Int, Offset> = SnapshotStateMap()
    /** Number of pitch columns currently drawn (updated by Size menu). */
    val numberOfNotes = mutableIntStateOf(Presets.SizeLabels[Presets.DefaultSizeIdx].toInt())
}

/**
 * The instrument's main playing surface. Renders the slate background, the
 * vertical pitch grid, and a translucent yellow disc under each active
 * finger. Forwards every touch transition to the [Synth] so the engine
 * spawns / updates / ends notes.
 *
 * Multi-touch model: each Compose pointer id is mapped to a slot index in
 * [0, Presets.MAX_TOUCHES). On touch-down we allocate the lowest free slot;
 * on touch-up the slot is returned to the pool. Csound's instr 1 reads
 * `touch.<slot>.x|y` at audio rate, so we just push the latest UI value into
 * those channels on every move — no per-frame event scheduling needed.
 */
@Composable
internal fun TouchSurface(
    synth: Synth,
    state: TouchState,
    modifier: Modifier = Modifier,
) {
    val slots = remember { mutableMapOf<Long, Int>() }
    val viewSize = remember { mutableStateOf(Size.Zero) }
    val density = LocalDensity.current.density

    Canvas(
        modifier = modifier
            .background(EtherColors.Background)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        val w = size.width.toFloat()
                        val h = size.height.toFloat()
                        viewSize.value = Size(w, h)

                        for (change in event.changes) {
                            val id = change.id.value
                            val wasDown = id in slots
                            val isDown = change.pressed
                            val x = (change.position.x / w).coerceIn(0f, 1f).toDouble()
                            val y = (1f - change.position.y / h).coerceIn(0f, 1f).toDouble()

                            if (!wasDown && isDown) {
                                // touch-down: allocate the lowest free slot
                                val slot = (0 until Presets.MAX_TOUCHES).firstOrNull { s ->
                                    slots.values.none { it == s }
                                }
                                if (slot != null) {
                                    slots[id] = slot
                                    synth.touchDown(slot, x, y)
                                    state.live[slot] = change.position
                                    Log.d(TAG, "down slot=$slot x=$x y=$y")
                                }
                            } else if (wasDown && isDown) {
                                // touch-move: same slot, new position
                                val slot = slots[id]!!
                                synth.touchMove(slot, x, y)
                                state.live[slot] = change.position
                            } else if (wasDown && !isDown) {
                                // touch-up: free the slot
                                val slot = slots.remove(id)!!
                                synth.touchUp(slot)
                                state.live.remove(slot)
                                Log.d(TAG, "up slot=$slot")
                            }
                            change.consume()
                        }
                    }
                }
            },
    ) {
        // Vertical pitch grid lines. Engine value 8 → 7 lines dividing the
        // surface into 8 columns. The legacy 2014 view drew strokes the same
        // way; we keep the 6 px width here for visual continuity.
        val gridCount = state.numberOfNotes.intValue
        if (gridCount > 1) {
            val step = size.width / gridCount.toFloat()
            for (i in 1 until gridCount) {
                drawLine(
                    color = EtherColors.Grid,
                    start = Offset(i * step, 0f),
                    end = Offset(i * step, size.height),
                    strokeWidth = 6f,
                )
            }
        }
        // Translucent yellow disc under each active finger.
        state.live.values.forEach { p ->
            drawCircle(
                color = EtherColors.FingerCircle,
                radius = 60f * density,
                center = p,
            )
        }
    }
}
