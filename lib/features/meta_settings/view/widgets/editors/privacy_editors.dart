import 'package:aves/app_flavor.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/bin_usage.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_sub_page_tile.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_switch_list_tile.dart';
import 'package:aves/model/device.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/text.dart';
import 'package:aves/widgets/common/action_mixins/permission_aware.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/privacy/permissions/permissions_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

/// Custom editor for the permissions entry (delegates to `PermissionsPage` and
/// shows a live permission status subtitle).
class PermissionsEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSubPageTile(
        title: def.title,
        subtitle: (context) => const PermissionsStatusSubtitle(),
        routeName: PermissionsPage.routeName,
        builder: (context) => const PermissionsPage(),
      );
}

/// Custom editor for the bin toggle: disabling it tears down trashed items.
class EnableBinEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSwitchListTile(
        selector: (context, settings) => settings.enableBin,
        onChanged: (value) => setBinUsage(context, value),
        title: def.title,
        subtitle: (context) => context.l10n.settingsEnableBinSubtitle,
      );
}

/// Custom editor for the auto-export toggle: enabling it asks for a SAF
/// directory, so it cannot go through the generic store write.
class AutoExportSettingsEditor extends StatelessWidget with PermissionAwareMixin {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSwitchListTile(
        selector: (context, settings) => settings.autoExportPath != null,
        onChanged: (value) async {
          if (value) {
            if (!await checkSystemFilePickerEnabled(context)) return;

            final dirPath = await storagePermissionService.requestSafAnyDirectoryAccess();
            if (dirPath == null) return;

            settings.autoExportPath = dirPath;
          } else {
            settings.autoExportPath = null;
          }
        },
        title: def.title,
        subtitle: (context) => settings.autoExportPath,
      );
}

/// Permission status indicator, copied from the upstream permissions tile so
/// the v2 surface never imports the upstream settings layer.
class PermissionsStatusSubtitle extends StatefulWidget {
  const new({super.key});

  @override
  State<PermissionsStatusSubtitle> createState() => _PermissionsStatusSubtitleState();
}

class _PermissionsStatusSubtitleState extends State<PermissionsStatusSubtitle> with WidgetsBindingObserver {
  late Future<bool> _isMediaManagementGrantedLoader;
  late Future<bool> _areNotificationsEnabledLoader;

  @override
  void initState() {
    super.initState();
    _initLoader();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initLoader() {
    _isMediaManagementGrantedLoader = deviceService.isMediaManagementGranted();
    _areNotificationsEnabledLoader = Permission.notification.status.then((v) => v == PermissionStatus.granted);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == .resumed) {
      _initLoader();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _areNotificationsEnabledLoader,
      builder: (context, notificationSnapshot) {
        final areNotificationsEnabled = notificationSnapshot.data ?? false;
        return FutureBuilder<bool>(
          future: _isMediaManagementGrantedLoader,
          builder: (context, mediaManagementSnapshot) {
            final isMediaManagementGranted = mediaManagementSnapshot.data ?? false;

            final permissions = <(IconData, bool)>[];
            permissions.add((AIcons.app, context.select<Settings, bool>((s) => s.isInstalledAppAccessAllowed)));
            if (context.select<AppFlavor, bool>((v) => v.canEnableErrorReporting)) {
              permissions.add((AIcons.bugReport, context.select<Settings, bool>((s) => s.isErrorReportingAllowed)));
            }
            permissions.add((AIcons.notifications, areNotificationsEnabled));
            if (!settings.useTvLayout && device.canRequestMediaManagementPermission) {
              permissions.add((AIcons.allCollection, isMediaManagementGranted));
            }

            final textSpans =
                (permissions
                        .expand((v) {
                          final (icon, enabled) = v;
                          return [
                            const TextSpan(text: AText.separator),
                            WidgetSpan(
                              child: Opacity(
                                opacity: enabled ? 1 : MetaSwitchListTile.disabledOpacity,
                                child: Icon(icon),
                              ),
                              alignment: .middle,
                            ),
                          ];
                        })
                        .skip(1))
                    .toList();

            final theme = Theme.of(context);
            final subtitleTextStyle =
                theme.listTileTheme.subtitleTextStyle ??
                theme.textTheme.bodyMedium!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                );
            return IconTheme.merge(
              data: IconThemeData(
                size: 18,
                color: subtitleTextStyle.color,
              ),
              child: Text.rich(
                TextSpan(
                  // text directionality does not affect children span order,
                  // so we manually reverse them when necessary
                  children: context.isRtl ? textSpans.reversed.toList() : textSpans,
                ),
                style: subtitleTextStyle,
              ),
            );
          },
        );
      },
    );
  }
}
