package com.goodusestudios.weldinggaswallet.backend.storage

import com.goodusestudios.weldinggaswallet.backend.domain.*
import kotlinx.serialization.json.*
import java.nio.charset.StandardCharsets
import java.time.Instant

/** Current-schema JSON persistence/backup codec for the public Android app. */
class JsonWalletCodec : WalletBackupCodec {
    private val json = Json {
        prettyPrint = false
        explicitNulls = true
        ignoreUnknownKeys = false
    }

    fun encodePrivate(state: WalletData): String = buildJsonObject {
        put("format", JsonPrimitive(PRIVATE_FORMAT))
        put("schemaVersion", JsonPrimitive(WALLET_SCHEMA_VERSION))
        put("state", stateToJson(state, includeLocalPhotos = true, includeEntitlement = true))
    }.toString()

    fun decodePrivate(encoded: String): WalletData {
        val root = parseObject(encoded, "Private wallet store")
        require(root.string("format") == PRIVATE_FORMAT) { "Unsupported private wallet store." }
        require(root.int("schemaVersion") in MINIMUM_SUPPORTED_WALLET_SCHEMA_VERSION..WALLET_SCHEMA_VERSION) {
            "Unsupported private wallet schema."
        }
        return stateFromJson(root.objectValue("state"), includeEntitlement = true)
    }

    override fun encode(state: WalletData, exportedAt: Instant): String {
        val root = buildJsonObject {
            put("format", JsonPrimitive(BACKUP_FORMAT))
            put("schemaVersion", JsonPrimitive(WALLET_SCHEMA_VERSION))
            put("exportedAt", JsonPrimitive(exportedAt.toString()))
            put("payload", stateToJson(state, includeLocalPhotos = false, includeEntitlement = false))
        }
        val encoded = root.toString()
        require(encoded.toByteArray(StandardCharsets.UTF_8).size <= MAXIMUM_BACKUP_BYTES) { "Backup exceeds 5 MB." }
        return encoded
    }

    override fun decode(encoded: String): WalletData {
        require(encoded.toByteArray(StandardCharsets.UTF_8).size <= MAXIMUM_BACKUP_BYTES) { "Backup exceeds 5 MB." }
        val root = parseObject(encoded, "Backup")
        require(root.string("format") == BACKUP_FORMAT) { "Unknown backup format." }
        require(root.int("schemaVersion") in MINIMUM_SUPPORTED_WALLET_SCHEMA_VERSION..WALLET_SCHEMA_VERSION) {
            "Unsupported backup schema."
        }
        Instant.parse(root.string("exportedAt"))
        return stateFromJson(root.objectValue("payload"), includeEntitlement = false)
            .copy(entitlementCache = Entitlement.Free)
    }

    private fun stateToJson(
        state: WalletData,
        includeLocalPhotos: Boolean,
        includeEntitlement: Boolean,
    ): JsonObject = buildJsonObject {
        put("revision", JsonPrimitive(state.revision))
        put("settings", settingsToJson(state.settings))
        put("suppliers", JsonArray(state.suppliers.map(::supplierToJson)))
        put("cylinders", JsonArray(state.cylinders.map { cylinderToJson(it, includeLocalPhotos) }))
        put("events", JsonArray(state.events.map(::eventToJson)))
        put("reminders", JsonArray(state.reminders.map(::reminderToJson)))
        put("pendingDraft", state.pendingDraft?.let { pendingDraftToJson(it, includeLocalPhotos) } ?: JsonNull)
        put("freeEditableSelection", JsonArray(state.freeEditableSelection.map(::JsonPrimitive)))
        if (includeEntitlement) put("entitlement", entitlementToJson(state.entitlementCache))
    }

    private fun stateFromJson(root: JsonObject, includeEntitlement: Boolean): WalletData {
        val settings = settingsFromJson(root.objectValue("settings"))
        val suppliers = root.arrayValue("suppliers").map { supplierFromJson(it.asObject("supplier")) }
        val cylinders = root.arrayValue("cylinders").map { cylinderFromJson(it.asObject("cylinder")) }
        val events = root.arrayValue("events").map { eventFromJson(it.asObject("event")) }
        val reminders = root.arrayValue("reminders").map { reminderFromJson(it.asObject("reminder")) }
        val pending = root["pendingDraft"]?.takeUnless { it is JsonNull }?.let {
            pendingDraftFromJson(it.asObject("pendingDraft"))
        }
        val selection = root.arrayValue("freeEditableSelection").map {
            (it as? JsonPrimitive)?.contentOrNull ?: error("Invalid free editable selection.")
        }.distinct()
        val entitlement = if (includeEntitlement) {
            root["entitlement"]?.takeUnless { it is JsonNull }?.let { entitlementFromJson(it.asObject("entitlement")) }
                ?: Entitlement.Free
        } else Entitlement.Free
        val state = WalletData(
            schemaVersion = WALLET_SCHEMA_VERSION,
            revision = root.int("revision"),
            settings = settings,
            suppliers = suppliers,
            cylinders = cylinders,
            events = events,
            reminders = reminders,
            pendingDraft = pending,
            freeEditableSelection = selection,
            entitlementCache = entitlement,
        )
        validateReferences(state)
        return state
    }

