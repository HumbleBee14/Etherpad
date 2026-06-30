package com.humblebee.etherpad

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.ui.EtherpadApp

// onDestroy stops the Oboe stream; Csound itself is intentionally never destroyed (see engine.cpp).
class MainActivity : ComponentActivity() {

    private lateinit var synth: Synth

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Immersive full-screen: draw under the bars and behind the cutout, then
        // hide the bars. ALWAYS is the Android 15+ cutout default (SHORT_EDGES,
        // which enableEdgeToEdge() set, is deprecated).
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.attributes.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        synth = Synth(resources)
        setContent { EtherpadApp(synth) }
    }

    override fun onDestroy() {
        super.onDestroy()
        synth.stop()
    }
}
