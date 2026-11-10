package dev.bookisle.bookisle

import android.app.Activity
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.text.Html
import android.util.Xml
import android.view.Gravity
import android.widget.*
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.net.URI
import java.util.zip.ZipFile
import java.util.concurrent.Executors

/** Text-only EPUB chapters and rasterized PDF pages. All file work is serialized. */
class BookReaderActivity : Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var file: File
    private lateinit var body: ScrollView
    private lateinit var label: TextView
    private lateinit var previous: Button
    private lateinit var next: Button
    private var pdf: PdfRenderer? = null
    private var zip: ZipFile? = null
    private var chapters = emptyList<String>()
    private var index = 0
    private var count = 0
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        file = File(intent.getStringExtra("path") ?: "")
        if (!file.isFile || !file.canonicalPath.startsWith(cacheDir.canonicalPath + "/")) { finish(); return }
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        setContentView(root)
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        root.addView(header)
        header.addView(Button(this).apply { text = "返回"; setOnClickListener { finish() } })
        header.addView(TextView(this).apply { text = intent.getStringExtra("title"); textSize = 17f; maxLines = 2 })
        body = ScrollView(this)
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        val bar = LinearLayout(this).apply { gravity = Gravity.CENTER }
        root.addView(bar)
        previous = Button(this).apply { text = "上一页"; setOnClickListener { render(index - 1) } }
        next = Button(this).apply { text = "下一页"; setOnClickListener { render(index + 1) } }
        label = TextView(this)
        bar.addView(previous); bar.addView(label); bar.addView(next)
        previous.isEnabled = false; next.isEnabled = false
        label.text = "正在排版…"
        worker.execute {
            try {
                if (intent.getStringExtra("format") == "PDF") {
                    pdf = PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY))
                    count = pdf!!.pageCount
                } else {
                    zip = ZipFile(file)
                    chapters = readSpine(zip!!)
                    count = chapters.size
                }
                require(count > 0)
                runOnUiThread { if (!isDestroyed && !isFinishing) render((state?.getInt("page") ?: 0).coerceIn(0, count - 1)) }
            } catch (_: Exception) { showError("无法读取此书，文件可能损坏、加密或格式不受支持。") }
        }
    }

    private fun entryText(archive: ZipFile, name: String): String {
        val entry = requireNotNull(archive.getEntry(name))
        require(entry.size in 1..4_194_304)
        return archive.getInputStream(entry).bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    private fun readSpine(archive: ZipFile): List<String> {
        fun tags(source: String, visit: (XmlPullParser) -> Unit) {
            val parser = Xml.newPullParser()
            parser.setInput(source.reader())
            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG) visit(parser)
                parser.next()
            }
        }
        var opf: String? = null
        tags(entryText(archive, "META-INF/container.xml")) {
            if (it.name == "rootfile" && opf == null) opf = it.getAttributeValue(null, "full-path")
        }
        val path = requireNotNull(opf)
        val manifest = mutableMapOf<String, String>()
        val spine = mutableListOf<String>()
        tags(entryText(archive, path)) {
            when (it.name) {
                "item" -> {
                    val type = it.getAttributeValue(null, "media-type")
                    if (type == "application/xhtml+xml" || type == "text/html") {
                        val href = it.getAttributeValue(null, "href").replace(" ", "%20")
                        val resolved = URI(null, null, "/$path", null).resolve(href).normalize()
                        if (resolved.scheme == null && resolved.authority == null)
                            manifest[it.getAttributeValue(null,"id")] = resolved.path.trimStart('/')
                    }
                }
                "itemref" -> spine.add(it.getAttributeValue(null,"idref"))
            }
        }
        return spine.mapNotNull(manifest::get)
    }

    private fun render(page: Int) {
        index = page
        previous.isEnabled = false; next.isEnabled = false
        val width = resources.displayMetrics.widthPixels.coerceIn(320, 1600)
        val reader = pdf
        worker.execute {
            try {
                val bitmap = reader?.openPage(page)?.use {
                    val scale = minOf(width.toDouble() / it.width, 2560.0 / it.height)
                    Bitmap.createBitmap((it.width * scale).toInt().coerceAtLeast(1), (it.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888).apply {
                        eraseColor(Color.WHITE)
                        it.render(this, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    }
                }
                val text = if (bitmap == null) Html.fromHtml(entryText(zip!!, chapters[page]), Html.FROM_HTML_MODE_COMPACT) else null
                runOnUiThread {
                    if (isDestroyed || isFinishing) return@runOnUiThread
                    body.removeAllViews()
                    if (bitmap != null) body.addView(ImageView(this).apply { adjustViewBounds = true; setImageBitmap(bitmap) })
                    else body.addView(TextView(this).apply { setPadding(dp(16),dp(12),dp(16),dp(12)); textSize = 18f; setTextIsSelectable(true); this.text = text.toString().trim().ifEmpty { "本章没有可显示的文字" } })
                    body.scrollTo(0,0)
                    label.text = "  ${page + 1} / $count  "
                    previous.text = if (reader == null) "上一章" else "上一页"
                    next.text = if (reader == null) "下一章" else "下一页"
                    previous.isEnabled = page > 0; next.isEnabled = page + 1 < count
                }
            } catch (_: Exception) { showError("此页无法读取，可尝试下载后使用其他阅读器。") }
        }
    }
    private fun showError(message: String) = runOnUiThread { if (!isDestroyed && !isFinishing) label.text = message }
    override fun onSaveInstanceState(out: Bundle) { out.putInt("page",index); super.onSaveInstanceState(out) }
    override fun onDestroy() {
        val remove = !isChangingConfigurations
        worker.execute { pdf?.close(); zip?.close(); if (remove && ::file.isInitialized && file.parentFile?.canonicalPath == File(cacheDir,"read-preview").canonicalPath) file.delete() }
        worker.shutdown()
        super.onDestroy()
    }
}
