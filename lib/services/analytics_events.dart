/// Constants pra TODOS os nomes de evento emitidos pelo Stage após o cutover
/// de 2026-05/06 (release de instrumentação nova — plano v2).
///
/// **Regras absolutas (não negociáveis):**
/// - `snake_case` em todo nome.
/// - Verbo no passado: `_started`, `_completed`, `_failed`, `_succeeded`,
///   `_seen`, `_opened`, `_dismissed`, `_clicked`, `_submitted`, `_changed`,
///   `_abandoned`.
/// - Prefixo de domínio obrigatório: `auth_`, `onboarding_`, `cv_`, `adapt_`,
///   `feed_`, `job_`, `trilha_`, `phase_`, `push_`, `nav_`, `tutorial_`,
///   `settings_`, `prefs_`, `perf_`, `error_`, `share_`, `b2b_`, `system_`,
///   `experiment_`, `screen_`, `auth_`, `analytics_`, `session_`, `app_`,
///   `home_`, `cv_tab_`, `trilha_tab_`, `profile_tab_`, `activation_`,
///   `streak_`, `lifecycle_`, `dormant_`, `resurrected_`, `device_`,
///   `network_`, `dark_`, `accessibility_`, `language_`, `edge_`, `llm_`,
///   `db_`, `apify_`, `ats_`, `brazil_`, `daily_`, `webhook_`, `rate_`,
///   `pgcron_`, `install_`, `deep_`, `referrer_`, `first_`, `qr_`, `ad_`,
///   `feedback_`, `paywall_`, `pricing_`, `purchase_`, `subscription_`,
///   `modal_`, `search_`, `filter_`, `sort_`, `match_`, `identify_`,
///   `alias_`, `multi_`, `account_`, `profile_pic_`, `email_`, `phone_`,
///   `notification_`, `privacy_`, `theme_`, `pref_`, `feature_`, `crash_`.
///
/// **Quem precisa adicionar evento novo:** SEMPRE adicionar a constant aqui
/// PRIMEIRO. Nunca emitir string crua de evento no app. Wrapper do
/// AnalyticsService rejeita events que não estejam neste catálogo.
///
/// Catálogo derivado do plano v2 (BLOCO B, subseções B.1 a B.20).
library;

// ════════════════════════════════════════════════════════════════════
// B.1 — Jornada principal (auth, onboarding, ativação) — 50 eventos
// ════════════════════════════════════════════════════════════════════

const String evAppOpened = 'app_opened';
const String evAppFirstOpenEver = 'app_first_open_ever';
const String evAuthSignupLandingShown = 'auth_signup_landing_shown';
const String evAuthSignupMethodChosen = 'auth_signup_method_chosen';
const String evAuthSignupStarted = 'auth_signup_started';
const String evAuthSignupCompleted = 'auth_signup_completed';
const String evAuthSignupFailed = 'auth_signup_failed';
const String evAuthLoginAttempt = 'auth_login_attempt';
const String evAuthLoginSucceeded = 'auth_login_succeeded';
const String evAuthLoginFailed = 'auth_login_failed';
const String evAuthEmailVerificationSent = 'auth_email_verification_sent';
const String evAuthEmailVerificationCompleted = 'auth_email_verification_completed';
const String evAuthPhoneOtpRequested = 'auth_phone_otp_requested';
const String evAuthPhoneOtpValidated = 'auth_phone_otp_validated';
const String evAuthLogout = 'auth_logout';
const String evAuthAccountDeletionRequested = 'auth_account_deletion_requested';
const String evAuthAccountDeletionCompleted = 'auth_account_deletion_completed';
const String evOnboardingStarted = 'onboarding_started';
const String evOnboardingTwoDoorsShown = 'onboarding_two_doors_shown';
const String evOnboardingDoorChosen = 'onboarding_door_chosen';
const String evOnboardingCvUploadPickerOpened = 'onboarding_cv_upload_picker_opened';
const String evOnboardingCvUploadStarted = 'onboarding_cv_upload_started';
const String evOnboardingCvUploadCompleted = 'onboarding_cv_upload_completed';
const String evOnboardingCvUploadFailed = 'onboarding_cv_upload_failed';
const String evOnboardingCvQuestionShown = 'onboarding_cv_question_shown';
const String evOnboardingCvQuestionAnswered = 'onboarding_cv_question_answered';
const String evOnboardingCvQuestionSkipped = 'onboarding_cv_question_skipped';
const String evOnboardingProfileExtractionStarted = 'onboarding_profile_extraction_started';
const String evOnboardingProfileExtractionSucceeded = 'onboarding_profile_extraction_succeeded';
const String evOnboardingProfileExtractionFailed = 'onboarding_profile_extraction_failed';
const String evOnboardingCvImportAbandoned = 'onboarding_cv_import_abandoned';
const String evOnboardingPersonalReviewShown = 'onboarding_personal_review_shown';
const String evOnboardingPersonalFieldEdited = 'onboarding_personal_field_edited';
const String evOnboardingPersonalReviewConfirmed = 'onboarding_personal_review_confirmed';
const String evOnboardingCvReviewShown = 'onboarding_cv_review_shown';
const String evOnboardingCvSectionEdited = 'onboarding_cv_section_edited';
const String evOnboardingCvReviewConfirmed = 'onboarding_cv_review_confirmed';
const String evOnboardingPrefStepShown = 'onboarding_pref_step_shown';
const String evOnboardingPrefStepAnswered = 'onboarding_pref_step_answered';
const String evOnboardingPrefStepSkipped = 'onboarding_pref_step_skipped';
const String evOnboardingMaskingQuestionShown = 'onboarding_masking_question_shown';
const String evOnboardingMaskingQuestionAnswered = 'onboarding_masking_question_answered';
const String evOnboardingAllSetShown = 'onboarding_all_set_shown';
const String evOnboardingCompleted = 'onboarding_completed';
const String evOnboardingAbandoned = 'onboarding_abandoned';
const String evHomeFirstShown = 'home_first_shown';
const String evHomeShown = 'home_shown';
const String evCvTabFirstShown = 'cv_tab_first_shown';
const String evTrilhaTabFirstShown = 'trilha_tab_first_shown';
const String evProfileTabFirstShown = 'profile_tab_first_shown';
const String evActivationMilestoneHit = 'activation_milestone_hit';

