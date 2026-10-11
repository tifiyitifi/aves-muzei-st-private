import 'package:aves/features/meta_settings/data/def_visibility.dart';
import 'package:aves/features/meta_settings/model/editor_keys.dart';
import 'package:aves/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:aves/features/meta_settings/model/enum/settings_category.dart';
import 'package:aves/features/meta_settings/model/page_keys.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/model/setting_ids.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/settings/enums/coordinate_format.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/ref/poi.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';

/// The declarative catalog driving the metadata settings surface (v2).
///
/// Sections migrate whole, one category at a time: a category's defs are added
/// here when its legacy section is ported. Categories absent from the catalog
/// fall back to a fork-owned copy of the legacy section.
final List<SettingDef> metaSettingsCatalog = [
  ..._displayDefs,
  ..._languageDefs,
  ..._accessibilityDefs,
  ..._privacyDefs,
  ..._viewerDefs,
  ..._videoDefs,
  ..._thumbnailsDefs,
  ..._navigationDefs,
  ..._advancedDefs,
];

/// Defs of [category], ordered by `sortOrder`.
List<SettingDef> metaSettingsDefsFor(SettingsCategory category) =>
    metaSettingsCatalog.where((def) => def.category == category).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

// Display

final List<SettingDef> _displayDefs = [
  SettingDef(
    key: SettingKeys.themeBrightnessKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsThemeBrightnessTile,
    reader: (settings) => settings.themeBrightness,
    enumValues: AvesThemeBrightness.values,
    enumName: (context, value) => (value as AvesThemeBrightness).getName(context),
    dialogTitle: (context) => context.l10n.settingsThemeBrightnessDialogTitle,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 10,
  ),
  SettingDef(
    key: SettingKeys.themeColorModeKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsThemeColorHighlights,
    editorKey: MetaEditorKeys.themeColorMode,
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.enableDynamicColorKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsThemeEnableDynamicColor,
    reader: (settings) => settings.enableDynamicColor,
    availabilityKey: DefVisibility.dynamicColor,
    sortOrder: 30,
  ),
  SettingDef(
    key: SettingKeys.enableBlurEffectKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsViewerEnableOverlayBlurEffect,
    reader: (settings) => settings.enableBlurEffect,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.maxBrightnessKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsViewerMaximumBrightness,
    reader: (settings) => settings.maxBrightness,
    enumValues: MaxBrightness.values,
    enumName: (context, value) => (value as MaxBrightness).getName(context),
    availabilityKey: DefVisibility.notTv,
    sortOrder: 50,
  ),
  SettingDef(
    key: SettingKeys.displayRefreshRateModeKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsDisplayRefreshRateModeTile,
    reader: (settings) => settings.displayRefreshRateMode,
    enumValues: DisplayRefreshRateMode.values,
    enumName: (context, value) => (value as DisplayRefreshRateMode).getName(context),
    dialogTitle: (context) => context.l10n.settingsDisplayRefreshRateModeDialogTitle,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 60,
  ),
  SettingDef(
    key: SettingKeys.forceTvLayoutKey,
    category: SettingsCategory.display,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsDisplayUseTvInterface,
    editorKey: MetaEditorKeys.forceTvLayout,
    availabilityKey: DefVisibility.notTelevision,
    sortOrder: 70,
  ),
];

// Language

final List<SettingDef> _languageDefs = [
  SettingDef(
    key: SettingKeys.localeKey,
    category: SettingsCategory.language,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsLanguageTile,
    editorKey: MetaEditorKeys.locale,
    sortOrder: 10,
  ),
  SettingDef(
    key: SettingKeys.calendarKey,
    category: SettingsCategory.language,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsCalendarTile,
    reader: (settings) => settings.calendar,
    mutator: (settings, value) => settings.calendar = value as ACalendar,
    enumValues: const [ACalendar.gregorian, ACalendar.hijriTbla, ACalendar.hijriUmalqura, ACalendar.persian],
    enumName: (context, value) => (value as ACalendar).getName(context),
    optionSubtitle: (context, value) {
      final locale = settings.avesLocale.copyWith(calendar: value as ACalendar);
      return locale.yMMMMd(DateTime.now());
    },
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.coordinateFormatKey,
    category: SettingsCategory.language,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsCoordinateFormatTile,
    reader: (settings) => settings.coordinateFormat,
    enumValues: CoordinateFormat.values,
    enumName: (context, value) => (value as CoordinateFormat).getName(context),
    dialogTitle: (context) => context.l10n.settingsCoordinateFormatDialogTitle,
    optionSubtitle: (context, value) => (value as CoordinateFormat).format(context, PointsOfInterest.pointNemo),
    sortOrder: 30,
  ),
  SettingDef(
    key: SettingKeys.unitSystemKey,
    category: SettingsCategory.language,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsUnitSystemTile,
    reader: (settings) => settings.unitSystem,
    enumValues: UnitSystem.values,
    enumName: (context, value) => (value as UnitSystem).getName(context),
    dialogTitle: (context) => context.l10n.settingsUnitSystemDialogTitle,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.forceWesternArabicNumeralsKey,
    category: SettingsCategory.language,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsForceWesternArabicNumeralsTile,
    reader: (settings) => settings.forceWesternArabicNumerals,
    mutator: (settings, value) => settings.forceWesternArabicNumerals = value as bool,
    sortOrder: 50,
  ),
];

