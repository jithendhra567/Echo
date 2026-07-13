package com.echo.companion.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DesktopWindows
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.echo.companion.EchoUiState
import com.echo.companion.EchoViewModel
import com.echo.companion.net.EchoSocketClient
import com.echo.companion.protocol.AppDto
import com.echo.companion.protocol.ClipDto

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    state: EchoUiState,
    vm: EchoViewModel,
    onRescan: () -> Unit,
) {
    var tab by remember { mutableIntStateOf(0) }
    val streaming = state.streamingBundleId != null

    if (streaming) {
        StreamScreen(state = state, vm = vm)
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Echo")
                        Text(
                            state.hostName ?: "Local Mac",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onRescan) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan again")
                    }
                    IconButton(onClick = vm::disconnect) {
                        Icon(Icons.Default.LinkOff, contentDescription = "Disconnect")
                    }
                },
            )
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                    label = { Text("Clipboard") },
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Default.DesktopWindows, contentDescription = null) },
                    label = { Text("Apps") },
                )
            }
        },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        ) {
            ConnectionBanner(state)
            state.error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            when (tab) {
                0 -> ClipboardPane(state, vm)
                else -> AppsPane(state, vm)
            }
        }
    }
}

@Composable
private fun ConnectionBanner(state: EchoUiState) {
    val label = when (state.connection) {
        EchoSocketClient.State.Connected -> "Connected on Wi‑Fi"
        EchoSocketClient.State.Connecting -> "Connecting…"
        EchoSocketClient.State.Failed -> "Connection failed — same network?"
        EchoSocketClient.State.Closed, EchoSocketClient.State.Idle -> "Disconnected"
    }
    Text(
        label,
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.primaryContainer)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        style = MaterialTheme.typography.bodyMedium,
    )
}

@Composable
private fun ClipboardPane(state: EchoUiState, vm: EchoViewModel) {
    var draft by remember { mutableStateOf("") }
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Send text to Mac clipboard") },
                singleLine = true,
            )
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(
                onClick = {
                    vm.pushClipboardText(draft)
                    draft = ""
                },
            ) {
                Icon(Icons.Default.Send, contentDescription = "Send")
            }
        }
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(state.clips, key = { it.id }) { clip ->
                ClipRow(clip) { vm.copyClipToDevice(clip) }
            }
        }
    }
}

@Composable
private fun ClipRow(clip: ClipDto, onCopy: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .clickable(onClick = onCopy)
            .padding(14.dp),
    ) {
        Text(
            clip.sourceAppName ?: clip.contentType,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.secondary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            clip.text?.take(240) ?: "[${clip.contentType}]",
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun AppsPane(state: EchoUiState, vm: EchoViewModel) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text(
                "Open a Mac app here — only that window streams, not the whole desktop.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }
        items(state.apps, key = { it.bundleId }) { app ->
            AppRow(app) { vm.startStream(app.bundleId) }
        }
    }
}

@Composable
private fun AppRow(app: AppDto, onOpen: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .clickable(onClick = onOpen)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val iconBmp = remember(app.iconBase64) {
            app.iconBase64?.let {
                val bytes = Base64.decode(it, Base64.DEFAULT)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        }
        if (iconBmp != null) {
            Image(
                bitmap = iconBmp.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.size(40.dp),
            )
        } else {
            Icon(Icons.Default.DesktopWindows, contentDescription = null, modifier = Modifier.size(40.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(app.name, style = MaterialTheme.typography.titleLarge)
            Text(
                if (app.isRunning) "Running" else "Not running",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
        FilledTonalButton(onClick = onOpen) { Text("Open") }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StreamScreen(state: EchoUiState, vm: EchoViewModel) {
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    var keyDraft by remember { mutableStateOf("") }
    val appName = state.apps.firstOrNull { it.bundleId == state.streamingBundleId }?.name
        ?: state.streamingBundleId.orEmpty()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(appName) },
                navigationIcon = {
                    IconButton(onClick = vm::stopStream) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .onSizeChanged { viewSize = it }
                    .pointerInput(viewSize) {
                        detectTapGestures { offset ->
                            if (viewSize.width > 0 && viewSize.height > 0) {
                                vm.sendTap(
                                    offset.x / viewSize.width.toDouble(),
                                    offset.y / viewSize.height.toDouble(),
                                )
                            }
                        }
                    }
                    .pointerInput(viewSize) {
                        detectTransformGestures { _, pan, _, _ ->
                            if (viewSize.width > 0 && viewSize.height > 0) {
                                vm.sendScroll(
                                    pan.x / viewSize.width.toDouble(),
                                    pan.y / viewSize.height.toDouble(),
                                    0.5,
                                    0.5,
                                )
                            }
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                val bmp = state.streamBitmap
                if (bmp != null) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = "App stream",
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Fit,
                    )
                } else {
                    Text("Starting stream…", color = MaterialTheme.colorScheme.secondary)
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = keyDraft,
                    onValueChange = { keyDraft = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Type to Mac") },
                    singleLine = true,
                )
                IconButton(
                    onClick = {
                        if (keyDraft.isNotEmpty()) {
                            vm.sendKey(keyDraft)
                            keyDraft = ""
                        }
                    },
                ) {
                    Icon(Icons.Default.Send, contentDescription = "Send keys")
                }
            }
        }
    }
}
