package com.humblebee.etherpad

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.humblebee.etherpad.engine.Synth
import com.humblebee.etherpad.ui.EtherSurfaceApp

// onDestroy stops the Oboe stream; Csound itself is intentionally never destroyed (see engine.cpp).
class MainActivity : ComponentActivity() {

    private lateinit var synth: Synth

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        synth = Synth(resources)
        setContent { EtherSurfaceApp(synth) }
    }

    override fun onDestroy() {
        super.onDestroy()
        synth.stop()
    }
}
