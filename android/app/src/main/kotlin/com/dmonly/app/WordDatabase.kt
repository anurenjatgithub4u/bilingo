package com.dmonly.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray

data class Word(val id: Long, val lang: String, val word: String, val meaning: String)

/** Lifetime progress. "Learned" = distinct words shown at least once. */
data class Stats(
    val totalShown: Int,
    val learned: Map<String, Int>,
    val available: Map<String, Int>,
)

/**
 * Local SQLite store of words. Seeded once from assets/words.json, so adding
 * words later is a JSON edit plus a DB_VERSION bump and an onUpgrade that seeds the new rows. Words are served
 * least-shown-first (random among ties) so nothing repeats until every word
 * in the chosen languages has been seen. Words the user marked as known or
 * hidden ([STATUS_KNOWN], [STATUS_HIDDEN]) are never picked again until restored.
 */
class WordDatabase private constructor(private val context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE words (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "lang TEXT NOT NULL, " +
                "word TEXT NOT NULL, " +
                "meaning TEXT NOT NULL, " +
                "shown INTEGER NOT NULL DEFAULT 0, " +
                "status INTEGER NOT NULL DEFAULT 0, " +
                "level INTEGER NOT NULL DEFAULT 2)"
        )
        db.execSQL("CREATE INDEX idx_words_lang_shown ON words(lang, shown)")
        seed(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v2 added Hindi. Insert only the new language so existing counts survive.
        if (oldVersion < 2) seed(db, only = setOf("hi"))
        // v3 added per-word user control (known / hidden).
        if (oldVersion < 3) db.execSQL("ALTER TABLE words ADD COLUMN status INTEGER NOT NULL DEFAULT 0")
        // v4 added a difficulty level (1 beginner, 2 intermediate, 3 advanced) for the learning path.
        if (oldVersion < 4) {
            db.execSQL("ALTER TABLE words ADD COLUMN level INTEGER NOT NULL DEFAULT 2")
            applyLevels(db)
        }
        // v5 added about 100 words per language; existing words keep their progress.
        if (oldVersion < 5) seedMissing(db)
    }

    /** Inserts seed words that are not in the table yet (matched by language and word). */
    private fun seedMissing(db: SQLiteDatabase) {
        val existing = HashSet<String>()
        db.rawQuery("SELECT lang, word FROM words", null).use {
            while (it.moveToNext()) existing += it.getString(0) + "|" + it.getString(1)
        }
        val array = seedArray()
        db.beginTransaction()
        try {
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                if (item.getString("lang") + "|" + item.getString("word") in existing) continue
                db.insert("words", null, ContentValues().apply {
                    put("lang", item.getString("lang"))
                    put("word", item.getString("word"))
                    put("meaning", item.getString("meaning"))
                    put("level", item.optInt("level", 2))
                })
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun seedArray(): JSONArray =
        JSONArray(context.assets.open(SEED_ASSET).bufferedReader().use { it.readText() })

    private fun applyLevels(db: SQLiteDatabase) {
        val array = seedArray()
        db.beginTransaction()
        try {
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                db.execSQL(
                    "UPDATE words SET level = ? WHERE lang = ? AND word = ?",
                    arrayOf<Any>(item.optInt("level", 2), item.getString("lang"), item.getString("word")),
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun seed(db: SQLiteDatabase, only: Set<String>? = null) {
        val array = seedArray()
        db.beginTransaction()
        try {
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                if (only != null && item.getString("lang") !in only) continue
                db.insert("words", null, ContentValues().apply {
                    put("lang", item.getString("lang"))
                    put("word", item.getString("word"))
                    put("meaning", item.getString("meaning"))
                put("level", item.optInt("level", 2))
                })
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Words in [languages] that can still be shown. */
    fun count(languages: Set<String>): Int {
        val (clause, args) = activeFilter(languages)
        readableDatabase.rawQuery("SELECT COUNT(*) FROM words WHERE $clause", args).use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    fun stats(): Stats {
        val learned = Languages.all.associate { it.code to 0 }.toMutableMap()
        val available = Languages.all.associate { it.code to 0 }.toMutableMap()
        var total = 0
        readableDatabase.rawQuery(
            // Hidden words drop out of the totals; known words count as learned.
            "SELECT lang, SUM(CASE WHEN status != $STATUS_HIDDEN THEN 1 ELSE 0 END), " +
                "SUM(CASE WHEN status != $STATUS_HIDDEN AND (shown > 0 OR status = $STATUS_KNOWN) " +
                "THEN 1 ELSE 0 END), SUM(shown) FROM words GROUP BY lang",
            null,
        ).use {
            while (it.moveToNext()) {
                available[it.getString(0)] = it.getInt(1)
                learned[it.getString(0)] = it.getInt(2)
                total += it.getInt(3)
            }
        }
        return Stats(total, learned, available)
    }

    /** Picks the next word and records that it was shown. Null if none match. */
    @Synchronized
    fun nextWord(languages: Set<String>, excludeId: Long = -1): Word? {
        val (clause, args) = activeFilter(languages)
        val db = writableDatabase
        // Least-shown first, but never the word that was just shown (matters when a new
        // cycle starts and every word is tied). Falls back if it is the only word left.
        val word = query(db, "$clause AND id != ?", args + excludeId.toString())
            ?: query(db, clause, args)
            ?: return null
        db.execSQL("UPDATE words SET shown = shown + 1 WHERE id = ?", arrayOf<Any>(word.id))
        return word
    }

    /**
     * Words in [languages] whose text matches [text], best match first: exact, prefix,
     * then anywhere. Meanings are searched too once the query is long enough to be useful.
     * Hidden words are left out.
     */
    fun search(text: String, languages: Set<String>, limit: Int = 5): List<Word> {
        val q = text.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val like = "%$q%"
        val (langClause, langArgs) = languageFilter(languages)
        val meaningClause = if (q.length >= 3) " OR LOWER(meaning) LIKE ?" else ""
        val whereArgs = if (q.length >= 3) arrayOf(like, like) else arrayOf(like)
        readableDatabase.rawQuery(
            "SELECT id, lang, word, meaning FROM words WHERE $langClause AND status != $STATUS_HIDDEN " +
                "AND (LOWER(word) LIKE ?$meaningClause) " +
                "ORDER BY CASE WHEN LOWER(word) = ? THEN 0 WHEN LOWER(word) LIKE ? THEN 1 " +
                "WHEN LOWER(word) LIKE ? THEN 2 ELSE 3 END, LENGTH(word) LIMIT ?",
            langArgs + whereArgs + arrayOf(q, "$q%", like, limit.toString()),
        ).use {
            val words = mutableListOf<Word>()
            while (it.moveToNext()) {
                words += Word(it.getLong(0), it.getString(1), it.getString(2), it.getString(3))
            }
            return words
        }
    }

    /** A least-seen word for in-app browsing; unlike [nextWord] it is not counted as shown. */
    fun peekWord(languages: Set<String>): Word? {
        val (clause, args) = activeFilter(languages)
        return query(readableDatabase, clause, args)
    }

    /** Marks a word known, hidden, or back to active ([STATUS_ACTIVE]). */
    fun setStatus(id: Long, status: Int) {
        writableDatabase.execSQL("UPDATE words SET status = ? WHERE id = ?", arrayOf<Any>(status, id))
    }

    /** Same as [setStatus], for callers (Flutter) that only know the word itself. */
    fun setStatus(lang: String, word: String, status: Int) {
        writableDatabase.execSQL(
            "UPDATE words SET status = ? WHERE lang = ? AND word = ?",
            arrayOf<Any>(status, lang, word),
        )
    }

    fun isActive(id: Long): Boolean =
        readableDatabase.rawQuery("SELECT status FROM words WHERE id = ?", arrayOf(id.toString())).use {
            it.moveToFirst() && it.getInt(0) == STATUS_ACTIVE
        }

    /** Every word with [status], alphabetically within each language. */
    fun wordsWithStatus(status: Int): List<Word> =
        readableDatabase.rawQuery(
            "SELECT id, lang, word, meaning FROM words WHERE status = ? ORDER BY lang, LOWER(word)",
            arrayOf(status.toString()),
        ).use {
            val words = mutableListOf<Word>()
            while (it.moveToNext()) {
                words += Word(it.getLong(0), it.getString(1), it.getString(2), it.getString(3))
            }
            words
        }

    /** Every word in [lang] except hidden ones, easiest first, as (word, level) for the learning path. */
    fun pathWords(lang: String): List<Pair<Word, Int>> =
        readableDatabase.rawQuery(
            "SELECT id, lang, word, meaning, level FROM words WHERE lang = ? AND status != $STATUS_HIDDEN " +
                "ORDER BY level, id",
            arrayOf(lang),
        ).use {
            val words = mutableListOf<Pair<Word, Int>>()
            while (it.moveToNext()) {
                words += Word(it.getLong(0), it.getString(1), it.getString(2), it.getString(3)) to it.getInt(4)
            }
            words
        }

    private fun query(db: SQLiteDatabase, where: String, args: Array<String>): Word? =
        db.rawQuery(
            "SELECT id, lang, word, meaning FROM words WHERE $where " +
                "ORDER BY shown ASC, RANDOM() LIMIT 1",
            args,
        ).use {
            if (it.moveToFirst()) Word(it.getLong(0), it.getString(1), it.getString(2), it.getString(3))
            else null
        }

    private fun languageFilter(languages: Set<String>): Pair<String, Array<String>> {
        val langs = languages.intersect(Languages.codes).ifEmpty { Languages.codes }.toTypedArray()
        return "lang IN (${langs.joinToString(",") { "?" }})" to langs
    }

    /** [languageFilter] limited to words the user has not marked known or hidden. */
    private fun activeFilter(languages: Set<String>): Pair<String, Array<String>> {
        val (clause, args) = languageFilter(languages)
        return "$clause AND status = $STATUS_ACTIVE" to args
    }

    companion object {
        private const val DB_NAME = "words.db"
        private const val DB_VERSION = 5
        private const val SEED_ASSET = "words.json"

        const val STATUS_ACTIVE = 0
        const val STATUS_KNOWN = 1
        const val STATUS_HIDDEN = 2

        @Volatile private var instance: WordDatabase? = null

        fun get(context: Context): WordDatabase =
            instance ?: synchronized(this) {
                instance ?: WordDatabase(context.applicationContext).also { instance = it }
            }
    }
}
