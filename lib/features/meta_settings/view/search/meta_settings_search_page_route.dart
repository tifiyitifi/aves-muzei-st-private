import 'package:aves/features/meta_settings/view/search/meta_settings_search_delegate.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/search/route.dart';
import 'package:material_ui/material_ui.dart';

class MetaSettingsSearchPageRoute extends SearchPageRoute {
  new({
    required BuildContext context,
    super.background,
  }) : super(
          delegate: MetaSettingsSearchDelegate(
            searchFieldLabel: context.l10n.settingsSearchFieldLabel,
            searchFieldStyle: Themes.searchFieldStyle(context),
          ),
        );
}