// Accessibility

final List<SettingDef> _accessibilityDefs = [
  SettingDef(
    key: SettingKeys.showPinchGestureAlternativesKey,
    category: SettingsCategory.accessibility,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsAccessibilityShowPinchGestureAlternatives,
    reader: (settings) => settings.showPinchGestureAlternatives,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 10,
  ),
  SettingDef(
    key: SettingKeys.accessibilityAnimationsKey,
    category: SettingsCategory.accessibility,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsRemoveAnimationsTile,
    reader: (settings) => settings.accessibilityAnimations,
    enumValues: AccessibilityAnimations.values,
    enumName: (context, value) => (value as AccessibilityAnimations).getName(context),
    dialogTitle: (context) => context.l10n.settingsRemoveAnimationsDialogTitle,
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.timeToTakeActionKey,
    category: SettingsCategory.accessibility,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsTimeToTakeActionTile,
    editorKey: MetaEditorKeys.timeToTakeAction,
    sortOrder: 30,
  ),
];

// Privacy

final List<SettingDef> _privacyDefs = [
  SettingDef(
    key: MetaPageKeys.permissions,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsPermissionsTile,
    editorKey: MetaEditorKeys.permissions,
    sortOrder: 10,
  ),
  SettingDef(
    key: MetaPageKeys.hiddenItems,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsHiddenItemsTile,
    routeName: MetaPageKeys.hiddenItems,
    sortOrder: 20,
  ),
  SettingDef(
    key: MetaPageKeys.storageAccess,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsStorageAccessTile,
    routeName: MetaPageKeys.storageAccess,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 30,
  ),
  SettingDef(
    key: SettingKeys.enableBinKey,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsEnableBin,
    editorKey: MetaEditorKeys.enableBin,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.saveSearchHistoryKey,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsSaveSearchHistory,
    reader: (settings) => settings.saveSearchHistory,
    mutator: (settings, value) {
      settings.saveSearchHistory = value as bool;
      if (!value) settings.searchHistory = [];
    },
    sortOrder: 50,
  ),
  SettingDef(
    key: SettingKeys.autoExportPathKey,
    category: SettingsCategory.privacy,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsAutoExportSettings,
    editorKey: MetaEditorKeys.autoExportSettings,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 60,
  ),
];

// Viewer

final List<SettingDef> _viewerDefs = [
  SettingDef(
    key: MetaPageKeys.viewerActions,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsViewerQuickActionsTile,
    routeName: MetaPageKeys.viewerActions,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 10,
  ),
  SettingDef(
    key: MetaPageKeys.viewerOverlay,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsViewerOverlayTile,
    routeName: MetaPageKeys.viewerOverlay,
    sortOrder: 20,
  ),
  SettingDef(
    key: MetaPageKeys.viewerSlideshow,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsViewerSlideshowTile,
    routeName: MetaPageKeys.viewerSlideshow,
    sortOrder: 30,
  ),
  SettingDef(
    key: SettingKeys.viewerGestureSideTapNextKey,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsViewerGestureSideTapNext,
    reader: (settings) => settings.viewerGestureSideTapNext,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.viewerUseCutoutKey,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsViewerUseCutout,
    editorKey: MetaEditorKeys.viewerUseCutout,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 50,
  ),
  SettingDef(
    key: SettingKeys.enableMotionPhotoAutoPlayKey,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsMotionPhotoAutoPlay,
    reader: (settings) => settings.enableMotionPhotoAutoPlay,
    sortOrder: 60,
  ),
  SettingDef(
    key: SettingKeys.imageBackgroundKey,
    category: SettingsCategory.viewer,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsImageBackground,
    editorKey: MetaEditorKeys.viewerImageBackground,
    sortOrder: 70,
  ),
];