    private fun settingsToJson(value: AppSettings) = buildJsonObject {
        put("locale", JsonPrimitive(value.locale))
        put("currencyCode", JsonPrimitive(value.currencyCode))
        put("defaultMassUnit", JsonPrimitive(value.defaultMassUnit))
        put("defaultVolumeUnit", JsonPrimitive(value.defaultVolumeUnit))
        put("remindersEnabled", JsonPrimitive(value.remindersEnabled))
        put("onboardingComplete", JsonPrimitive(value.onboardingComplete))
    }

    private fun settingsFromJson(value: JsonObject): AppSettings = AppSettings.create(
        locale = value.string("locale"),
        currencyCode = value.string("currencyCode"),
        defaultMassUnit = value.string("defaultMassUnit"),
        defaultVolumeUnit = value.string("defaultVolumeUnit"),
        remindersEnabled = value.boolean("remindersEnabled"),
        onboardingComplete = value.boolean("onboardingComplete"),
    )

    private fun supplierToJson(value: Supplier) = buildJsonObject {
        put("id", JsonPrimitive(value.id)); put("name", JsonPrimitive(value.name))
        put("createdAt", JsonPrimitive(value.createdAt.toString())); put("updatedAt", JsonPrimitive(value.updatedAt.toString()))
        putNullableString("notes", value.notes)
    }

    private fun supplierFromJson(value: JsonObject) = Supplier(
        id = value.string("id"), name = value.string("name"),
        createdAt = value.instant("createdAt"), updatedAt = value.instant("updatedAt"),
        notes = value.textOrNull("notes"),
    )

