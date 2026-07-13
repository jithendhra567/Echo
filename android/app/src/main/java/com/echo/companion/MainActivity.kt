package com.echo.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.echo.companion.net.EchoSocketClient
import com.echo.companion.protocol.PairingPayload
import com.echo.companion.ui.HomeScreen
import com.echo.companion.ui.ScanScreen
import com.echo.companion.ui.theme.EchoTheme

class MainActivity : ComponentActivity() {
    private val vm: EchoViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        intent?.dataString?.let { raw ->
            PairingPayload.parse(raw)?.let(vm::connect)
        }

        setContent {
            EchoTheme {
                Surface(Modifier.fillMaxSize()) {
                    val state by vm.state.collectAsState()
                    var showScanner by remember { mutableStateOf(false) }
                    val connected = state.connection == EchoSocketClient.State.Connected
                        || state.connection == EchoSocketClient.State.Connecting

                    LaunchedEffect(Unit) {
                        if (state.lastPairing != null && !connected && intent?.dataString == null) {
                            vm.reconnect()
                        }
                    }

                    if (showScanner || (!connected && state.lastPairing == null)) {
                        ScanScreen(
                            onPaired = {
                                showScanner = false
                                vm.connect(it)
                            },
                            onBack = if (showScanner) ({ showScanner = false }) else null,
                        )
                    } else if (!connected) {
                        ScanScreen(
                            onPaired = { vm.connect(it) },
                        )
                    } else {
                        HomeScreen(
                            state = state,
                            vm = vm,
                            onRescan = { showScanner = true },
                        )
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Android only allows reading the clipboard while focused.
        vm.captureClipboardIfChanged()
    }
}
