enum AppMode {
  initialization,
  main,
  pickCollectionFiltersExternal,
  pickSingleMediaExternal,
  pickMultipleMediaExternal,
  pickFilteredMediaInternal,
  pickUnfilteredMediaInternal,
  pickFilterInternal,
  previewMap,
  screenSaver,
  setWallpaper,
  slideshow,
  view,
  edit,
}

extension ExtraAppMode on AppMode {
  bool get canNavigate => <AppMode>{
    .main,
    .pickCollectionFiltersExternal,
    .pickSingleMediaExternal,
    .pickMultipleMediaExternal,
  }.contains(this);

  bool get canEditEntry => <AppMode>{
    .main,
    .view,
  }.contains(this);

  bool get canSelectMedia => <AppMode>{
    .main,
    .pickMultipleMediaExternal,
  }.contains(this);

  bool get canSelectFilter => <AppMode>{
    .main,
    .pickCollectionFiltersExternal,
  }.contains(this);

  bool get canCreateFilter => <AppMode>{
    .main,
    .pickFilterInternal,
  }.contains(this);

  bool get isPickingMedia => <AppMode>{
    .pickSingleMediaExternal,
    .pickMultipleMediaExternal,
    .pickFilteredMediaInternal,
    .pickUnfilteredMediaInternal,
  }.contains(this);

  /// Whether the app is showing a view only to return a choice to its caller.
  ///
  /// Such a view must never be replaced by the browse-only browser: nothing in it
  /// is selectable and it has no way to confirm, so a pick that arrives during
  /// the first import would have no completion path at all.
  bool get isPicking => <AppMode>{
    .pickCollectionFiltersExternal,
    .pickSingleMediaExternal,
    .pickMultipleMediaExternal,
    .pickFilteredMediaInternal,
    .pickUnfilteredMediaInternal,
    .pickFilterInternal,
  }.contains(this);
}
