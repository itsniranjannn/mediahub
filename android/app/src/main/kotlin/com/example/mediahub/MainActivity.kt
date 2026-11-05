package com.example.mediahub

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.mediahub.personal.ExtractorChannel

class MainActivity : AudioServiceActivity() {
    private var mediaStoreChannel: MediaStoreChannel? = null
    private var downloadServiceChannel: DownloadServiceChannel? = null
    private var extractorChannel: ExtractorChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaStoreChannel = MediaStoreChannel(context, flutterEngine.dartExecutor.binaryMessenger)
        downloadServiceChannel = DownloadServiceChannel(context, flutterEngine.dartExecutor.binaryMessenger)
        if (ExtractorChannel.PERSONAL_TOOLS) {
            extractorChannel = ExtractorChannel(context, flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun onDestroy() {
        downloadServiceChannel?.cleanup()
        downloadServiceChannel = null
        extractorChannel?.cleanup()
        extractorChannel = null
        super.onDestroy()
    }
}