// ════════════════════════════════════════════════════════════════════
// B.2 — Microinteração e UX — 16 eventos
// ════════════════════════════════════════════════════════════════════

const String evScrollDepth = 'scroll_depth';
const String evScreenDwellTime = 'screen_dwell_time';
const String evTapHesitation = 'tap_hesitation';
const String evRetapAfterMiss = 'retap_after_miss';
const String evLongPressDetected = 'long_press_detected';
const String evCopyDetected = 'copy_detected';
const String evPasteDetected = 'paste_detected';
const String evScreenshotTaken = 'screenshot_taken';
const String evSwipeVelocityMeasured = 'swipe_velocity_measured';
const String evPinchZoom = 'pinch_zoom';
const String evDoubleTapDetected = 'double_tap_detected';
const String evSwipeIndecision = 'swipe_indecision';
const String evCardReturnedToCenter = 'card_returned_to_center';
const String evTextFieldFocused = 'text_field_focused';
const String evTextFieldBlurred = 'text_field_blurred';
const String evTextFieldAbandoned = 'text_field_abandoned';

// ════════════════════════════════════════════════════════════════════
// B.3 — Fricção, erro e abandono — 18 eventos
// ════════════════════════════════════════════════════════════════════

const String evFormValidationErrorShown = 'form_validation_error_shown';
const String evModalShown = 'modal_shown';
const String evModalDismissed = 'modal_dismissed';
const String evBackButtonPressed = 'back_button_pressed';
const String evNetworkErrorEncountered = 'network_error_encountered';
const String evTimeoutEncountered = 'timeout_encountered';
const String evRetryAttempted = 'retry_attempted';
const String evAppForceKilledDetected = 'app_force_killed_detected';
const String evEmptyStateShown = 'empty_state_shown';
const String evEmptyStateCtaClicked = 'empty_state_cta_clicked';
const String evErrorScreenShown = 'error_screen_shown';
const String evErrorScreenActionTaken = 'error_screen_action_taken';
const String evPermissionRequested = 'permission_requested';
const String evPermissionGranted = 'permission_granted';
const String evPermissionDenied = 'permission_denied';
const String evPermissionSettingsOpened = 'permission_settings_opened';
const String evPermissionReGranted = 'permission_re_granted';
const String evFeatureUnavailableAttempted = 'feature_unavailable_attempted';

// ════════════════════════════════════════════════════════════════════
// B.4 — Performance e tempo (cliente) — 14 eventos
// ════════════════════════════════════════════════════════════════════

const String evAppColdStart = 'app_cold_start';
const String evAppWarmStart = 'app_warm_start';
const String evScreenTimeToInteractive = 'screen_time_to_interactive';
const String evImageLoadTime = 'image_load_time';
const String evFrameDropDetected = 'frame_drop_detected';
const String evMemoryWarningReceived = 'memory_warning_received';
const String evScrollFpsMeasured = 'scroll_fps_measured';
const String evApiCallCompleted = 'api_call_completed';
const String evApiCallFailed = 'api_call_failed';
const String evCacheHit = 'cache_hit';
const String evCacheMiss = 'cache_miss';
const String evPdfRenderStarted = 'pdf_render_started';
const String evPdfRenderCompleted = 'pdf_render_completed';
const String evPdfRenderFailed = 'pdf_render_failed';

// ════════════════════════════════════════════════════════════════════
// B.5 — Contexto e ambiente — 6 eventos
// ════════════════════════════════════════════════════════════════════

const String evDeviceContextSnapshot = 'device_context_snapshot';
const String evNetworkTypeChanged = 'network_type_changed';
const String evDarkModeToggled = 'dark_mode_toggled';
const String evAccessibilityEnabledDetected = 'accessibility_enabled_detected';
const String evLanguageMismatchDetected = 'language_mismatch_detected';
const String evAppVersionOutdated = 'app_version_outdated';

// ════════════════════════════════════════════════════════════════════
// B.6 — Sessão e lifecycle — 10 eventos
// ════════════════════════════════════════════════════════════════════

