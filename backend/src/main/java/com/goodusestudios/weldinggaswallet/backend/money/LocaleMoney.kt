package com.goodusestudios.weldinggaswallet.backend.money

import com.goodusestudios.weldinggaswallet.backend.domain.*
import java.text.DecimalFormat
import java.text.NumberFormat
import java.text.ParsePosition
import java.util.Currency
import java.util.Locale
import kotlin.math.roundToLong

object LocaleMoney {
    fun javaLocale(locale: String): Locale = Locale.forLanguageTag(canonicalLocale(locale))

    fun defaultCurrencyForSystemLocale(systemLocale: String): String {
        return try {
            Currency.getInstance(Locale.forLanguageTag(systemLocale.replace('_', '-'))).currencyCode
                .takeIf { it in ISO_4217_CODES }
                ?: defaultCurrencyForLocale(systemLocale)
        } catch (_: Throwable) {
            defaultCurrencyForLocale(systemLocale)
        }
    }

    fun currencyScale(code: String): Int = when (code.uppercase(Locale.ROOT)) {
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF",
        "UGX", "VND", "VUV", "XAF", "XOF", "XPF" -> 0
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND" -> 3
        "CLF", "UYW" -> 4
        else -> 2
    }

    fun parseMajor(input: String, locale: String): Double? {
        val normalizedDigits = normalizeDigits(input.trim())
        if (normalizedDigits.isEmpty()) return null
        val format = NumberFormat.getNumberInstance(javaLocale(locale))
        val position = ParsePosition(0)
        val number = format.parse(normalizedDigits, position) ?: return null
        if (position.index != normalizedDigits.length) return null
        return number.toDouble().takeIf { it.isFinite() }
    }

    fun parseMoney(input: String, currencyCode: String, locale: String): Money? {
        if (input.isBlank()) return null
        val amount = parseMajor(input, locale) ?: return null
        if (!amount.isFinite() || amount < 0.0) return null
        val normalized = normalizedCurrency(currencyCode, "USD")
        val scale = currencyScale(normalized)
        val factor = powerOfTen(scale)
        return Money((amount * factor).roundToLong(), normalized)
    }

    fun formatMoney(money: Money, locale: String): String =
        formatMinorUnits(money.minorUnits, money.normalizedCurrencyCode, locale)

    fun formatMinorUnits(minorUnits: Long, currencyCode: String, locale: String): String {
        val scale = currencyScale(currencyCode)
        val format = NumberFormat.getCurrencyInstance(javaLocale(locale))
        return try {
            format.currency = Currency.getInstance(currencyCode)
            format.minimumFractionDigits = scale
            format.maximumFractionDigits = scale
            format.format(minorUnits.toDouble() / powerOfTen(scale))
        } catch (_: Throwable) {
            "$currencyCode ${inputValue(minorUnits, currencyCode, locale)}"
        }
    }

    fun inputValue(minorUnits: Long, currencyCode: String, locale: String): String {
        val scale = currencyScale(currencyCode)
        val format = NumberFormat.getNumberInstance(javaLocale(locale)) as DecimalFormat
        format.minimumFractionDigits = scale
        format.maximumFractionDigits = scale
        format.isGroupingUsed = true
        return format.format(minorUnits.toDouble() / powerOfTen(scale))
    }

    fun formatDecimal(value: Double, locale: String): String {
        val format = NumberFormat.getNumberInstance(javaLocale(locale)) as DecimalFormat
        format.minimumFractionDigits = 0
        format.maximumFractionDigits = 2
        return format.format(value)
    }

    private fun normalizeDigits(value: String): String = buildString {
        for (char in value) {
            val digit = Character.digit(char, 10)
            when {
                digit in 0..9 -> append(('0'.code + digit).toChar())
                char == '\u066B' -> append('.')
                char == '\u066C' -> Unit
                char == '\u00A0' || char == '\u202F' -> append(' ')
                else -> append(char)
            }
        }
    }

    private fun powerOfTen(exponent: Int): Long = when (exponent) {
        0 -> 1L
        3 -> 1_000L
        4 -> 10_000L
        else -> 100L
    }
}