    private fun cylinderToJson(value: Cylinder, includeLocalPhotos: Boolean) = buildJsonObject {
        put("id", JsonPrimitive(value.id)); put("nickname", JsonPrimitive(value.nickname)); put("gasType", JsonPrimitive(value.gasType))
        put("relationship", JsonPrimitive(value.relationship.name)); put("lifecycle", JsonPrimitive(value.lifecycle.name))
        put("state", JsonPrimitive(value.state.name))
        put("createdAt", JsonPrimitive(value.createdAt.toString())); put("updatedAt", JsonPrimitive(value.updatedAt.toString()))
        putNullableDouble("capacityValue", value.capacityValue); putNullableString("capacityUnit", value.capacityUnit)
        putNullableString("serialNumber", value.serialNumber)
        putNullableString("localPhotoUri", if (includeLocalPhotos) value.localPhotoUri else null)
        putNullableString("supplierId", value.supplierId)
        put("acquisitionAmount", value.acquisitionAmount?.let(::moneyToJson) ?: JsonNull)
        put("acquiredAt", value.acquiredAt?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
        put("isFreeEditableSelection", JsonPrimitive(false))
    }

    private fun cylinderFromJson(value: JsonObject) = Cylinder(
        id = value.string("id"), nickname = value.string("nickname"), gasType = value.string("gasType"),
        relationship = enumValue<RelationshipType>(value.string("relationship")),
        lifecycle = enumValue<CylinderLifecycle>(value.string("lifecycle")),
        state = value.textOrNull("state")?.let { enumValue<CylinderState>(it) } ?: CylinderState.ready,
        createdAt = value.instant("createdAt"), updatedAt = value.instant("updatedAt"),
        capacityValue = value.doubleOrNull("capacityValue"), capacityUnit = value.textOrNull("capacityUnit"),
        serialNumber = value.textOrNull("serialNumber"), localPhotoUri = value.textOrNull("localPhotoUri"),
        supplierId = value.textOrNull("supplierId"),
        acquisitionAmount = value["acquisitionAmount"]?.takeUnless { it is JsonNull }?.let { moneyFromJson(it.asObject("acquisitionAmount")) },
        acquiredAt = value.instantOrNull("acquiredAt"),
        isFreeEditableSelection = false,
    )

    private fun eventToJson(value: CylinderEvent) = buildJsonObject {
        put("id", JsonPrimitive(value.id)); put("cylinderId", JsonPrimitive(value.cylinderId)); put("type", JsonPrimitive(value.type.name))
        put("occurredAt", JsonPrimitive(value.occurredAt.toString())); putNullableString("supplierId", value.supplierId)
        put("amount", value.amount?.let(::moneyToJson) ?: JsonNull); putNullableString("note", value.note)
        put("metadata", anyToJson(value.metadata))
    }

    private fun eventFromJson(value: JsonObject) = CylinderEvent(
        id = value.string("id"), cylinderId = value.string("cylinderId"), type = enumValue<CylinderEventType>(value.string("type")),
        occurredAt = value.instant("occurredAt"), supplierId = value.textOrNull("supplierId"),
        amount = value["amount"]?.takeUnless { it is JsonNull }?.let { moneyFromJson(it.asObject("amount")) },
        note = value.textOrNull("note"),
        metadata = (value["metadata"]?.let(::jsonToAny) as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value } ?: emptyMap(),
    )

    private fun reminderToJson(value: Reminder) = buildJsonObject {
        put("id", JsonPrimitive(value.id)); put("cylinderId", JsonPrimitive(value.cylinderId)); put("kind", JsonPrimitive(value.kind.name))
        put("title", JsonPrimitive(value.title)); put("dueAt", JsonPrimitive(value.dueAt.toString())); put("createdAt", JsonPrimitive(value.createdAt.toString()))
        put("delivery", JsonPrimitive(value.delivery.name)); put("completed", JsonPrimitive(value.completed)); put("notificationId", JsonPrimitive(value.notificationId))
    }

    private fun reminderFromJson(value: JsonObject): Reminder {
        val id = value.string("id")
        return Reminder(
            id = id, cylinderId = value.string("cylinderId"), kind = enumValue<ReminderKind>(value.string("kind")),
            title = value.string("title"), dueAt = value.instant("dueAt"), createdAt = value.instant("createdAt"),
            delivery = enumValue<ReminderDelivery>(value.string("delivery")), completed = value.boolean("completed"),
            notificationId = value.intOrNull("notificationId") ?: stableNotificationId(id),
        )
    }

    private fun draftToJson(value: AddCylinderDraft, includeLocalPhotos: Boolean) = buildJsonObject {
        put("nickname", JsonPrimitive(value.nickname)); put("gasType", JsonPrimitive(value.gasType)); put("relationship", JsonPrimitive(value.relationship.name))
        putNullableDouble("capacityValue", value.capacityValue); putNullableString("capacityUnit", value.capacityUnit); putNullableString("serialNumber", value.serialNumber)
        putNullableString("localPhotoUri", if (includeLocalPhotos) value.localPhotoUri else null); putNullableString("supplierId", value.supplierId)
        put("acquisitionAmount", value.acquisitionAmount?.let(::moneyToJson) ?: JsonNull)
        put("acquiredAt", value.acquiredAt?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
    }

    private fun draftFromJson(value: JsonObject) = AddCylinderDraft(
        nickname = value.string("nickname"), gasType = value.string("gasType"), relationship = enumValue<RelationshipType>(value.string("relationship")),
        capacityValue = value.doubleOrNull("capacityValue"), capacityUnit = value.textOrNull("capacityUnit"), serialNumber = value.textOrNull("serialNumber"),
        localPhotoUri = value.textOrNull("localPhotoUri"), supplierId = value.textOrNull("supplierId"),
        acquisitionAmount = value["acquisitionAmount"]?.takeUnless { it is JsonNull }?.let { moneyFromJson(it.asObject("acquisitionAmount")) },
        acquiredAt = value.instantOrNull("acquiredAt"),
    )

    private fun pendingDraftToJson(value: PendingCylinderDraft, includeLocalPhotos: Boolean) = buildJsonObject {
        put("draft", draftToJson(value.draft, includeLocalPhotos)); put("draftResumed", JsonPrimitive(value.draftResumed))
    }

    private fun pendingDraftFromJson(value: JsonObject) = PendingCylinderDraft(
        draft = draftFromJson(value.objectValue("draft")), draftResumed = value.boolean("draftResumed"),
    )

    private fun moneyToJson(value: Money) = buildJsonObject {
        put("minorUnits", JsonPrimitive(value.minorUnits)); put("currencyCode", JsonPrimitive(value.normalizedCurrencyCode))
    }
    private fun moneyFromJson(value: JsonObject) = Money(value.long("minorUnits"), value.string("currencyCode"))

    private fun entitlementToJson(value: Entitlement) = buildJsonObject {
        put("tier", JsonPrimitive(value.tier.name)); put("source", JsonPrimitive(value.source.name))
        put("validUntil", value.validUntil?.let { JsonPrimitive(it.toString()) } ?: JsonNull); put("willRenew", JsonPrimitive(value.willRenew))
    }
    private fun entitlementFromJson(value: JsonObject) = Entitlement(
        tier = enumValue<AccessTier>(value.string("tier")), source = enumValue<EntitlementSource>(value.string("source")),
        validUntil = value.instantOrNull("validUntil"), willRenew = value.boolean("willRenew"),
    )

    private fun validateReferences(state: WalletData) {
        val supplierIds = state.suppliers.map { it.id }.toSet(); val cylinderIds = state.cylinders.map { it.id }.toSet()
        require(state.suppliers.map { it.id }.distinct().size == state.suppliers.size) { "Duplicate supplier IDs." }
        require(state.cylinders.map { it.id }.distinct().size == state.cylinders.size) { "Duplicate cylinder IDs." }
        require(state.cylinders.all { it.supplierId == null || it.supplierId in supplierIds }) { "Cylinder references an unknown supplier." }
        require(state.events.all { it.cylinderId in cylinderIds && (it.supplierId == null || it.supplierId in supplierIds) }) { "Event references an unknown record." }
        require(state.reminders.all { it.cylinderId in cylinderIds }) { "Reminder references an unknown cylinder." }
        require(state.freeEditableSelection.all { it in cylinderIds }) { "Free selection references an unknown cylinder." }
        state.pendingDraft?.draft?.supplierId?.let { require(it in supplierIds) { "Pending draft references an unknown supplier." } }
    }

    private fun parseObject(encoded: String, label: String): JsonObject = try {
        json.parseToJsonElement(encoded).asObject(label)
    } catch (error: Throwable) {
        throw IllegalArgumentException("$label must be valid JSON.", error)
    }

    private fun anyToJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value); is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value); is Long -> JsonPrimitive(value); is Float -> JsonPrimitive(value); is Double -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value.toString())
        is Map<*, *> -> JsonObject(value.entries.associate { it.key.toString() to anyToJson(it.value) })
        is Iterable<*> -> JsonArray(value.map(::anyToJson))
        else -> JsonPrimitive(value.toString())
    }

    private fun jsonToAny(value: JsonElement): Any? = when (value) {
        JsonNull -> null
        is JsonObject -> value.mapValues { jsonToAny(it.value) }
        is JsonArray -> value.map(::jsonToAny)
        is JsonPrimitive -> when {
            value.isString -> value.content
            value.booleanOrNull != null -> value.boolean
            value.longOrNull != null -> value.long
            value.doubleOrNull != null -> value.double
            else -> value.content
        }
    }

    private inline fun <reified T : Enum<T>> enumValue(raw: String): T = enumValues<T>().firstOrNull { it.name == raw }
        ?: throw IllegalArgumentException("Unknown ${T::class.simpleName} value: $raw")

    companion object {
        private const val PRIVATE_FORMAT = "welding-gas-wallet-private-v3"
        private const val BACKUP_FORMAT = "welding-gas-wallet-v3"
    }
}

