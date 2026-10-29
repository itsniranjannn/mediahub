package com.example.mediahub

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var mediaStoreChannel: MediaStoreChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaStoreChannel = MediaStoreChannel(context, flutterEngine.dartExecutor.binaryMessenger)
    }
}