const String evSessionStarted = 'session_started';
const String evSessionEnded = 'session_ended';
const String evAppBackgrounded = 'app_backgrounded';
const String evAppForegrounded = 'app_foregrounded';
const String evSessionInterrupted = 'session_interrupted';
const String evStreakDayStarted = 'streak_day_started';
const String evStreakBroken = 'streak_broken';
const String evLifecycleAnniversary = 'lifecycle_anniversary';
const String evDormantUserDetected = 'dormant_user_detected';
const String evResurrectedUserDetected = 'resurrected_user_detected';

// ════════════════════════════════════════════════════════════════════
// B.7 — Backend, edge functions e LLM — 17 eventos (server-side)
// ════════════════════════════════════════════════════════════════════

const String evEdgeFunctionInvoked = 'edge_function_invoked';
const String evEdgeFunctionColdStart = 'edge_function_cold_start';
const String evLlmCallMade = 'llm_call_made';
const String evLlmCallFailed = 'llm_call_failed';
const String evLlmResponseAntiInventionFlagged = 'llm_response_anti_invention_flagged';
const String evDbQuerySlow = 'db_query_slow';
const String evApifySyncStarted = 'apify_sync_started';
const String evApifySyncCompleted = 'apify_sync_completed';
const String evApifySyncFailed = 'apify_sync_failed';
const String evAtsScraperCompleted = 'ats_scraper_completed';
const String evBrazilScraperCompleted = 'brazil_scraper_completed';
const String evDailyReportSent = 'daily_report_sent';
const String evPushSendInitiated = 'push_send_initiated';
const String evPushSendCompleted = 'push_send_completed';
const String evWebhookReceived = 'webhook_received';
const String evRateLimitHit = 'rate_limit_hit';
const String evPgcronJobExecuted = 'pgcron_job_executed';

// ════════════════════════════════════════════════════════════════════
// B.8 — Aquisição, atribuição e canal — 7 eventos
// ════════════════════════════════════════════════════════════════════

const String evInstallAttributed = 'install_attributed';
const String evDeepLinkOpened = 'deep_link_opened';
const String evDeepLinkFailedToResolve = 'deep_link_failed_to_resolve';
const String evReferrerCaptured = 'referrer_captured';
const String evFirstSessionAttribution = 'first_session_attribution';
const String evQrCodeScanned = 'qr_code_scanned';
const String evAdLinkClickedInbound = 'ad_link_clicked_inbound';

// ════════════════════════════════════════════════════════════════════
// B.9 — Sociais, share e viralidade — 7 eventos
// ════════════════════════════════════════════════════════════════════

const String evShareSheetOpened = 'share_sheet_opened';
const String evShareCompleted = 'share_completed';
const String evShareCancelled = 'share_cancelled';
const String evInviteLinkGenerated = 'invite_link_generated';
const String evInviteLinkOpenedInbound = 'invite_link_opened_inbound';
const String evInviteConvertedToSignup = 'invite_converted_to_signup';
const String evReferralCreditGranted = 'referral_credit_granted';

// ════════════════════════════════════════════════════════════════════
// B.10 — Notificação push — 12 eventos
// ════════════════════════════════════════════════════════════════════

const String evPushReceivedBackground = 'push_received_background';
const String evPushDisplayed = 'push_displayed';
const String evPushOpened = 'push_opened';
const String evPushDismissed = 'push_dismissed';
const String evPushActionButtonTapped = 'push_action_button_tapped';
const String evPushIgnored = 'push_ignored';
const String evPushPermissionRequested = 'push_permission_requested';
const String evPushPermissionGranted = 'push_permission_granted';
const String evPushPermissionDenied = 'push_permission_denied';
const String evPushPermissionRevokedDetected = 'push_permission_revoked_detected';
const String evPushOptoutViaSettings = 'push_optout_via_settings';
const String evPushResubscribedViaSettings = 'push_resubscribed_via_settings';

// ════════════════════════════════════════════════════════════════════
// B.11 — Tutorial, discovery e ajuda — 10 eventos
// ════════════════════════════════════════════════════════════════════

const String evTutorialStarted = 'tutorial_started';
const String evTutorialStepShown = 'tutorial_step_shown';
const String evTutorialStepDismissed = 'tutorial_step_dismissed';
const String evTutorialCompleted = 'tutorial_completed';
const String evTutorialSkipped = 'tutorial_skipped';
const String evFeatureFirstUsed = 'feature_first_used';
const String evHelpLinkClicked = 'help_link_clicked';
const String evFaqOpened = 'faq_opened';
const String evFeedbackFormOpened = 'feedback_form_opened';
const String evFeedbackSubmitted = 'feedback_submitted';

// ════════════════════════════════════════════════════════════════════
// B.12 — Monetização proativa (B2B futuro) — 13 eventos
// ════════════════════════════════════════════════════════════════════

const String evPaywallShown = 'paywall_shown';
const String evPaywallDismissed = 'paywall_dismissed';
const String evPricingPageShown = 'pricing_page_shown';
const String evPurchaseInitiated = 'purchase_initiated';
const String evPurchaseCompleted = 'purchase_completed';
const String evPurchaseFailed = 'purchase_failed';
const String evSubscriptionRenewed = 'subscription_renewed';
const String evSubscriptionCancelled = 'subscription_cancelled';
const String evB2bCompanyRegistered = 'b2b_company_registered';
const String evB2bJobPublished = 'b2b_job_published';
const String evB2bCandidateViewed = 'b2b_candidate_viewed';
const String evB2bCandidateContacted = 'b2b_candidate_contacted';
const String evB2bDashboardOpened = 'b2b_dashboard_opened';

