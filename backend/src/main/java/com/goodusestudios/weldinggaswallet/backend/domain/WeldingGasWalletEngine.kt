package com.goodusestudios.weldinggaswallet.backend.domain

import java.time.Instant

class WeldingGasWalletEngine(
    val repo: AtomicWalletRepository,
    val billing: StoreBillingGateway,
    val scheduler: ReminderScheduler,
    val ids: IdFactory,
    val clock: Clock,
    private val backupCodec: WalletBackupCodec,
) {
    suspend fun snapshot(): WalletData = repo.read()

    suspend fun createSupplier(
        name: String,
        notes: String? = null,
        expectedRevision: Int? = null,
    ): Supplier = repo.transact(expectedRevision) { current ->
        val now = clock.now()
        val supplier = Supplier(
            id = ids.newId(),
            name = requiredText(name, "supplier name"),
            notes = textOrNull(notes),
            createdAt = now,
            updatedAt = now,
        )
        TransactionOutcome(
            current.next(suppliers = current.suppliers + supplier),
            supplier,
        )
    }

    suspend fun updateSupplier(
        supplierId: String,
        name: String? = null,
        notes: FieldPatch<String> = FieldPatch.Keep(),
        expectedRevision: Int? = null,
    ): Supplier = repo.transact(expectedRevision) { current ->
        val index = current.suppliers.indexOfFirst { it.id == supplierId }
        check(index >= 0) { "Supplier not found." }
        val old = current.suppliers[index]
        val updated = old.copy(
            name = name?.let { requiredText(it, "supplier name") } ?: old.name,
            notes = notes.applyTo(old.notes),
            updatedAt = clock.now(),
        )
        val suppliers = current.suppliers.toMutableList().apply { this[index] = updated }
        TransactionOutcome(current.next(suppliers = suppliers), updated)
    }

    suspend fun deleteSupplier(
        supplierId: String,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        check(current.suppliers.any { it.id == supplierId }) { "Supplier not found." }
        val referenced =
            current.cylinders.any { it.supplierId == supplierId } ||
                current.events.any { it.supplierId == supplierId } ||
                current.pendingDraft?.draft?.supplierId == supplierId
        if (referenced) throw SupplierInUseException(supplierId)
        TransactionOutcome(
            current.next(suppliers = current.suppliers.filterNot { it.id == supplierId }),
            Unit,
        )
    }

    suspend fun updateSettings(
        locale: String? = null,
        currencyCode: String? = null,
        defaultMassUnit: String? = null,
        defaultVolumeUnit: String? = null,
        onboardingComplete: Boolean? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        if (locale != null) require(isSupportedLocaleCandidate(locale)) { "Unsupported locale." }
        if (defaultMassUnit != null) require(defaultMassUnit in setOf("kg", "lb")) {
            "Unsupported mass unit."
        }
        if (defaultVolumeUnit != null) require(defaultVolumeUnit in setOf("L", "m3", "ft3")) {
            "Unsupported volume unit."
        }
        val nextLocale = locale?.let(::canonicalLocale) ?: current.settings.locale
        val nextCurrency = currencyCode?.let {
            val normalized = it.trim().uppercase()
            require(normalized in ISO_4217_CODES) { "Unsupported ISO 4217 currency: $it" }
            normalized
        } ?: current.settings.currencyCode
        val settings = AppSettings.create(
            locale = nextLocale,
            currencyCode = nextCurrency,
            defaultMassUnit = defaultMassUnit ?: current.settings.defaultMassUnit,
            defaultVolumeUnit = defaultVolumeUnit ?: current.settings.defaultVolumeUnit,
            remindersEnabled = current.settings.remindersEnabled,
            onboardingComplete = onboardingComplete ?: current.settings.onboardingComplete,
        )
        TransactionOutcome(current.next(settings = settings), Unit)
    }

    suspend fun addOrGate(
        draft: AddCylinderDraft,
        expectedRevision: Int? = null,
    ): AddResult {
        validateDraft(draft)
        return repo.transact(expectedRevision) { current ->
            assertSupplierExists(current, draft.supplierId)
            val isPro = current.entitlementCache.isProAt(clock.now())
            val slots = current.cylinders.count { it.consumesCurrentSlot }
            if (!isPro && slots >= FREE_EDITABLE_CYLINDER_LIMIT) {
                TransactionOutcome(
                    current.next(
                        pendingDraft = FieldPatch.SetValue(PendingCylinderDraft(draft)),
                    ),
                    AddRequiresPaywall(PaywallReason.addFourthCylinder),
                )
            } else {
                val (state, cylinder) = insertDraft(current, draft, freeSelection = !isPro)
                TransactionOutcome(state, CylinderAdded(cylinder))
            }
        }
    }

    private fun insertDraft(
        current: WalletData,
        draft: AddCylinderDraft,
        freeSelection: Boolean,
    ): Pair<WalletData, Cylinder> {
        validateDraft(draft)
        assertSupplierExists(current, draft.supplierId)
        val now = clock.now()
        val cylinder = Cylinder(
            id = ids.newId(),
            nickname = draft.nickname.trim().ifEmpty {
                automaticCylinderName(
                    gasType = draft.gasType,
                    capacityValue = draft.capacityValue,
                    capacityUnit = draft.capacityUnit,
                )
            },
            gasType = draft.gasType.trim(),
            capacityValue = draft.capacityValue,
            capacityUnit = textOrNull(draft.capacityUnit),
            serialNumber = textOrNull(draft.serialNumber),
            localPhotoUri = textOrNull(draft.localPhotoUri),
            relationship = draft.relationship,
            lifecycle = CylinderLifecycle.active,
            supplierId = textOrNull(draft.supplierId),
            acquisitionAmount = draft.acquisitionAmount,
            acquiredAt = draft.acquiredAt,
            createdAt = now,
            updatedAt = now,
        )
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinder.id,
            type = CylinderEventType.created,
            occurredAt = draft.acquiredAt ?: now,
            supplierId = cylinder.supplierId,
            amount = cylinder.acquisitionAmount,
            metadata = mapOf("relationship" to cylinder.relationship.name),
        )
        val selection = if (freeSelection) {
            (current.freeEditableSelection + cylinder.id)
                .filter { id -> id == cylinder.id || current.cylinders.any { it.id == id && it.consumesCurrentSlot } }
                .distinct()
                .take(FREE_EDITABLE_CYLINDER_LIMIT)
        } else {
            current.freeEditableSelection
        }
        return current.next(
            cylinders = current.cylinders + cylinder,
            events = current.events + event,
            freeEditableSelection = selection,
        ) to cylinder
    }

    suspend fun getPaywallProducts(): List<StoreProduct> {
        val expected = ProductIds.android
        return billing.loadProducts()
            .filter { it.id in expected && it.localizedPrice.isNotBlank() }
            .map {
                it.copy(isDefault = it.id == ProductIds.androidAnnual)
            }
            .sortedBy { expected.indexOf(it.id) }
    }

    suspend fun purchaseAndResume(productId: String): Cylinder? {
        require(productId in ProductIds.android) { "Product does not belong to Android." }
        val verified = billing.purchaseVerified(productId)
        validateVerifiedEntitlement(verified)
        val resumed = applyEntitlementAndResume(verified)
        enforceDowngradeIfNeeded()
        return resumed
    }

    suspend fun restoreAndResume(): Cylinder? {
        val verified = billing.restoreOrRefreshVerified()
        validateVerifiedEntitlement(verified)
        val resumed = applyEntitlementAndResume(verified)
        enforceDowngradeIfNeeded()
        return resumed
    }

    private suspend fun applyEntitlementAndResume(verified: Entitlement): Cylinder? {
        (repo as? SessionEntitlementTrust)?.acceptStoreVerifiedEntitlement(verified)
        return repo.transact { current ->
            val isPro = verified.isProAt(clock.now())
            val pending = current.pendingDraft
            if (isPro && pending != null && !pending.draftResumed) {
                val marked = current.copy(
                    pendingDraft = pending.copy(draftResumed = true),
                    entitlementCache = verified,
                )
                val (insertedState, insertedCylinder) =
                    insertDraft(marked, pending.draft, freeSelection = false)
                TransactionOutcome(
                    insertedState.copy(
                        pendingDraft = null,
                        freeEditableSelection = emptyList(),
                        entitlementCache = verified,
                    ),
                    insertedCylinder,
                )
            } else {
                val nextPending = if (pending?.draftResumed == true) null else pending
                val selection = if (isPro) emptyList() else current.freeEditableSelection
                TransactionOutcome(
                    current.next(
                        pendingDraft = if (nextPending == null) FieldPatch.Clear()
                            else FieldPatch.SetValue(nextPending),
                        freeEditableSelection = selection,
                        entitlementCache = verified,
                    ),
                    null,
                )
            }
        }
    }

    suspend fun canEditCylinder(cylinderId: String): EditDecision =
        editDecision(repo.read(), cylinderId)

    suspend fun enforceDowngradeIfNeeded(): DowngradeDecision = repo.transact { current ->
        val normalizedCylinders = current.cylinders.map { cylinder ->
            if (!cylinder.consumesCurrentSlot && cylinder.isFreeEditableSelection) {
                cylinder.copy(isFreeEditableSelection = false)
            } else {
                cylinder
            }
        }
        val legacyFlagsChanged = normalizedCylinders != current.cylinders

        if (current.entitlementCache.isProAt(clock.now())) {
            val nextSelection = emptyList<String>()
            TransactionOutcome(
                if (legacyFlagsChanged || current.freeEditableSelection.isNotEmpty()) {
                    current.next(
                        cylinders = normalizedCylinders,
                        freeEditableSelection = nextSelection,
                    )
                } else {
                    current
                },
                DowngradeReady,
            )
        } else {
            val activeIds = normalizedCylinders.filter { it.consumesCurrentSlot }.map { it.id }
            if (activeIds.size <= FREE_EDITABLE_CYLINDER_LIMIT) {
                val normalizedSelection = activeIds.distinct()
                TransactionOutcome(
                    if (legacyFlagsChanged || normalizedSelection != current.freeEditableSelection) {
                        current.next(
                            cylinders = normalizedCylinders,
                            freeEditableSelection = normalizedSelection,
                        )
                    } else {
                        current
                    },
                    DowngradeReady,
                )
            } else {
                val validSelection = current.freeEditableSelection.distinct().let { selected ->
                    selected.size <= FREE_EDITABLE_CYLINDER_LIMIT &&
                        selected.isNotEmpty() &&
                        selected.all { it in activeIds }
                }
                TransactionOutcome(
                    if (legacyFlagsChanged) current.next(cylinders = normalizedCylinders) else current,
                    if (validSelection) DowngradeReady
                    else RequiresFreeSelection(FREE_EDITABLE_CYLINDER_LIMIT),
                )
            }
        }
    }

    private fun editDecision(state: WalletData, cylinderId: String): EditDecision {
        val target = state.cylinders.firstOrNull { it.id == cylinderId } ?: return MissingCylinder
        if (state.entitlementCache.isProAt(clock.now())) return Editable
        if (!target.consumesCurrentSlot) {
            return ReadOnly("Cylinder is not current, read-only for free tier.")
        }
        val currentCount = state.cylinders.count { it.consumesCurrentSlot }
        if (currentCount <= FREE_EDITABLE_CYLINDER_LIMIT || cylinderId in state.freeEditableSelection) {
            return Editable
        }
        return Locked(PaywallReason.editLockedCylinderAfterDowngrade)
    }

    suspend fun selectFreeEditable(
        cylinderIds: Set<String>,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        if (current.entitlementCache.isProAt(clock.now())) {
            TransactionOutcome(
                if (current.freeEditableSelection.isEmpty()) current
                else current.next(freeEditableSelection = emptyList()),
                Unit,
            )
        } else {
            require(cylinderIds.size <= FREE_EDITABLE_CYLINDER_LIMIT) {
                "Select at most $FREE_EDITABLE_CYLINDER_LIMIT cylinders."
            }
            val currentIds = current.cylinders.filter { it.consumesCurrentSlot }.map { it.id }.toSet()
            if (currentIds.size > FREE_EDITABLE_CYLINDER_LIMIT) {
                require(cylinderIds.isNotEmpty()) { "Select at least one current cylinder." }
            }
            require(currentIds.containsAll(cylinderIds)) {
                "Selection contains a non-current cylinder."
            }
            TransactionOutcome(
                current.next(freeEditableSelection = cylinderIds.toList().sorted()),
                Unit,
            )
        }
    }

    suspend fun recordExchange(
        cylinderId: String,
        occurredAt: Instant,
        supplierId: String? = null,
        amount: Money? = null,
        newSerialNumber: FieldPatch<String> = FieldPatch.Keep(),
        note: String? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        assertSupplierExists(current, supplierId)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val updated = old.copy(
            serialNumber = newSerialNumber.applyTo(old.serialNumber),
            supplierId = supplierId?.let { requiredText(it, "supplierId") } ?: old.supplierId,
            lifecycle = CylinderLifecycle.active,
            state = CylinderState.ready,
            updatedAt = clock.now(),
        )
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = CylinderEventType.exchange,
            occurredAt = occurredAt,
            supplierId = supplierId ?: old.supplierId,
            amount = amount,
            note = textOrNull(note),
            metadata = mapOf("serialNumber" to newSerialNumber.applyTo(old.serialNumber)),
        )
        TransactionOutcome(
            current.next(cylinders = cylinders, events = current.events + event),
            Unit,
        )
    }

    suspend fun recordRefill(
        cylinderId: String,
        occurredAt: Instant,
        supplierId: FieldPatch<String> = FieldPatch.Keep(),
        amount: Money? = null,
        note: String? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        if (supplierId is FieldPatch.SetValue) assertSupplierExists(current, supplierId.value)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val updated = old.copy(
            supplierId = supplierId.applyTo(old.supplierId),
            lifecycle = CylinderLifecycle.active,
            state = CylinderState.ready,
            updatedAt = clock.now(),
        )
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = CylinderEventType.refill,
            occurredAt = occurredAt,
            supplierId = updated.supplierId,
            amount = amount,
            note = textOrNull(note),
        )
        TransactionOutcome(
            current.next(cylinders = cylinders, events = current.events + event),
            Unit,
        )
    }

    suspend fun changeCylinderState(
        cylinderId: String,
        state: CylinderState,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        require(old.consumesCurrentSlot) { "Only a current cylinder can change state." }
        if (old.state == state) {
            TransactionOutcome(current, Unit)
        } else {
            val now = clock.now()
            val updated = old.copy(
                lifecycle = CylinderLifecycle.active,
                state = state,
                updatedAt = now,
            )
            val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
            val event = CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.stateChanged,
                occurredAt = now,
                metadata = mapOf(
                    "previousState" to old.state.name,
                    "state" to state.name,
                ),
            )
            TransactionOutcome(
                current.next(cylinders = cylinders, events = current.events + event),
                Unit,
            )
        }
    }

    suspend fun changeSupplier(
        cylinderId: String,
        supplierId: FieldPatch<String>,
        occurredAt: Instant,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        if (supplierId is FieldPatch.SetValue) assertSupplierExists(current, supplierId.value)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val updated = old.copy(
            supplierId = supplierId.applyTo(old.supplierId),
            updatedAt = clock.now(),
        )
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = CylinderEventType.supplierChanged,
            occurredAt = occurredAt,
            supplierId = updated.supplierId,
            metadata = mapOf("cleared" to (updated.supplierId == null)),
        )
        TransactionOutcome(
            current.next(cylinders = cylinders, events = current.events + event),
            Unit,
        )
    }

    suspend fun recordCost(
        cylinderId: String,
        occurredAt: Instant,
        amount: Money,
        supplierId: String? = null,
        note: String? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        assertSupplierExists(current, supplierId)
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = CylinderEventType.cost,
            occurredAt = occurredAt,
            supplierId = textOrNull(supplierId),
            amount = amount,
            note = textOrNull(note),
        )
        TransactionOutcome(current.next(events = current.events + event), Unit)
    }

    suspend fun changeRelationship(
        cylinderId: String,
        relationship: RelationshipType,
        occurredAt: Instant,
        note: String? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val updated = old.copy(relationship = relationship, updatedAt = clock.now())
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = CylinderEventType.relationshipChanged,
            occurredAt = occurredAt,
            note = textOrNull(note),
            metadata = mapOf("relationship" to relationship.name),
        )
        TransactionOutcome(
            current.next(cylinders = cylinders, events = current.events + event),
            Unit,
        )
    }

    suspend fun markReturned(
        cylinderId: String,
        note: String? = null,
        expectedRevision: Int? = null,
    ) = transitionLifecycle(
        cylinderId = cylinderId,
        lifecycle = CylinderLifecycle.returned,
        eventType = CylinderEventType.returned,
        note = note,
        expectedRevision = expectedRevision,
    )

    suspend fun archiveCylinder(
        cylinderId: String,
        expectedRevision: Int? = null,
    ) = transitionLifecycle(
        cylinderId = cylinderId,
        lifecycle = CylinderLifecycle.archived,
        eventType = CylinderEventType.archived,
        expectedRevision = expectedRevision,
    )

    suspend fun deleteCylinder(
        cylinderId: String,
        confirmed: Boolean,
        force: Boolean = false,
        expectedRevision: Int? = null,
    ): CylinderDeleteResult {
        check(confirmed) { "Explicit confirmation is required." }
        val before = repo.read()
        check(before.cylinders.any { it.id == cylinderId }) { "Cylinder not found." }
        val reminderFailures = mutableListOf<String>()
        before.reminders.filter { it.cylinderId == cylinderId }.forEach { reminder ->
            try {
                scheduler.cancel(reminder)
            } catch (_: Throwable) {
                reminderFailures += reminder.id
                try { scheduler.dismiss(reminder) } catch (_: Throwable) { }
            }
        }
        if (reminderFailures.isNotEmpty() && !force) {
            throw CannotDeleteDueToRemindersException(cylinderId, reminderFailures)
        }
        val guardedRevision = expectedRevision ?: before.revision
        repo.transact(guardedRevision) { current ->
            check(current.cylinders.any { it.id == cylinderId }) { "Cylinder not found." }
            TransactionOutcome(
                current.next(
                    cylinders = current.cylinders.filterNot { it.id == cylinderId },
                    events = current.events.filterNot { it.cylinderId == cylinderId },
                    reminders = current.reminders.filterNot { it.cylinderId == cylinderId },
                    freeEditableSelection = current.freeEditableSelection.filterNot { it == cylinderId },
                ),
                Unit,
            )
        }
        (repo as? ResidualWalletDataPurger)?.purgeResidualWalletFiles()
        return CylinderDeleteResult(
            forced = force && reminderFailures.isNotEmpty(),
            reminderCancellationFailures = reminderFailures.toList(),
        )
    }

    private suspend fun transitionLifecycle(
        cylinderId: String,
        lifecycle: CylinderLifecycle,
        eventType: CylinderEventType,
        note: String? = null,
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val now = clock.now()
        val updated = old.copy(
            lifecycle = lifecycle,
            updatedAt = now,
        )
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val event = CylinderEvent(
            id = ids.newId(),
            cylinderId = cylinderId,
            type = eventType,
            occurredAt = now,
            note = textOrNull(note),
        )
        TransactionOutcome(
            current.next(
                cylinders = cylinders,
                events = current.events + event,
                freeEditableSelection = current.freeEditableSelection.filterNot { it == cylinderId },
            ),
            Unit,
        )
    }

    suspend fun updateCylinderDetails(
        cylinderId: String,
        nickname: String? = null,
        gasType: String? = null,
        capacityValue: FieldPatch<Double> = FieldPatch.Keep(),
        capacityUnit: FieldPatch<String> = FieldPatch.Keep(),
        serialNumber: FieldPatch<String> = FieldPatch.Keep(),
        localPhotoUri: FieldPatch<String> = FieldPatch.Keep(),
        acquisitionAmount: FieldPatch<Money> = FieldPatch.Keep(),
        acquiredAt: FieldPatch<Instant> = FieldPatch.Keep(),
        relationship: RelationshipType? = null,
        supplierId: FieldPatch<String> = FieldPatch.Keep(),
        expectedRevision: Int? = null,
    ) = repo.transact(expectedRevision) { current ->
        requireEditable(current, cylinderId)
        if (supplierId is FieldPatch.SetValue) assertSupplierExists(current, supplierId.value)
        val index = current.cylinders.indexOfFirst { it.id == cylinderId }
        val old = current.cylinders[index]
        val now = clock.now()
        val updated = old.copy(
            nickname = nickname?.let { requiredText(it, "nickname") } ?: old.nickname,
            gasType = gasType?.let { requiredText(it, "gasType") } ?: old.gasType,
            capacityValue = capacityValue.applyTo(old.capacityValue),
            capacityUnit = capacityUnit.applyTo(old.capacityUnit),
            serialNumber = serialNumber.applyTo(old.serialNumber),
            localPhotoUri = localPhotoUri.applyTo(old.localPhotoUri),
            acquisitionAmount = acquisitionAmount.applyTo(old.acquisitionAmount),
            acquiredAt = acquiredAt.applyTo(old.acquiredAt),
            relationship = relationship ?: old.relationship,
            supplierId = supplierId.applyTo(old.supplierId),
            updatedAt = now,
        )
        if (updated.capacityValue != null) {
            require(updated.capacityValue.isFinite() && updated.capacityValue > 0) {
                "Capacity must be a finite number above zero."
            }
            require(textOrNull(updated.capacityUnit) != null) {
                "Capacity unit is required with capacity."
            }
        }
        val cylinders = current.cylinders.toMutableList().apply { this[index] = updated }
        val events = current.events.toMutableList()

        val acquisitionChanged =
            updated.acquisitionAmount != old.acquisitionAmount || updated.acquiredAt != old.acquiredAt
        if (acquisitionChanged) {
            events += CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.acquisitionUpdated,
                occurredAt = now,
                amount = updated.acquisitionAmount,
                metadata = mapOf(
                    "oldAmount" to auditMoney(old.acquisitionAmount),
                    "newAmount" to auditMoney(updated.acquisitionAmount),
                    "oldAcquiredAt" to old.acquiredAt?.toString(),
                    "newAcquiredAt" to updated.acquiredAt?.toString(),
                    "amountCleared" to (old.acquisitionAmount != null && updated.acquisitionAmount == null),
                ),
            )
        }

        val genericChanges = linkedMapOf<String, Any?>()
        recordChange(genericChanges, "nickname", old.nickname, updated.nickname)
        recordChange(genericChanges, "gasType", old.gasType, updated.gasType)
        recordChange(genericChanges, "capacityValue", old.capacityValue, updated.capacityValue)
        recordChange(genericChanges, "capacityUnit", old.capacityUnit, updated.capacityUnit)
        recordChange(genericChanges, "serialNumber", old.serialNumber, updated.serialNumber)
        recordChange(genericChanges, "localPhotoUri", old.localPhotoUri, updated.localPhotoUri)
        if (genericChanges.isNotEmpty()) {
            events += CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.cylinderUpdated,
                occurredAt = now,
                metadata = mapOf("changes" to genericChanges),
            )
        }
        if (updated.relationship != old.relationship) {
            events += CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.relationshipChanged,
                occurredAt = now,
                metadata = mapOf(
                    "oldRelationship" to old.relationship.name,
                    "relationship" to updated.relationship.name,
                ),
            )
        }
        if (updated.supplierId != old.supplierId) {
            events += CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.supplierChanged,
                occurredAt = now,
                supplierId = updated.supplierId,
                metadata = mapOf(
                    "oldSupplierId" to old.supplierId,
                    "cleared" to (updated.supplierId == null),
                ),
            )
        }
        TransactionOutcome(current.next(cylinders = cylinders, events = events), Unit)
    }

    suspend fun createReminder(
        cylinderId: String,
        kind: ReminderKind,
        title: String,
        dueAt: Instant,
        expectedRevision: Int? = null,
    ): ReminderResult {
        val reminder = repo.transact(expectedRevision) { current ->
            requireEditable(current, cylinderId)
            val now = clock.now()
            val id = ids.newId()
            val created = Reminder(
                id = id,
                cylinderId = cylinderId,
                kind = kind,
                title = requiredText(title, "title"),
                dueAt = dueAt,
                createdAt = now,
                delivery = if (current.settings.remindersEnabled) {
                    ReminderDelivery.needsScheduling
                } else {
                    ReminderDelivery.idle
                },
                notificationId = stableNotificationId(id),
            )
            val event = CylinderEvent(
                id = ids.newId(),
                cylinderId = cylinderId,
                type = CylinderEventType.reminderCreated,
                occurredAt = now,
                metadata = mapOf(
                    "reminderId" to created.id,
                    "dueAt" to created.dueAt.toString(),
                ),
            )
            TransactionOutcome(
                current.next(
                    reminders = current.reminders + created,
                    events = current.events + event,
                ),
                created,
            )
        }
        if (!repo.read().settings.remindersEnabled) return ReminderResult(reminder, false)
        return ReminderResult(reminder, scheduleReminder(reminder))
    }

    suspend fun updateReminder(
        reminderId: String,
        kind: ReminderKind? = null,
        title: String? = null,
        dueAt: Instant? = null,
        expectedRevision: Int? = null,
    ): ReminderResult {
        val old = repo.read().reminders.firstOrNull { it.id == reminderId }
            ?: error("Reminder not found.")
        val updated = repo.transact(expectedRevision) { current ->
            val index = current.reminders.indexOfFirst { it.id == reminderId }
            check(index >= 0) { "Reminder not found." }
            val existing = current.reminders[index]
            requireEditable(current, existing.cylinderId)
            check(!existing.completed) { "Completed reminders cannot be edited." }
            val changed = existing.copy(
                kind = kind ?: existing.kind,
                title = title?.let { requiredText(it, "title") } ?: existing.title,
                dueAt = dueAt ?: existing.dueAt,
                delivery = if (current.settings.remindersEnabled) {
                    ReminderDelivery.needsScheduling
                } else {
                    ReminderDelivery.idle
                },
            )
            val reminders = current.reminders.toMutableList().apply { this[index] = changed }
            val event = CylinderEvent(
                id = ids.newId(),
                cylinderId = existing.cylinderId,
                type = CylinderEventType.reminderUpdated,
                occurredAt = clock.now(),
                metadata = mapOf(
                    "reminderId" to reminderId,
                    "oldDueAt" to existing.dueAt.toString(),
                    "newDueAt" to changed.dueAt.toString(),
                    "titleChanged" to (existing.title != changed.title),
                    "kindChanged" to (existing.kind != changed.kind),
                ),
            )
            TransactionOutcome(
                current.next(reminders = reminders, events = current.events + event),
                changed,
            )
        }
        try { scheduler.cancel(old) } catch (_: Throwable) {
            try { scheduler.dismiss(old) } catch (_: Throwable) { }
        }
        if (!repo.read().settings.remindersEnabled) return ReminderResult(updated, false)
        return ReminderResult(updated, scheduleReminder(updated))
    }

    suspend fun deleteReminder(reminderId: String, expectedRevision: Int? = null) {
        val before = repo.read()
        val reminder = before.reminders.firstOrNull { it.id == reminderId }
            ?: error("Reminder not found.")

        try {
            scheduler.cancel(reminder)
        } catch (failure: Throwable) {
            try { scheduler.dismiss(reminder) } catch (_: Throwable) { }
            throw failure
        }

        val guardedRevision = expectedRevision ?: before.revision
        repo.transact(guardedRevision) { current ->
            val existing = current.reminders.firstOrNull { it.id == reminderId }
                ?: error("Reminder not found.")
            val event = CylinderEvent(
                id = ids.newId(),
                cylinderId = existing.cylinderId,
                type = CylinderEventType.reminderDeleted,
                occurredAt = clock.now(),
                metadata = mapOf("reminderId" to reminderId),
            )
            TransactionOutcome(
                current.next(
                    reminders = current.reminders.filterNot { it.id == reminderId },
                    events = current.events + event,
                ),
                Unit,
            )
        }
    }

    suspend fun completeReminder(reminderId: String, expectedRevision: Int? = null) {
        val completed = repo.transact(expectedRevision) { current ->
            val index = current.reminders.indexOfFirst { it.id == reminderId }
            check(index >= 0) { "Reminder not found." }
            val old = current.reminders[index]
            requireEditable(current, old.cylinderId)
            val updated = old.copy(
                completed = true,
                delivery = ReminderDelivery.needsCancellation,
            )
            val reminders = current.reminders.toMutableList().apply { this[index] = updated }
            val event = CylinderEvent(
                id = ids.newId(),
                cylinderId = old.cylinderId,
                type = CylinderEventType.reminderCompleted,
                occurredAt = clock.now(),
                metadata = mapOf("reminderId" to reminderId),
            )
            TransactionOutcome(
                current.next(reminders = reminders, events = current.events + event),
                updated,
            )
        }
        try {
            scheduler.cancel(completed)
            setReminderDelivery(completed.id, ReminderDelivery.idle)
        } catch (_: Throwable) {
            try { scheduler.dismiss(completed) } catch (_: Throwable) { }
        }
    }

    suspend fun setRemindersEnabled(enabled: Boolean) {
        repo.transact { current ->
            val settings = current.settings.copy(remindersEnabled = enabled)
            val reminders = current.reminders.map { reminder ->
                if (reminder.completed) {
                    reminder.copy(delivery = ReminderDelivery.needsCancellation)
                } else {
                    reminder.copy(
                        delivery = if (enabled) {
                            ReminderDelivery.needsScheduling
                        } else {
                            ReminderDelivery.needsCancellation
                        },
                    )
                }
            }
            TransactionOutcome(current.next(settings = settings, reminders = reminders), Unit)
        }
        reconcileReminders()
    }

    suspend fun reconcileReminders() {
        val idsToCheck = repo.read().reminders.map { it.id }
        for (reminderId in idsToCheck) {
            if (scheduler.consumePermissionFailure(reminderId)) {
                setReminderDelivery(reminderId, ReminderDelivery.permissionRequired)
            }
            val current = repo.read()
            val reminder = current.reminders.firstOrNull { it.id == reminderId } ?: continue
            try {
                if (!current.settings.remindersEnabled || reminder.completed) {
                    if (reminder.delivery != ReminderDelivery.idle) {
                        scheduler.cancel(reminder)
                        setReminderDelivery(reminder.id, ReminderDelivery.idle)
                    } else {
                        scheduler.dismiss(reminder)
                    }
                } else if (reminder.delivery == ReminderDelivery.permissionRequired &&
                    !scheduler.canPostNotifications()
                ) {
                    continue
                } else if (reminder.delivery != ReminderDelivery.scheduled) {
                    scheduleReminder(reminder)
                }
            } catch (_: Throwable) {
            }
        }
    }

    private suspend fun scheduleReminder(reminder: Reminder): Boolean {
        if (!scheduler.canPostNotifications()) {
            setReminderDelivery(reminder.id, ReminderDelivery.permissionRequired)
            return false
        }
        return try {
            scheduler.schedule(reminder)
            setReminderDelivery(reminder.id, ReminderDelivery.scheduled)
            true
        } catch (_: Throwable) {
            setReminderDelivery(reminder.id, ReminderDelivery.needsScheduling)
            false
        }
    }

    private suspend fun setReminderDelivery(id: String, delivery: ReminderDelivery) {
        repo.transact { current ->
            val index = current.reminders.indexOfFirst { it.id == id }
            if (index < 0) {
                TransactionOutcome(current, Unit)
            } else if (current.reminders[index].delivery == delivery) {
                TransactionOutcome(current, Unit)
            } else {
                val reminders = current.reminders.toMutableList().apply {
                    this[index] = current.reminders[index].copy(delivery = delivery)
                }
                TransactionOutcome(current.next(reminders = reminders), Unit)
            }
        }
    }

    suspend fun exportBackup(): String = backupCodec.encode(repo.read(), clock.now())

    suspend fun spendByCurrency(
        from: Instant? = null,
        to: Instant? = null,
        cylinderId: String? = null,
    ): Map<String, Long> {
        val state = repo.read()
        val totals = linkedMapOf<String, Long>()

        for (cylinder in state.cylinders) {
            if (cylinderId != null && cylinder.id != cylinderId) continue
            val acquisitionEditExists = state.events.any {
                it.cylinderId == cylinder.id && it.type == CylinderEventType.acquisitionUpdated
            }
            val legacyCreated = state.events.firstOrNull {
                it.cylinderId == cylinder.id && it.type == CylinderEventType.created
            }
            val amount = cylinder.acquisitionAmount
                ?: if (!acquisitionEditExists) legacyCreated?.amount else null
            val occurredAt = cylinder.acquiredAt ?: legacyCreated?.occurredAt ?: cylinder.createdAt
            if (amount != null && inRange(occurredAt, from, to)) {
                totals[amount.normalizedCurrencyCode] =
                    (totals[amount.normalizedCurrencyCode] ?: 0L) + amount.minorUnits
            }
        }

        for (event in state.events) {
            if (event.type == CylinderEventType.created ||
                event.type == CylinderEventType.acquisitionUpdated
            ) continue
            val amount = event.amount ?: continue
            if (cylinderId != null && event.cylinderId != cylinderId) continue
            if (!inRange(event.occurredAt, from, to)) continue
            val signed = if (event.type == CylinderEventType.depositReturned) {
                -amount.minorUnits
            } else {
                amount.minorUnits
            }
            totals[amount.normalizedCurrencyCode] =
                (totals[amount.normalizedCurrencyCode] ?: 0L) + signed
        }
        return totals.toMap()
    }

    suspend fun importBackup(encoded: String, expectedRevision: Int): ImportResult {
        val imported = backupCodec.decode(encoded)
        val before = repo.read()
        val normalized = validateAndNormalizeImportedState(imported, before.entitlementCache)
        repo.replaceFromBackup(normalized.state, expectedRevision)
        val downgradeDecision = enforceDowngradeIfNeeded()
        reconcileReminders()
        return ImportResult(
            state = repo.read(),
            warnings = normalized.warnings,
            downgradeDecision = downgradeDecision,
        )
    }

    fun validateAndNormalizeImportedState(
        imported: WalletData,
        currentEntitlement: Entitlement,
    ): ImportNormalization {
        val supplierIds = imported.suppliers.map { it.id }.toSet()
        imported.pendingDraft?.draft?.let { draft ->
            validateDraft(draft)
            require(draft.supplierId == null || draft.supplierId in supplierIds) {
                "Pending draft references an unknown supplier."
            }
        }

        val currentIds = imported.cylinders.filter { it.consumesCurrentSlot }.map { it.id }
        val isPro = currentEntitlement.isProAt(clock.now())
        val warnings = mutableListOf<String>()
        val selection = when {
            isPro -> emptyList()
            currentIds.size <= FREE_EDITABLE_CYLINDER_LIMIT -> currentIds
            imported.freeEditableSelection.size <= FREE_EDITABLE_CYLINDER_LIMIT &&
                imported.freeEditableSelection.isNotEmpty() &&
                imported.freeEditableSelection.distinct().size == imported.freeEditableSelection.size &&
                imported.freeEditableSelection.all { it in currentIds } -> imported.freeEditableSelection
            else -> {
                warnings += "Imported free-editable selection was invalid and was cleared."
                emptyList()
            }
        }
        val pending = if (imported.pendingDraft?.draftResumed == true) {
            warnings += "An already-resumed imported pending draft was discarded."
            null
        } else {
            imported.pendingDraft
        }
        val reminders = imported.reminders.map { reminder ->
            reminder.copy(
                notificationId = stableNotificationId(reminder.id),
                delivery = if (reminder.completed || !imported.settings.remindersEnabled) {
                    ReminderDelivery.needsCancellation
                } else {
                    ReminderDelivery.needsScheduling
                },
            )
        }
        return ImportNormalization(
            state = WalletData(
                schemaVersion = WALLET_SCHEMA_VERSION,
                revision = imported.revision,
                settings = imported.settings,
                suppliers = imported.suppliers,
                cylinders = imported.cylinders.map { it.copy(isFreeEditableSelection = false) },
                events = imported.events,
                reminders = reminders,
                pendingDraft = pending,
                freeEditableSelection = selection,
                entitlementCache = currentEntitlement,
            ),
            warnings = warnings,
        )
    }

    suspend fun deleteAllWalletData(confirmed: Boolean) {
        check(confirmed) { "Explicit confirmation is required." }
        scheduler.cancelAll()
        repo.transact { current ->
            val cleared = WalletData.empty(
                locale = current.settings.locale,
                currencyCode = current.settings.currencyCode,
            )
            TransactionOutcome(
                WalletData(
                    schemaVersion = WALLET_SCHEMA_VERSION,
                    revision = current.revision + 1,
                    settings = cleared.settings,
                    suppliers = emptyList(),
                    cylinders = emptyList(),
                    events = emptyList(),
                    reminders = emptyList(),
                    pendingDraft = null,
                    freeEditableSelection = emptyList(),
                    entitlementCache = current.entitlementCache,
                ),
                Unit,
            )
        }
        (repo as? ResidualWalletDataPurger)?.purgeResidualWalletFiles()
    }

    private fun requireEditable(state: WalletData, cylinderId: String) {
        when (val decision = editDecision(state, cylinderId)) {
            MissingCylinder -> error("Cylinder not found.")
            is Locked -> error("Cylinder is read-only.")
            is ReadOnly -> error(decision.reason)
            Editable -> Unit
        }
    }

    private fun assertSupplierExists(state: WalletData, supplierId: String?) {
        val id = textOrNull(supplierId)
        require(id == null || state.suppliers.any { it.id == id }) {
            "Supplier does not exist."
        }
    }

    private fun inRange(value: Instant, from: Instant?, to: Instant?): Boolean =
        (from == null || !value.isBefore(from)) && (to == null || !value.isAfter(to))

    private fun auditMoney(value: Money?): Map<String, Any?>? = value?.let {
        mapOf("minorUnits" to it.minorUnits, "currencyCode" to it.normalizedCurrencyCode)
    }

    private fun recordChange(
        changes: MutableMap<String, Any?>,
        field: String,
        oldValue: Any?,
        newValue: Any?,
    ) {
        if (oldValue != newValue) {
            changes[field] = mapOf("old" to oldValue?.toString(), "new" to newValue?.toString())
        }
    }

    private fun validateVerifiedEntitlement(entitlement: Entitlement) {
        if (entitlement.tier == AccessTier.free) {
            check(entitlement.source == EntitlementSource.none) {
                "Free entitlement has an invalid source."
            }
            return
        }
        check(entitlement.source == EntitlementSource.googlePlaySubscription) {
            "Verified entitlement source does not match Android."
        }
        check(entitlement.validUntil != null) {
            "Android subscription is missing continuity expiry."
        }
    }

    private fun validateDraft(draft: AddCylinderDraft) {
        require(draft.nickname.trim().length <= 500) { "nickname is too long." }
        requiredText(draft.gasType, "gasType")
        if (draft.capacityValue != null) {
            require(draft.capacityValue.isFinite() && draft.capacityValue > 0) {
                "Capacity must be a finite number above zero."
            }
            require(textOrNull(draft.capacityUnit) in CYLINDER_CAPACITY_UNITS) {
                "Use a supported capacity unit."
            }
        }
    }
}

internal fun requiredText(value: String, field: String): String {
    val trimmed = value.trim()
    require(trimmed.isNotEmpty()) { "$field is required." }
    require(trimmed.length <= 500) { "$field is too long." }
    return trimmed
}

internal fun textOrNull(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }
