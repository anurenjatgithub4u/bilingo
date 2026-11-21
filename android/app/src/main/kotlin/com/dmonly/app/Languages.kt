package com.dmonly.app

/** The languages the app ships words for. Add an entry here plus rows in words.json. */
data class Language(val code: String, val label: String, val badge: String, val color: Int)

object Languages {
    val all = listOf(
        Language("en", "English", "EN", 0xFF3B5BDB.toInt()),
        Language("de", "Deutsch", "DE", 0xFFD9480F.toInt()),
    )

    val codes: Set<String> = all.map { it.code }.toSet()

    fun byCode(code: String): Language = all.firstOrNull { it.code == code } ?: all.first()
}
