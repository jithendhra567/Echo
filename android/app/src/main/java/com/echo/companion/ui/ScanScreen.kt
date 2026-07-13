package com.echo.companion.ui

import android.Manifest
import android.content.pm.PackageManager
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.echo.companion.protocol.PairingPayload
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@Composable
fun ScanScreen(
    onPaired: (PairingPayload) -> Unit,
    onBack: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    var manual by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var hasCamera by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasCamera = granted }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(20.dp),
    ) {
        Text("Echo", style = MaterialTheme.typography.displayLarge)
        Text(
            "Scan the QR from Echo → Dashboard → Phone",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (hasCamera) {
                QrCamera(
                    onCode = { raw ->
                        val payload = PairingPayload.parse(raw)
                        if (payload != null) onPaired(payload)
                        else error = "Not an Echo pairing code"
                    }
                )
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Camera permission needed", textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                        Text("Allow camera")
                    }
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text("Or paste the pairing link", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(
            value = manual,
            onValueChange = { manual = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
            singleLine = true,
            placeholder = { Text("echo://pair?…") },
        )
        Button(
            onClick = {
                val payload = PairingPayload.parse(manual)
                if (payload != null) onPaired(payload)
                else error = "Could not parse pairing link"
            },
            Modifier
                .fillMaxWidth()
                .padding(top = 12.dp),
        ) {
            Text("Connect")
        }
        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
        }
        onBack?.let {
            TextButton(onClick = it, modifier = Modifier.padding(top = 8.dp)) {
                Text("Cancel")
            }
        }
    }
}

@Composable
private fun QrCamera(onCode: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val handled = remember { AtomicBoolean(false) }
    val executor = remember { Executors.newSingleThreadExecutor() }

    DisposableEffect(Unit) {
        onDispose { executor.shutdown() }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val analysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(1280, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                val scanner = BarcodeScanning.getClient()
                analysis.setAnalyzer(executor) { imageProxy ->
                    val media = imageProxy.image
                    if (media != null && !handled.get()) {
                        val image = InputImage.fromMediaImage(media, imageProxy.imageInfo.rotationDegrees)
                        scanner.process(image)
                            .addOnSuccessListener { barcodes ->
                                val raw = barcodes.firstOrNull()?.rawValue
                                if (raw != null && handled.compareAndSet(false, true)) {
                                    onCode(raw)
                                }
                            }
                            .addOnCompleteListener { imageProxy.close() }
                    } else {
                        imageProxy.close()
                    }
                }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
    )
}
