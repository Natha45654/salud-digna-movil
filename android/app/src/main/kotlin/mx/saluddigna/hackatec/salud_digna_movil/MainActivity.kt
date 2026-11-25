package mx.saluddigna.hackatec.salud_digna_movil

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Abre WhatsApp (https://wa.me/...) o el marcador (tel:...) sin
        // dependencias externas. ACTION_DIAL solo muestra el número: no llama
        // ni requiere permisos.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.saluddigna/launch")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = Uri.parse(call.argument<String>("uri") ?: "")
                val action = if (uri.scheme == "tel") Intent.ACTION_DIAL else Intent.ACTION_VIEW
                try {
                    startActivity(Intent(action, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
