package dev.folio.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage Access Framework grants are scoped to a single pick. Durable reuse
 * requires takePersistableUriPermission at pick time.
 */
class DocumentHandlePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "persistUriPermission" -> {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
          result.error("bad_args", "uri missing", null); return
        }
        try {
          context.contentResolver.takePersistableUriPermission(
            Uri.parse(uriString),
            Intent.FLAG_GRANT_READ_URI_PERMISSION
          )
          result.success(null)
        } catch (e: SecurityException) {
          result.error("revoked", e.message, null)
        }
      }

      "openContentUri" -> {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
          result.error("bad_args", "uri missing", null); return
        }
        val uri = Uri.parse(uriString)
        val held = context.contentResolver.persistedUriPermissions.any {
          it.uri == uri && it.isReadPermission
        }
        if (!held) {
          result.error("revoked", "no persisted read permission", null); return
        }
        try {
          // Copy into cache so the Dart side receives a plain readable path.
          val cached = File(context.cacheDir, "saf_${uri.hashCode()}.pdf")
          context.contentResolver.openInputStream(uri).use { input ->
            if (input == null) {
              result.error("missing", "cannot open stream", null); return
            }
            cached.outputStream().use { input.copyTo(it) }
          }
          result.success(cached.absolutePath)
        } catch (e: SecurityException) {
          result.error("revoked", e.message, null)
        } catch (e: java.io.FileNotFoundException) {
          result.error("missing", e.message, null)
        }
      }

      else -> result.notImplemented()
    }
  }
}

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.folio.app/handles")
      .setMethodCallHandler(DocumentHandlePlugin(applicationContext))
  }
}