private fun JsonElement.asObject(label: String): JsonObject = this as? JsonObject
    ?: throw IllegalArgumentException("$label must be an object.")
private fun JsonObject.objectValue(field: String): JsonObject = this[field]?.asObject(field)
    ?: throw IllegalArgumentException("Missing $field.")
private fun JsonObject.arrayValue(field: String): JsonArray = this[field] as? JsonArray
    ?: throw IllegalArgumentException("$field must be a list.")
private fun JsonObject.string(field: String): String = (this[field] as? JsonPrimitive)?.takeIf { it.isString }?.content
    ?: throw IllegalArgumentException("$field is required.")
private fun JsonObject.textOrNull(field: String): String? = (this[field] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.takeIf { it.isNotEmpty() }
private fun JsonObject.int(field: String): Int = (this[field] as? JsonPrimitive)?.intOrNull ?: throw IllegalArgumentException("$field is required.")
private fun JsonObject.intOrNull(field: String): Int? = (this[field] as? JsonPrimitive)?.intOrNull
private fun JsonObject.long(field: String): Long = (this[field] as? JsonPrimitive)?.longOrNull ?: throw IllegalArgumentException("$field is required.")
private fun JsonObject.doubleOrNull(field: String): Double? = (this[field] as? JsonPrimitive)?.doubleOrNull
private fun JsonObject.boolean(field: String): Boolean = (this[field] as? JsonPrimitive)?.booleanOrNull ?: false
private fun JsonObject.instant(field: String): Instant = instantOrNull(field) ?: throw IllegalArgumentException("Invalid $field date.")
private fun JsonObject.instantOrNull(field: String): Instant? = (this[field] as? JsonPrimitive)?.takeIf { it.isString }?.content?.let {
    try { Instant.parse(it) } catch (_: Throwable) { throw IllegalArgumentException("Invalid $field date.") }
}
private fun JsonObjectBuilder.putNullableString(field: String, value: String?) { put(field, value?.let(::JsonPrimitive) ?: JsonNull) }
private fun JsonObjectBuilder.putNullableDouble(field: String, value: Double?) { put(field, value?.let(::JsonPrimitive) ?: JsonNull) }
