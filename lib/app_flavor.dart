enum AppFlavor { play, izzy, libre, custom }

extension ExtraAppFlavor on AppFlavor {
  bool get canEnableErrorReporting {
    switch (this) {
      case .play:
        return true;
      case .izzy:
      case .libre:
      case .custom:
        return false;
    }
  }

  bool get hasMapStyleDefault {
    switch (this) {
      case .play:
      case .custom:
        return true;
      case .izzy:
      case .libre:
        return false;
    }
  }
}
