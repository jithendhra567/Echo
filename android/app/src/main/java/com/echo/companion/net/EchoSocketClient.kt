package com.echo.companion.net

import com.echo.companion.protocol.CompanionMessage
import com.echo.companion.protocol.PairingPayload
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class EchoSocketClient(
    private val onMessage: (CompanionMessage) -> Unit,
    private val onState: (State) -> Unit,
) {
    enum class State { Idle, Connecting, Connected, Failed, Closed }

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    private val open = AtomicBoolean(false)
    private var pairing: PairingPayload? = null

    fun connect(payload: PairingPayload, deviceName: String) {
        disconnect()
        pairing = payload
        onState(State.Connecting)
        val request = Request.Builder().url(payload.wsUrl).build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                open.set(true)
                onState(State.Connected)
                send(CompanionMessage.Hello(payload.token, deviceName))
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                CompanionMessage.parse(text)?.let(onMessage)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                open.set(false)
                onState(State.Failed)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                open.set(false)
                onState(State.Closed)
            }
        })
    }

    fun send(message: CompanionMessage) {
        socket?.send(message.toJson())
    }

    fun disconnect() {
        open.set(false)
        socket?.close(1000, "bye")
        socket = null
        onState(State.Closed)
    }

    fun isOpen(): Boolean = open.get()
}
