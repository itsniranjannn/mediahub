// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
package com.example.mediahub

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Receives "Share to MediaHub" (ACTION_SEND text/plain) and hands only the text to
 * [MainActivity], then finishes without drawing anything.
 *
 * Why not a filter on MainActivity itself: a share starts its target in the SHARING app's
 * task, which would create a second MainActivity there, taking over the one cached engine
 * (music, the media session, picture-in-picture) from the one already running. Started
 * from here with NEW_TASK, MainActivity's own task comes to the front instead (singleTop:
 * onNewIntent when it is already showing, onCreate on a cold start).
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = SharedLinkChannel.sharedText(intent)
        if (text != null) {
            val open = Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_SHARED_TEXT
                putExtra(MainActivity.EXTRA_SHARED_TEXT, text)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            runCatching { startActivity(open) }
        }
        finish()
    }
}