// ════════════════════════════════════════════════════════════════════
// B.13 — Tela e navegação granular — 10 eventos
// ════════════════════════════════════════════════════════════════════

const String evScreenViewed = 'screen_viewed';
const String evScreenExited = 'screen_exited';
const String evNavTabSwitched = 'nav_tab_switched';
const String evNavBack = 'nav_back';
const String evNavDeepLinkIntraApp = 'nav_deep_link_intra_app';
const String evModalOpened = 'modal_opened';
const String evModalClosed = 'modal_closed';
const String evSearchInitiated = 'search_initiated';
const String evFilterApplied = 'filter_applied';
const String evSortChanged = 'sort_changed';

// ════════════════════════════════════════════════════════════════════
// B.14 — Swipe (diferencial Stage) — 19 eventos
// ════════════════════════════════════════════════════════════════════

const String evJobCardShown = 'job_card_shown';
const String evJobCardDwellStarted = 'job_card_dwell_started';
const String evJobCardDwellEnded = 'job_card_dwell_ended';
const String evJobSwiped = 'job_swiped';
const String evJobSwipeUndo = 'job_swipe_undo';
const String evJobSwipeRedo = 'job_swipe_redo';
const String evJobSwipePaused = 'job_swipe_paused';
const String evJobBulkSwipeBurst = 'job_bulk_swipe_burst';
const String evJobRevisitedFromCurtidas = 'job_revisited_from_curtidas';
const String evJobDetailsOpened = 'job_details_opened';
const String evJobDetailsScrollProgress = 'job_details_scroll_progress';
const String evJobDetailsApplyClicked = 'job_details_apply_clicked';
const String evJobDetailsApplyExternalOpened = 'job_details_apply_external_opened';
const String evJobDetailsApplyReturned = 'job_details_apply_returned';
const String evJobDetailsShareClicked = 'job_details_share_clicked';
const String evJobDetailsUnsaveClicked = 'job_details_unsave_clicked';
const String evJobDetailsClosed = 'job_details_closed';
const String evFeedCurtidasOpened = 'feed_curtidas_opened';
const String evFeedCurtidasFiltered = 'feed_curtidas_filtered';

// ════════════════════════════════════════════════════════════════════
// B.15 — Adaptação de CV — 20 eventos
// ════════════════════════════════════════════════════════════════════

const String evAdaptIntentClicked = 'adapt_intent_clicked';
const String evAdaptStarted = 'adapt_started';
const String evAdaptLoadingShown = 'adapt_loading_shown';
const String evAdaptSucceeded = 'adapt_succeeded';
const String evAdaptFailed = 'adapt_failed';
const String evAdaptDiffShown = 'adapt_diff_shown';
const String evAdaptDiffScrollProgress = 'adapt_diff_scroll_progress';
const String evAdaptSkillsConfirmationShown = 'adapt_skills_confirmation_shown';
const String evAdaptSkillAccepted = 'adapt_skill_accepted';
const String evAdaptSkillRejected = 'adapt_skill_rejected';
const String evAdaptSkillAddedManually = 'adapt_skill_added_manually';
const String evAdaptTemplateChanged = 'adapt_template_changed';
const String evAdaptSectionEditedManually = 'adapt_section_edited_manually';
const String evAdaptPreviewOpened = 'adapt_preview_opened';
const String evAdaptPreviewZoomed = 'adapt_preview_zoomed';
const String evAdaptPdfDownloaded = 'adapt_pdf_downloaded';
const String evAdaptPdfShared = 'adapt_pdf_shared';
const String evAdaptAbandoned = 'adapt_abandoned';
const String evAdaptApplyUsed = 'adapt_apply_used';
const String evAdaptReusedForAnotherJob = 'adapt_reused_for_another_job';

// ════════════════════════════════════════════════════════════════════
// B.16 — Trilha (gamificação) — 23 eventos
// ════════════════════════════════════════════════════════════════════

const String evTrilhaMapShown = 'trilha_map_shown';
const String evTrilhaPhaseCardSeen = 'trilha_phase_card_seen';
const String evTrilhaPhaseLockedTapped = 'trilha_phase_locked_tapped';
const String evPhaseStarted = 'phase_started';
const String evPhaseIntroSeen = 'phase_intro_seen';
const String evPhaseStepShown = 'phase_step_shown';
const String evPhaseStepScrollProgress = 'phase_step_scroll_progress';
const String evPhaseStepTimeSpent = 'phase_step_time_spent';
const String evPhaseStepCompleted = 'phase_step_completed';
const String evPhaseStepAbandoned = 'phase_step_abandoned';
const String evPhaseQuizShown = 'phase_quiz_shown';
const String evPhaseQuizAnswered = 'phase_quiz_answered';
const String evPhaseQuizPassed = 'phase_quiz_passed';
const String evPhaseQuizFailed = 'phase_quiz_failed';
const String evPhaseHintRequested = 'phase_hint_requested';
const String evPhaseActionCompleted = 'phase_action_completed';
const String evPhaseCompleted = 'phase_completed';
const String evPhaseCelebrationShown = 'phase_celebration_shown';
const String evPhaseShareClicked = 'phase_share_clicked';
const String evTrilhaCompleted = 'trilha_completed';
const String evTrilhaCvFinalDownloaded = 'trilha_cv_final_downloaded';
const String evTrilhaResumedAfterPause = 'trilha_resumed_after_pause';
const String evTrilhaRestartPhase = 'trilha_restart_phase';

