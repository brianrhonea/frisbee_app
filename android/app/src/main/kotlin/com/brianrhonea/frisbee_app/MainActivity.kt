package com.brianrhonea.frisbee_app

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stall10/notifications")
            .setMethodCallHandler { call, result ->
                val tag = call.arguments as? String
                if (call.method != "clearDelivered" || tag == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // FCM posts each notification with the message's tag (the
                // notice's collapse id, see functions/src/notifications).
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                for (n in manager.activeNotifications) {
                    // Messages are tagged "{collapse id}|{message id}".
                    if (n.tag == tag || n.tag?.startsWith("$tag|") == true) {
                        manager.cancel(n.tag, n.id)
                    }
                }
                result.success(null)
            }
    }
}
