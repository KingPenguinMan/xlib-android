package dev.bookisle.bookisle

import android.app.Activity
import android.content.*
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.content.ContentValues
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    companion object {
        private val records = java.util.concurrent.ConcurrentHashMap<String, JSONObject>()
        private var restored = false
        private const val CHANNEL = "dev.bookisle/native"
        private const val PICK_DIRECTORY = 1441
        private const val REQUEST_STORAGE_PERMISSION = 1442
        private const val PICK_BOOK_FILE = 1443
        private const val WEREAD_KEY_ALIAS = "bookisle_weread_session"
    }
    private data class PendingDownload(
        val id: String,
        val url: String,
        val fileName: String,
        val headers: Map<*, *>?
    )
    private val executor = Executors.newCachedThreadPool()
    private lateinit var prefs: android.content.SharedPreferences
    private val pendingStorageDownloads = mutableListOf<PendingDownload>()
    private var storagePermissionRequestInFlight = false
    private var pendingDirectory: MethodChannel.Result? = null
    private var pendingBookFile: MethodChannel.Result? = null

    override fun onCreate(state: Bundle?) { super.onCreate(state); prefs = getSharedPreferences("bookisle", MODE_PRIVATE); loadRecords() }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "appVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "loadSettings" -> result.success(prefs.getString("settings", "{}"))
                "saveSettings" -> { prefs.edit().putString("settings", call.arguments as? String ?: "{}").apply(); result.success(null) }
                "loadSession" -> result.success(prefs.getString("session", null))
                "saveSession" -> { val value = call.arguments as? String; prefs.edit().apply { if (value == null) remove("session") else putString("session", value) }.apply(); result.success(null) }
                "chooseDirectory" -> chooseDirectory(result)
                "resetDirectory" -> { prefs.edit().remove("directory").remove("directoryLabel").apply(); result.success(null) }
                "directoryLabel" -> result.success(directoryLabel())
                "listDownloads" -> result.success(JSONArray(records.values.map { it }).toString())
                "download" -> startDownload(call.arguments as Map<*, *>, result)
                "cancelDownload" -> { cancelDownload(call.arguments as? String ?: ""); result.success(null) }
                "pauseDownload" -> { setDownloadState(call.arguments as? String ?: "", "paused"); result.success(null) }
                "resumeDownload" -> { setDownloadState(call.arguments as? String ?: "", "running"); result.success(null) }
                "readerCache" -> {
                    val dir = File(cacheDir,"read-preview")
                    dir.mkdirs()
                    dir.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000L }?.forEach { it.delete() }
                    result.success(dir.absolutePath)
                }
                "openPreview" -> {
                    val args = call.arguments as Map<*, *>
                    startActivity(Intent(this, BookReaderActivity::class.java).apply {
                        for (key in listOf("path","title","format")) putExtra(key,args[key] as? String)
                    })
                    result.success(null)
                }
                "fileAvailable" -> {
                    val uri = Uri.parse(call.arguments as? String ?: "")
                    result.success(try { contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false } catch (_: Exception) { false })
                }
                "openFile" -> openFile(call.arguments as Map<*, *>, result)
                "shareFile" -> shareFile(call.arguments as Map<*, *>, result)
                "removeRecord" -> {
                    val args = call.arguments
                    if (args is Map<*, *>) removeRecord(args["id"] as? String ?: "", args["deleteFile"] as? Boolean == true)
                    else removeRecord(args as? String ?: "", false)
                    result.success(null)
                }
                "openUrl" -> openUrl(call.arguments as? String ?: "", result)
                "openWeread" -> openWeread(call.arguments as? String ?: "", result)
                "readWereadSession" -> result.success(readWereadSession())
                "writeWereadSession" -> { writeWereadSession(call.arguments as? String ?: ""); result.success(null) }
                "deleteWereadSession" -> { prefs.edit().remove("wereadSession").apply(); result.success(null) }
                "pickBookFile" -> pickBookFile(result)
                else -> result.notImplemented()
            }
        }
    }
    // 打开外部链接（网页，或微信读书的 weread:// 深链）。
    // 没装对应应用时返回错误而不是崩溃，交给 Dart 侧回退到网页版。
    private fun openUrl(url: String, result: MethodChannel.Result) {
        if (url.isEmpty()) { result.error("EMPTY", "链接为空", null); return }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            result.success(null)
        } catch (_: android.content.ActivityNotFoundException) {
            result.error("NO_APP", "没有可以打开这个链接的应用", null)
        }
    }

    // 直接用微信读书 App（com.tencent.weread）打开深链，不经过系统选择器、
    // 不会被浏览器抢走。返回是否成功（没装微信读书返回 false）。
    private fun openWeread(url: String, result: MethodChannel.Result) {
        if (url.isEmpty()) { result.success(false); return }
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                setPackage("com.tencent.weread")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun loadRecords() {
        if (restored) return
        val saved = runCatching { JSONArray(prefs.getString("downloads", "[]")) }.getOrElse { JSONArray() }
        for (i in 0 until saved.length()) {
            val record = saved.optJSONObject(i) ?: continue
            if (record.optString("status") in listOf("queued","running","paused")) {
                record.put("status","failed")
                record.put("error","上次下载被中断，点击重试可重新获取文件")
            }
            records[record.optString("id")] = record
        }
        // Previous versions appended a failed row on every retry. Keep only
        // the newest failure per book, and preserve all completed files.
        val failures = records.values.filter { it.optString("status") == "failed" }
            .groupBy { it.optJSONObject("book")?.optString("id").orEmpty() }
        for ((bookId, rows) in failures) {
            if (bookId.isBlank()) continue
            rows.sortedByDescending { it.optLong("created") }.drop(1)
                .forEach { records.remove(it.getString("id")) }
        }
        restored = true
        saveRecords()
    }
    private fun saveRecords() = synchronized(records) {
        prefs.edit().putString("downloads", JSONArray(records.values.toList()).toString()).apply()
    }
    private fun directoryLabel(): String = prefs.getString("directoryLabel", null)
        ?: "Download/Books"
    private fun directoryUri(): Uri? = prefs.getString("directory", null)?.let { Uri.parse(it) }
    private fun chooseDirectory(result: MethodChannel.Result) { pendingDirectory = result; startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }, PICK_DIRECTORY) }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) { super.onActivityResult(requestCode, resultCode, data); if (requestCode == PICK_BOOK_FILE) { handleBookFile(resultCode, data); return }; if (requestCode != PICK_DIRECTORY) return; val callback = pendingDirectory; pendingDirectory = null; if (resultCode != Activity.RESULT_OK || data?.data == null) { callback?.success(null); return }; val uri = data.data!!; try { contentResolver.takePersistableUriPermission(uri, data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) } catch (_: Exception) {}; val label = queryTreeName(uri) ?: "自定义下载目录"; prefs.edit().putString("directory", uri.toString()).putString("directoryLabel", label).apply(); callback?.success(mapOf("uri" to uri.toString(), "label" to label)) }
    private fun queryTreeName(uri: Uri): String? = try { contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } } catch (_: Exception) { null }
    private fun startDownload(args: Map<*, *>, result: MethodChannel.Result) {
        val bookJson = JSONObject(args["book"] as? String ?: "{}")
        val bookId = bookJson.optString("id")
        val matching = records.values.filter {
            bookId.isNotBlank() && it.optJSONObject("book")?.optString("id") == bookId
        }
        if (matching.any { it.optString("status") in setOf("queued", "running", "paused") }) {
            result.error("already_downloading", "这本书已经在下载队列中", null)
            return
        }
        val retry = matching.firstOrNull { it.optString("status") == "failed" }
        val id = retry?.getString("id") ?: UUID.randomUUID().toString()
        val title = args["title"] as? String ?: "图书"
        val fileName = args["fileName"] as? String ?: "book.bin"
        val url = args["url"] as? String ?: ""
        val obj = JSONObject().apply {
            put("id", id); put("title", title); put("status", "queued"); put("uri", "")
            put("error", ""); put("fileName", fileName); put("received", 0); put("total", 0)
            put("origin",args["origin"]); put("created", System.currentTimeMillis()); put("book", bookJson); put("path", "")
        }
        records[id] = obj; saveRecords(); result.success(null)
        val pending = PendingDownload(id, url, fileName, args["headers"] as? Map<*, *>)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            pendingStorageDownloads.add(pending)
            if (!storagePermissionRequestInFlight) {
                storagePermissionRequestInFlight = true
                requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_STORAGE_PERMISSION)
            }
        } else {
            executor.execute { performDownload(id, url, fileName, pending.headers) }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_STORAGE_PERMISSION) return
        storagePermissionRequestInFlight = false
        val queued = pendingStorageDownloads.toList()
        pendingStorageDownloads.clear()
        if (grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            queued.forEach { task -> executor.execute { performDownload(task.id, task.url, task.fileName, task.headers) } }
        } else {
            queued.forEach { task ->
                records[task.id]?.apply { put("status", "failed"); put("error", "需要允许存储权限才能保存到 Download/Books") }
            }
            saveRecords()
        }
    }
    private fun cancelDownload(id: String) { records.remove(id); saveRecords() }
    private fun setDownloadState(id: String, state: String) {
        records[id]?.put("status", state); saveRecords()
    }
    private fun performDownload(id: String, urlString: String, fileName: String, rawHeaders: Map<*, *>?, attempt: Int = 0) {
        val record = records[id] ?: return
        var createdUri: Uri? = null
        var connection: HttpURLConnection? = null
        try {
            while (records[id]?.optString("status") == "paused") Thread.sleep(250)
            if (!records.containsKey(id)) return
            record.put("status", "running"); record.put("error", ""); record.put("received", 0); saveRecords()
            val origin = Uri.parse(record.optString("origin"))
            var targetUrl = Uri.parse(urlString)
            var redirectCount = 0
            while (true) {
                require(targetUrl.scheme == "https" && !targetUrl.host.isNullOrBlank() && targetUrl.userInfo == null) { "下载地址无效" }
                val next = URL(targetUrl.toString()).openConnection() as HttpURLConnection
                connection = next
                next.connectTimeout = 15000; next.readTimeout = 120000; next.instanceFollowRedirects = false
                next.useCaches = false
                next.setRequestProperty("Accept-Encoding","identity")
                rawHeaders?.forEach { (k,v) ->
                    if (v != null && k != null && (targetUrl.authority == origin.authority || k.toString().equals("User-Agent", true)))
                        next.setRequestProperty(k.toString(),v.toString())
                }
                if (next.responseCode !in listOf(301,302,303,307,308)) break
                require(++redirectCount <= 5) { "下载地址跳转过多" }
                targetUrl = Uri.parse(URL(next.url, requireNotNull(next.getHeaderField("Location"))).toString())
                next.disconnect()
            }
            val conn = requireNotNull(connection)
            if (conn.responseCode !in 200..299) throw IllegalStateException("HTTP ${conn.responseCode}：下载链接不可用，请重新获取链接或切换线路")
            val total = conn.contentLengthLong
            record.put("total", if (total > 0) total else 0); saveRecords()
            val tree = directoryUri(); var outputUri: Uri? = null; var local: File? = null
            if (tree != null) {
                outputUri = try {
                    val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                    DocumentsContract.createDocument(contentResolver, parent, mime(fileName), fileName)
                } catch (_: IllegalArgumentException) {
                    null
                } catch (_: SecurityException) {
                    null
                }
            }
            if (tree != null && outputUri == null) throw IllegalStateException("无法写入已选目录，请在侧边栏重新选择下载目录")
            if (outputUri == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime(fileName))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Books")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                outputUri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("无法创建 Download/Books 文件")
                createdUri = outputUri
                record.put("displayPath", "Download/Books/$fileName")
            }
            if (outputUri == null) {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Books")
                dir.mkdirs()
                val original = File(dir, fileName)
                var target = original
                var suffix = 1
                while (!target.createNewFile()) {
                    target = File(dir, "${original.nameWithoutExtension} (${suffix++}).${original.extension}")
                }
                local = target
                record.put("fileName", target.name)
                record.put("path", local.absolutePath)
                outputUri = FileProvider.getUriForFile(this, "dev.bookisle.bookisle.fileprovider", local)
                createdUri = outputUri
            }
            if (createdUri == null) createdUri = outputUri
            val out = if (local != null) FileOutputStream(local) else contentResolver.openOutputStream(outputUri!!) ?: throw IllegalStateException("无法打开下载目录")
            conn.inputStream.use { input -> out.use { output ->
                val buffer = ByteArray(256 * 1024); var received = 0L
                var lastSaved = System.currentTimeMillis()
                while (true) {
                    if (!records.containsKey(id) || records[id]?.optString("status") == "cancelled") throw InterruptedException("cancelled")
                    while (records[id]?.optString("status") == "paused") {
                        Thread.sleep(250)
                    }
                    if (!records.containsKey(id)) throw InterruptedException("cancelled")
                    val count = input.read(buffer); if (count < 0) break
                    output.write(buffer, 0, count); received += count
                    val now = System.currentTimeMillis()
                    if (received - record.optLong("received") >= 1024 * 1024 || now - lastSaved >= 1000) {
                        records[id]?.put("received", received); saveRecords(); lastSaved = now
                    }
                }
                if (received == 0L) throw java.io.EOFException("下载文件为空")
                if (total > 0 && received != total) throw java.io.EOFException("下载中断，文件不完整")
                record.put("received", received)
            } }
            val finalUri = outputUri ?: throw IllegalStateException("下载文件位置不可用")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && finalUri.authority == MediaStore.AUTHORITY) {
                contentResolver.update(finalUri, ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }, null, null)
            }
            record.put("received", if (total > 0) total else record.optLong("received"))
            record.put("status", "complete"); record.put("uri", finalUri.toString()); saveRecords()
        } catch (e: InterruptedException) {
            try {
                createdUri?.let { contentResolver.delete(it, null, null) }
                record.optString("path").takeIf { it.isNotEmpty() }?.let { File(it).delete() }
            } catch (_: Exception) { }
            record.put("status", "cancelled"); record.put("error", "已取消"); saveRecords()
        }
        catch (e: Exception) {
            try {
                createdUri?.let { contentResolver.delete(it, null, null) }
                record.optString("path").takeIf { it.isNotEmpty() }?.let { File(it).delete() }
            } catch (_: Exception) { }
            connection?.disconnect()
            if (!records.containsKey(id)) return
            if ((e is java.net.SocketException || e is java.net.SocketTimeoutException ||
                    e is java.net.UnknownHostException || e is java.io.EOFException) && attempt < 3) {
                record.put("error", "网络中断，${5 * (attempt + 1)} 秒后自动重新下载（${attempt + 1}/3）")
                record.put("received", 0); saveRecords()
                var remaining = 5 * (attempt + 1) * 4
                while (remaining > 0) {
                    if (!records.containsKey(id)) return
                    Thread.sleep(250)
                    if (record.optString("status") != "paused") remaining--
                }
                performDownload(id, urlString, fileName, rawHeaders, attempt + 1)
            } else {
                record.put("status", "failed"); record.put("error", "${e.message ?: "下载失败"}；可点重试重新获取链接，或在侧边栏检测线路"); saveRecords()
            }
        } finally {
            connection?.disconnect()
        }
    }
    private fun mime(file: String): String {
        val ext = file.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }
    private fun removeRecord(id: String, deleteFile: Boolean) {
        val record = records[id]
        if (deleteFile && record != null) {
            val path = record.optString("path")
            try {
                if (path.isNotEmpty()) File(path).delete()
                else {
                    val rawUri = record.optString("uri")
                    if (rawUri.isNotEmpty()) {
                        val uri = Uri.parse(rawUri)
                        if (uri.authority == MediaStore.AUTHORITY) contentResolver.delete(uri, null, null)
                        else DocumentsContract.deleteDocument(contentResolver, uri)
                    }
                }
            } catch (_: Exception) { }
        }
        records.remove(id); saveRecords()
    }
    private fun openFile(args: Map<*, *>, result: MethodChannel.Result) {
        val uri = Uri.parse(args["uri"] as? String ?: "")
        val type = mime(args["fileName"] as? String ?: "")
        try {
            startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, type); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, "打开图书"))
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/octet-stream"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }, "选择应用打开"))
                result.success(null)
            } catch (_: Exception) {
                result.error("NO_READER", "设备上没有可以打开此文件的阅读器，请先安装 PDF/EPUB 阅读器", null)
            }
        }
    }
    private fun shareFile(args: Map<*, *>, result: MethodChannel.Result) {
        val uri = Uri.parse(args["uri"] as? String ?: "")
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = mime(args["fileName"] as? String ?: ""); putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }, "分享图书"))
        result.success(null)
    }

    // ── 本地书籍导入：选文件后复制到 cache，Dart 侧再流式上传到微信读书 ──
    private fun pickBookFile(result: MethodChannel.Result) {
        pendingBookFile = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }, PICK_BOOK_FILE)
    }
    private fun handleBookFile(resultCode: Int, data: Intent?) {
        val callback = pendingBookFile
        pendingBookFile = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { callback?.success(null); return }
        executor.execute {
            try {
                val name = queryOpenableName(uri) ?: "book.bin"
                val dir = File(cacheDir, "weread-import").apply { mkdirs() }
                val target = File(dir, name.replace(Regex("[/\\\\]"), "_"))
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output, 256 * 1024) }
                } ?: throw IllegalStateException("无法读取所选文件")
                runOnUiThread { callback?.success(mapOf("path" to target.absolutePath, "name" to name, "size" to target.length())) }
            } catch (e: Exception) {
                runOnUiThread { callback?.error("PICK_FAILED", e.message ?: "读取文件失败", null) }
            }
        }
    }
    private fun queryOpenableName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (_: Exception) { null }

    // ── 微信读书登录凭据：AES-GCM 加密后存进私有 prefs，密钥留在 AndroidKeyStore ──
    private fun wereadKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(WEREAD_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(WEREAD_KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }
    private fun readWereadSession(): String? {
        val raw = prefs.getString("wereadSession", null) ?: return null
        return try {
            val bytes = Base64.decode(raw, Base64.NO_WRAP)
            val iv = bytes.copyOfRange(0, 12)
            val payload = bytes.copyOfRange(12, bytes.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, wereadKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(payload), Charsets.UTF_8)
        } catch (e: Exception) {
            // 密钥被系统清除（换机、重置生物识别）后旧密文无法解开，按未连接处理。
            prefs.edit().remove("wereadSession").apply()
            null
        }
    }
    private fun writeWereadSession(value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wereadKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val bytes = cipher.iv + encrypted
        prefs.edit().putString("wereadSession", Base64.encodeToString(bytes, Base64.NO_WRAP)).apply()
    }
}