// ════════════════════════════════════════════════════════════════════
// B.17 — Feed de vagas (gerais) — 9 eventos
// ════════════════════════════════════════════════════════════════════

const String evFeedOpened = 'feed_opened';
const String evFeedLoaded = 'feed_loaded';
const String evFeedLoadFailed = 'feed_load_failed';
const String evFeedExhausted = 'feed_exhausted';
const String evFeedRefreshPulled = 'feed_refresh_pulled';
const String evFeedCacheStaleDetected = 'feed_cache_stale_detected';
const String evFeedPositionResumed = 'feed_position_resumed';

/// FASE 2 (T2.2): user alternou swipe↔lista no toggle da aba Vagas
/// (flag feed_list_v1). Prop: mode ('swipe'|'list'). A tese da lista é
/// lida pela adoção deste toggle + save-rate por feed_mode (decisão do
/// fundador 12/06: lista é opt-in, swipe segue padrão).
const String evFeedModeToggled = 'feed_mode_toggled';

/// FASE 2 (T2.3): user pediu uma empresa no estado de exaustão do feed
/// (row em company_requests). Aceite #7 da fase: ≥1 pedido real em prod.
const String evCompanyRequested = 'company_requested';
const String evMatchScoreVisualizationShown = 'match_score_visualization_shown';
const String evMatchScoreExplainedTapped = 'match_score_explained_tapped';

// ════════════════════════════════════════════════════════════════════
// B.18 — Identidade e conta — 8 eventos
// ════════════════════════════════════════════════════════════════════

const String evIdentifyCalled = 'identify_called';
const String evAliasCreated = 'alias_created';
const String evMultiDeviceDetected = 'multi_device_detected';
const String evAccountRecoveryStarted = 'account_recovery_started';
const String evProfilePicUploaded = 'profile_pic_uploaded';
const String evProfilePicRemoved = 'profile_pic_removed';
const String evEmailChanged = 'email_changed';
const String evPhoneChanged = 'phone_changed';

// ════════════════════════════════════════════════════════════════════
// B.19 — Configurações e preferências — 11 eventos
// ════════════════════════════════════════════════════════════════════

const String evSettingsOpened = 'settings_opened';
const String evSettingsSectionOpened = 'settings_section_opened';
const String evSettingChanged = 'setting_changed';
const String evNotificationPreferenceChanged = 'notification_preference_changed';
const String evPrivacyPreferenceChanged = 'privacy_preference_changed';
const String evThemePreferenceChanged = 'theme_preference_changed';
const String evLanguagePreferenceChanged = 'language_preference_changed';
const String evPrefLocationChanged = 'pref_location_changed';
const String evPrefAreaChanged = 'pref_area_changed';
const String evPrefModalityChanged = 'pref_modality_changed';
const String evPrefExperienceLevelChanged = 'pref_experience_level_changed';

// ════════════════════════════════════════════════════════════════════
// B.20 — Meta, governança e instrumentação — 12 eventos
// ════════════════════════════════════════════════════════════════════

const String evAnalyticsInitialized = 'analytics_initialized';
const String evAnalyticsOptedOut = 'analytics_opted_out';
const String evAnalyticsOptedIn = 'analytics_opted_in';
const String evSessionReplayStarted = 'session_replay_started';
const String evSessionReplayPaused = 'session_replay_paused';
const String evEventQueueOverflow = 'event_queue_overflow';
const String evEventSentOfflineDeferred = 'event_sent_offline_deferred';
const String evEventFlushedToServer = 'event_flushed_to_server';
const String evFeatureFlagEvaluated = 'feature_flag_evaluated';
const String evExperimentExposed = 'experiment_exposed';
const String evCrashDetectedNextSession = 'crash_detected_next_session';
const String evAppTerminatedClean = 'app_terminated_clean';

// ════════════════════════════════════════════════════════════════════
// B.21 — Domain extras (eventos específicos do Stage não cobertos pelo
// catálogo genérico do plano v2 mas que continuam ativos no app)
// ════════════════════════════════════════════════════════════════════

/// Backup genérico do funil de onboarding (legacy). Usado pelo método
/// `onboardingStepReached()` que cobre múltiplas etapas com `step_id`.
/// Mantido pra continuidade — as etapas específicas (B.1 #25-39) são
/// preferidas quando aplicável.
const String evOnboardingStepReached = 'onboarding_step_reached';

/// CV base exportado (resume tab, não adaptado pra vaga específica).
/// Distinto de `evAdaptPdfDownloaded` (B.15) que é CV adaptado.
const String evCvExported = 'cv_exported';

/// Template do CV base trocado (resume tab). Distinto de
/// `evAdaptTemplateChanged` que é template no fluxo de adapt.
const String evCvTemplateChanged = 'cv_template_changed';

/// Bottom-sheet de seleção de template do CV base aberto.
const String evCvTemplateSelectorOpened = 'cv_template_selector_opened';