// Video

final List<SettingDef> _videoDefs = [
  SettingDef(
    key: MetaSettingIds.videoShowVideos,
    category: SettingsCategory.video,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsVideoShowVideos,
    editorKey: MetaEditorKeys.videoShowVideos,
    sortOrder: 10,
  ),
  SettingDef(
    key: MetaPageKeys.videoPlayback,
    category: SettingsCategory.video,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsVideoPlaybackTile,
    routeName: MetaPageKeys.videoPlayback,
    sortOrder: 20,
  ),
  SettingDef(
    key: MetaPageKeys.videoControls,
    category: SettingsCategory.video,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsVideoControlsTile,
    routeName: MetaPageKeys.videoControls,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 30,
  ),
  SettingDef(
    key: MetaPageKeys.subtitleTheme,
    category: SettingsCategory.video,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsSubtitleThemeTile,
    routeName: MetaPageKeys.subtitleTheme,
    sortOrder: 40,
  ),
  SettingDef(
    key: SettingKeys.videoThumbnailMethodsKey,
    category: SettingsCategory.video,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsVideoThumbnailMethods,
    editorKey: MetaEditorKeys.videoThumbnailMethods,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 50,
  ),
];

// Thumbnails

final List<SettingDef> _thumbnailsDefs = [
  SettingDef(
    key: MetaPageKeys.collectionActions,
    category: SettingsCategory.thumbnails,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsCollectionQuickActionsTile,
    routeName: MetaPageKeys.collectionActions,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 10,
  ),
  SettingDef(
    key: MetaPageKeys.thumbnailOverlay,
    category: SettingsCategory.thumbnails,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsThumbnailOverlayTile,
    routeName: MetaPageKeys.thumbnailOverlay,
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.collectionBurstPatternsKey,
    category: SettingsCategory.thumbnails,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsCollectionBurstPatternsTile,
    editorKey: MetaEditorKeys.burstPatterns,
    sortOrder: 30,
  ),
];

// Navigation

final List<SettingDef> _navigationDefs = [
  SettingDef(
    key: SettingKeys.homePageKey,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsHomeTile,
    editorKey: MetaEditorKeys.homePage,
    sortOrder: 10,
  ),
  SettingDef(
    key: SettingKeys.keepScreenOnKey,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.enumPick,
    title: (context) => context.l10n.settingsKeepScreenOnTile,
    reader: (settings) => settings.keepScreenOn,
    enumValues: KeepScreenOn.values,
    enumName: (context, value) => (value as KeepScreenOn).getName(context),
    dialogTitle: (context) => context.l10n.settingsKeepScreenOnDialogTitle,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 20,
  ),
  SettingDef(
    key: SettingKeys.mustBackTwiceToExitKey,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.toggle,
    title: (context) => context.l10n.settingsDoubleBackExit,
    reader: (settings) => settings.mustBackTwiceToExit,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 30,
  ),
  SettingDef(
    key: MetaPageKeys.navigationDrawer,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsNavigationDrawerTile,
    routeName: MetaPageKeys.navigationDrawer,
    sortOrder: 40,
  ),
  SettingDef(
    key: MetaPageKeys.bottomNavActions,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsNavigationBottomActionsTile,
    routeName: MetaPageKeys.bottomNavActions,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 50,
  ),
  SettingDef(
    key: MetaPageKeys.confirmationDialog,
    category: SettingsCategory.navigation,
    widgetKind: SettingWidgetKind.subPage,
    title: (context) => context.l10n.settingsConfirmationTile,
    routeName: MetaPageKeys.confirmationDialog,
    availabilityKey: DefVisibility.notTv,
    sortOrder: 60,
  ),
];

// Advanced

final List<SettingDef> _advancedDefs = [
  SettingDef(
    key: SettingsEngineGate.key,
    category: SettingsCategory.advanced,
    widgetKind: SettingWidgetKind.custom,
    title: (context) => context.l10n.settingsEngineTile,
    editorKey: MetaEditorKeys.settingsEngine,
    sortOrder: 10,
  ),
];