/// Save do CV adaptado na biblioteca falhou. Não-fatal (user ainda
/// recebe PDF via share), mas crítico pra debug.
const String evCvLibrarySaveFailed = 'cv_library_save_failed';

/// Confirmação de skills do adapt: usuário confirmou as skills.
const String evAdaptSkillsConfirmationCompleted = 'adapt_skills_confirmation_completed';

/// Confirmação de skills do adapt: auto-skipada porque não tem o que
/// confirmar (CV completo, sem requirements, ou extração falhou).
const String evAdaptSkillsConfirmationAutoSkipped = 'adapt_skills_confirmation_auto_skipped';

/// Senha trocada com sucesso em settings.
const String evAuthPasswordChanged = 'auth_password_changed';

/// Falha em trocar senha (wrong_current, weak, network, etc).
const String evAuthPasswordChangeFailed = 'auth_password_change_failed';

/// Migração OAuth iniciada (users legacy email+senha → Apple/Google).
const String evAuthOauthMigrationStarted = 'auth_oauth_migration_started';
const String evAuthOauthMigrationCompleted = 'auth_oauth_migration_completed';
const String evAuthOauthMigrationFailed = 'auth_oauth_migration_failed';

/// "Fale com os fundadores" foi tocado. High-intent qualitativo — lista
/// de pessoas pra ligar/entrevistar.
const String evFoundersContactOpened = 'founders_contact_opened';

/// Usuário removeu uma vaga curtida. Volume baixíssimo no histórico (1/30d).
const String evJobUnsaved = 'job_unsaved';

/// Primeira ação de salvar mostrou o banner de celebração (feed).
const String evFirstSaveCelebrationShown = 'first_save_celebration_shown';

/// User dismissou o banner de celebração e seguiu navegando.
const String evFirstSaveCelebrationContinued = 'first_save_celebration_continued';

/// User dismissou o banner persistente "primeira save" na aba Curtidas.
const String evFirstSaveBannerDismissed = 'first_save_banner_dismissed';

/// User tocou em "Reativar notificações" em settings. Dispara antes do
/// prompt nativo / abertura de Settings.app — pre-condição pra medir
/// taxa de sucesso da reativação.
const String evPushReactivateTapped = 'push_reactivate_tapped';

/// Após o reactivatePush retornar do iOS — emite com `granted` (bool) e
/// `new_status` ('subscribed' | 'denied' | etc). Pareado com tapped
/// pra calcular taxa de sucesso da reativação.
const String evPushReactivateCompleted = 'push_reactivate_completed';

/// PDF do CV renderizado com sucesso (HTML → PDF via Printing). Distinto
/// de `evCvExported` (intent do user) e `evPdfRenderCompleted` (perf):
/// este é o evento de negócio "PDF saiu" com template, source, version
/// e duration. Volume alto pré-cutover.
const String evPdfGenerated = 'pdf_generated';

/// Sub-tab da aba Perfil trocada (info / preferences / resumes).
/// Distinto de `evNavTabSwitched` (que é nav principal: Vagas/CV/Trilha/Perfil).
const String evProfileTabChanged = 'profile_tab_changed';

/// User tocou em "Continuar" na AllSetScreen (transição entre masking
/// questions e review). Volume baixo (~7-10/30d pré-cutover) mas
/// preserva continuidade.
const String evOnboardingAllSetContinued = 'onboarding_all_set_continued';

/// Micro-questionário de fit cultural aberto a partir da aba Vagas.
const String evCultureFitPromptOpened = 'match_culture_fit_prompt_opened';

/// Uma resposta do questionário de fit cultural foi selecionada.
const String evCultureFitQuestionAnswered =
    'match_culture_fit_question_answered';

/// As 4 respostas de fit cultural foram salvas.
const String evCultureFitCompleted = 'match_culture_fit_completed';

// ════════════════════════════════════════════════════════════════════
// Fase 1 — applications (espinha de dados; R7: catálogo + emissor no
// mesmo PR). Transições server-side (edges admin, Fase 4) emitirão via
// _shared/posthog.ts captureEvent — estes 3 são os client-side.
// ════════════════════════════════════════════════════════════════════

/// Application criada pelo usuário (toggle "Marcar como aplicada"; adição
/// manual chega na F3). Props: application_id, application_type, job_id?,
/// application_method?.
const String evApplicationCreated = 'application_created';

/// Transição de estado feita PELO usuário (actor user). Props:
/// application_id, application_type, from_status, to_status, job_id?.
const String evApplicationStateChanged = 'application_state_changed';

/// Reabertura (rejected/withdrawn → submitted) pelo usuário. Props:
/// application_id, application_type, job_id?.
const String evApplicationReopened = 'application_reopened';

// ════════════════════════════════════════════════════════════════════
// Allowlist agregada — usada pelo wrapper pra rejeitar nomes não-catalogados.
// ════════════════════════════════════════════════════════════════════

/// Set imutável de TODOS os nomes de evento permitidos no app pós-cutover.
/// Wrapper `Analytics.shared.track(eventName)` checa contra esse set em
/// debug mode e loga warning se nome não está aqui. Em release, passa
/// silenciosamente (pra não quebrar comportamento por bug de catálogo).
const Set<String> kAllowedEventNames = {
  // Fase 1 — applications
  evApplicationCreated, evApplicationStateChanged, evApplicationReopened,
  // B.1
  evAppOpened, evAppFirstOpenEver, evAuthSignupLandingShown,
  evAuthSignupMethodChosen, evAuthSignupStarted, evAuthSignupCompleted,
  evAuthSignupFailed, evAuthLoginAttempt, evAuthLoginSucceeded,
  evAuthLoginFailed, evAuthEmailVerificationSent,
  evAuthEmailVerificationCompleted, evAuthPhoneOtpRequested,
  evAuthPhoneOtpValidated, evAuthLogout, evAuthAccountDeletionRequested,
  evAuthAccountDeletionCompleted, evOnboardingStarted,
  evOnboardingTwoDoorsShown, evOnboardingDoorChosen,
  evOnboardingCvUploadPickerOpened, evOnboardingCvUploadStarted,
  evOnboardingCvUploadCompleted, evOnboardingCvUploadFailed,
  evOnboardingCvQuestionShown, evOnboardingCvQuestionAnswered,
  evOnboardingCvQuestionSkipped, evOnboardingProfileExtractionStarted,
  evOnboardingProfileExtractionSucceeded,
  evOnboardingProfileExtractionFailed, evOnboardingPersonalReviewShown,
  evOnboardingPersonalFieldEdited, evOnboardingPersonalReviewConfirmed,
  evOnboardingCvReviewShown, evOnboardingCvSectionEdited,
  evOnboardingCvReviewConfirmed, evOnboardingPrefStepShown,
  evOnboardingPrefStepAnswered, evOnboardingPrefStepSkipped,
  evOnboardingMaskingQuestionShown, evOnboardingMaskingQuestionAnswered,
  evOnboardingAllSetShown, evOnboardingCompleted, evOnboardingAbandoned,
  evOnboardingCvImportAbandoned,
  evHomeFirstShown, evHomeShown, evCvTabFirstShown, evTrilhaTabFirstShown,
  evProfileTabFirstShown, evActivationMilestoneHit,
  // B.2
  evScrollDepth, evScreenDwellTime, evTapHesitation, evRetapAfterMiss,
  evLongPressDetected, evCopyDetected, evPasteDetected, evScreenshotTaken,
  evSwipeVelocityMeasured, evPinchZoom, evDoubleTapDetected,
  evSwipeIndecision, evCardReturnedToCenter, evTextFieldFocused,
  evTextFieldBlurred, evTextFieldAbandoned,
  // B.3
  evFormValidationErrorShown, evModalShown, evModalDismissed,
  evBackButtonPressed, evNetworkErrorEncountered, evTimeoutEncountered,
  evRetryAttempted, evAppForceKilledDetected, evEmptyStateShown,
  evEmptyStateCtaClicked, evErrorScreenShown, evErrorScreenActionTaken,
  evPermissionRequested, evPermissionGranted, evPermissionDenied,
  evPermissionSettingsOpened, evPermissionReGranted,
  evFeatureUnavailableAttempted,
  // B.4
  evAppColdStart, evAppWarmStart, evScreenTimeToInteractive,
  evImageLoadTime, evFrameDropDetected, evMemoryWarningReceived,
  evScrollFpsMeasured, evApiCallCompleted, evApiCallFailed, evCacheHit,
  evCacheMiss, evPdfRenderStarted, evPdfRenderCompleted, evPdfRenderFailed,
  // B.5
  evDeviceContextSnapshot, evNetworkTypeChanged, evDarkModeToggled,
  evAccessibilityEnabledDetected, evLanguageMismatchDetected,
  evAppVersionOutdated,
  // B.6
  evSessionStarted, evSessionEnded, evAppBackgrounded, evAppForegrounded,
  evSessionInterrupted, evStreakDayStarted, evStreakBroken,
  evLifecycleAnniversary, evDormantUserDetected, evResurrectedUserDetected,
  // B.7
  evEdgeFunctionInvoked, evEdgeFunctionColdStart, evLlmCallMade,
  evLlmCallFailed, evLlmResponseAntiInventionFlagged, evDbQuerySlow,
  evApifySyncStarted, evApifySyncCompleted, evApifySyncFailed,
  evAtsScraperCompleted, evBrazilScraperCompleted, evDailyReportSent,
  evPushSendInitiated, evPushSendCompleted, evWebhookReceived,
  evRateLimitHit, evPgcronJobExecuted,
  // B.8
  evInstallAttributed, evDeepLinkOpened, evDeepLinkFailedToResolve,
  evReferrerCaptured, evFirstSessionAttribution, evQrCodeScanned,
  evAdLinkClickedInbound,
  // B.9
  evShareSheetOpened, evShareCompleted, evShareCancelled,
  evInviteLinkGenerated, evInviteLinkOpenedInbound,
  evInviteConvertedToSignup, evReferralCreditGranted,
  // B.10
  evPushReceivedBackground, evPushDisplayed, evPushOpened, evPushDismissed,
  evPushActionButtonTapped, evPushIgnored, evPushPermissionRequested,
  evPushPermissionGranted, evPushPermissionDenied,
  evPushPermissionRevokedDetected, evPushOptoutViaSettings,
  evPushResubscribedViaSettings,
  // B.11
  evTutorialStarted, evTutorialStepShown, evTutorialStepDismissed,
  evTutorialCompleted, evTutorialSkipped, evFeatureFirstUsed,
  evHelpLinkClicked, evFaqOpened, evFeedbackFormOpened,
  evFeedbackSubmitted,
  // B.12
  evPaywallShown, evPaywallDismissed, evPricingPageShown,
  evPurchaseInitiated, evPurchaseCompleted, evPurchaseFailed,
  evSubscriptionRenewed, evSubscriptionCancelled, evB2bCompanyRegistered,
  evB2bJobPublished, evB2bCandidateViewed, evB2bCandidateContacted,
  evB2bDashboardOpened,
  // B.13
  evScreenViewed, evScreenExited, evNavTabSwitched, evNavBack,
  evNavDeepLinkIntraApp, evModalOpened, evModalClosed, evSearchInitiated,
  evFilterApplied, evSortChanged,
  // B.14
  evJobCardShown, evJobCardDwellStarted, evJobCardDwellEnded, evJobSwiped,
  evJobSwipeUndo, evJobSwipeRedo, evJobSwipePaused, evJobBulkSwipeBurst,
  evJobRevisitedFromCurtidas, evJobDetailsOpened,
  evJobDetailsScrollProgress, evJobDetailsApplyClicked,
  evJobDetailsApplyExternalOpened, evJobDetailsApplyReturned,
  evJobDetailsShareClicked, evJobDetailsUnsaveClicked,
  evJobDetailsClosed, evFeedCurtidasOpened, evFeedCurtidasFiltered,
  // B.15
  evAdaptIntentClicked, evAdaptStarted, evAdaptLoadingShown,
  evAdaptSucceeded, evAdaptFailed, evAdaptDiffShown,
  evAdaptDiffScrollProgress, evAdaptSkillsConfirmationShown,
  evAdaptSkillAccepted, evAdaptSkillRejected, evAdaptSkillAddedManually,
  evAdaptTemplateChanged, evAdaptSectionEditedManually,
  evAdaptPreviewOpened, evAdaptPreviewZoomed, evAdaptPdfDownloaded,
  evAdaptPdfShared, evAdaptAbandoned, evAdaptApplyUsed,
  evAdaptReusedForAnotherJob,
  // B.16
  evTrilhaMapShown, evTrilhaPhaseCardSeen, evTrilhaPhaseLockedTapped,
  evPhaseStarted, evPhaseIntroSeen, evPhaseStepShown,
  evPhaseStepScrollProgress, evPhaseStepTimeSpent, evPhaseStepCompleted,
  evPhaseStepAbandoned, evPhaseQuizShown, evPhaseQuizAnswered,
  evPhaseQuizPassed, evPhaseQuizFailed, evPhaseHintRequested,
  evPhaseActionCompleted, evPhaseCompleted, evPhaseCelebrationShown,
  evPhaseShareClicked, evTrilhaCompleted, evTrilhaCvFinalDownloaded,
  evTrilhaResumedAfterPause, evTrilhaRestartPhase,
  // B.17
  evFeedOpened, evFeedLoaded, evFeedLoadFailed, evFeedExhausted,
  evFeedRefreshPulled, evFeedCacheStaleDetected, evFeedPositionResumed,
  evFeedModeToggled, evCompanyRequested,
  evMatchScoreVisualizationShown, evMatchScoreExplainedTapped,
  // B.18
  evIdentifyCalled, evAliasCreated, evMultiDeviceDetected,
  evAccountRecoveryStarted, evProfilePicUploaded, evProfilePicRemoved,
  evEmailChanged, evPhoneChanged,
  // B.19
  evSettingsOpened, evSettingsSectionOpened, evSettingChanged,
  evNotificationPreferenceChanged, evPrivacyPreferenceChanged,
  evThemePreferenceChanged, evLanguagePreferenceChanged,
  evPrefLocationChanged, evPrefAreaChanged, evPrefModalityChanged,
  evPrefExperienceLevelChanged,
  // B.20
  evAnalyticsInitialized, evAnalyticsOptedOut, evAnalyticsOptedIn,
  evSessionReplayStarted, evSessionReplayPaused, evEventQueueOverflow,
  evEventSentOfflineDeferred, evEventFlushedToServer,
  evFeatureFlagEvaluated, evExperimentExposed,
  evCrashDetectedNextSession, evAppTerminatedClean,
  // B.21 — domain extras
  evOnboardingStepReached, evCvExported, evCvTemplateChanged,
  evCvTemplateSelectorOpened, evCvLibrarySaveFailed,
  evAdaptSkillsConfirmationCompleted, evAdaptSkillsConfirmationAutoSkipped,
  evAuthPasswordChanged, evAuthPasswordChangeFailed,
  evAuthOauthMigrationStarted, evAuthOauthMigrationCompleted,
  evAuthOauthMigrationFailed, evFoundersContactOpened,
  evJobUnsaved, evFirstSaveCelebrationShown,
  evFirstSaveCelebrationContinued, evFirstSaveBannerDismissed,
  evPushReactivateTapped, evPushReactivateCompleted,
  evPdfGenerated, evProfileTabChanged, evOnboardingAllSetContinued,
  evCultureFitPromptOpened, evCultureFitQuestionAnswered,
  evCultureFitCompleted,
};
