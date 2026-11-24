# Visible range — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-visible-range-rules.ps1` resolves every `F:`
token.

## Model

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| MOD-1 | Empty range | WHEN nothing is active, THE SYSTEM SHALL restrict nothing | a fresh install browses the whole library | `F:visible_range_model_test#an empty range restricts nothing` |
| MOD-2 | Switched-off source | WHEN a source is switched off, THE SYSTEM SHALL keep its filters but not restrict | a group can park a source without losing it | `F:visible_range_model_test#a switched-off source does not restrict and keeps its filters` |
| MOD-3 | Intersect-first | WHEN the order is intersect-first, THE SYSTEM SHALL resolve `sources AND restrictions, then OR supplements` | this is the inherited scenario semantics | `F:visible_range_model_test#intersect-first combines sources AND restrictions, then OR supplements` |
| MOD-4 | Union-first | WHEN the order is union-first, THE SYSTEM SHALL resolve `sources OR supplements, then AND restrictions` | the second inherited order | `F:visible_range_model_test#union-first ORs supplements first, then ANDs restrictions` |
| MOD-5 | Unrestricted source | WHEN the sources are unrestricted, THE SYSTEM SHALL make the union step a no-op in both orders | otherwise a supplement would silently restrict | `F:visible_range_model_test#an unrestricted source is a no-op in both orders` |
| MOD-6 | Supplements alone | WHEN only supplements are active, THE SYSTEM SHALL not restrict browsing | a supplement adds entries, it cannot remove them | `F:visible_range_model_test#a supplement alone never restricts browsing` |
| MOD-7 | Inactive rules | WHEN a rule is switched off, THE SYSTEM SHALL ignore its filters | the chip toggle must change the result | `F:visible_range_model_test#inactive rules do not contribute` |
| MOD-8 | Restricted predicate | WHEN `isRestricted` is evaluated, THE SYSTEM SHALL consider only the sources and the active restrictions | supplements never narrow | `F:visible_range_model_test#restricted is decided by the sources and restrictions only` |
| MOD-9 | Rule conjunction | WHEN a rule holds several filters, THE SYSTEM SHALL AND them | one rule is one condition | `F:visible_range_model_test#every rule filter is AND-ed inside its rule` |
| MOD-10 | Source union | WHEN several sources are active, THE SYSTEM SHALL OR the rules, each narrowed by its own filters | a group's source section is a union of conditions | `F:visible_range_model_test#several sources are a union, not a narrower conjunction` |
| MOD-11 | Outside last | WHEN an outside pool exists, THE SYSTEM SHALL apply `(group AND outside restrictions) OR outside supplements` after the group | the shared layer is the final word | `F:visible_range_model_test#applies last: group AND outside restrictions, then outside supplements` |
| MOD-12 | Outside supplement no-op | WHEN a group is unrestricted, THE SYSTEM SHALL let an outside supplement restrict nothing | a supplement cannot narrow | `F:visible_range_model_test#an outside supplement cannot restrict an otherwise unrestricted group` |
| MOD-13 | Outside restriction | WHEN only an outside restriction exists, THE SYSTEM SHALL narrow with it | the shared layer applies to every group | `F:visible_range_model_test#an outside restriction narrows even when the group has no source` |
| MOD-14 | Outside roles | WHEN the outside pool is edited, THE SYSTEM SHALL accept restrictions and supplements only | a shared source would widen every group | `F:visible_range_model_test#the outside pool has no source role` |
| MOD-15 | Fingerprint | WHEN a filter set is fingerprinted, THE SYSTEM SHALL ignore order and distinguish different sets | dedupe of rules relies on it | `F:visible_range_model_test#is order independent and distinguishes different sets` |
| MOD-16 | Source target | WHEN a target stands for a source rule, THE SYSTEM SHALL map it to the source section | the source section is the old base section | `F:visible_range_model_test#a source rule target maps to the source section` |
| MOD-17 | Legacy base target | WHEN a target has no rule id, THE SYSTEM SHALL address the range's legacy base | write-back must find the migrated source | `F:visible_range_model_test#a legacy base target is addressed by its range` |
| MOD-18 | Stable usage id | WHEN the same target is recorded twice, THE SYSTEM SHALL map it to one usage id | applied targets must not duplicate | `F:visible_range_model_test#the same target maps to one stable usage id` |

## Pin split

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SPL-1 | Album source | WHEN a media set holds one album, THE SYSTEM SHALL write one source | the album defines the media pool | `F:visible_range_pin_split_test#one album becomes one source` |
| SPL-2 | Conjunctive albums | WHEN a media set holds several albums, THE SYSTEM SHALL keep them one source | the media set ANDs them | `F:visible_range_pin_split_test#two albums stay one conjunctive source, not a union` |
| SPL-3 | Source-only union | WHEN the source part is a union, THE SYSTEM SHALL write one source per member | the union is already the group's OR | `F:visible_range_pin_split_test#a source-only union becomes one source per member` |
| SPL-4 | Source and narrowing | WHEN a media set holds an album and narrowing filters, THE SYSTEM SHALL write a source and the restrictions | this keeps the result equivalent | `F:visible_range_pin_split_test#a source plus narrowing filters becomes one source and restrictions` |
| SPL-5 | Reversed filter | WHEN a filter is reversed, THE SYSTEM SHALL keep it a restriction | a positive source would invert it | `F:visible_range_pin_split_test#a reversed filter never becomes a source` |
| SPL-6 | Mixed union | WHEN a union mixes a source and a narrowing filter, THE SYSTEM SHALL keep it one restriction | a positive source would change its meaning | `F:visible_range_pin_split_test#a mixed union stays one restriction` |
| SPL-7 | Forced source | WHEN the user forces the source role, THE SYSTEM SHALL keep the whole set in one source | forcing is an explicit semantic change | `F:visible_range_pin_split_test#forcing the source role keeps the whole set conjunctive` |
| SPL-8 | Forced restriction | WHEN the user forces restrictions, THE SYSTEM SHALL write one rule per filter | each filter stays independently editable | `F:visible_range_pin_split_test#forcing restrictions puts every filter in its own rule` |
| SPL-9 | Forced supplement | WHEN the user forces supplements, THE SYSTEM SHALL write one OR rule per filter | supplements are OR-ed | `F:visible_range_pin_split_test#forcing supplements puts every filter in its own OR rule` |
| SPL-10 | Source scope | WHEN a filter is classified, THE SYSTEM SHALL treat albums and paths as sources only | other filters narrow | `F:visible_range_pin_split_test#albums and paths are sources, other filters are not` |
| SPL-11 | Union scope | WHEN a union is classified, THE SYSTEM SHALL require every member to be a source | a mixed union is not a source | `F:visible_range_pin_split_test#a union of sources is a source, a mixed union is not` |

## Candidates and summary

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CND-1 | Source section | WHEN the source section is built, THE SYSTEM SHALL start with the unrestricted tile | clearing the sources must stay one tap away | `F:visible_range_candidate_test#an empty group starts with the unrestricted tile` |
| CND-2 | Selected source | WHEN a source exists, THE SYSTEM SHALL show the unrestricted tile as unselected and the source as selected | the source section is a union of conditions | `F:visible_range_candidate_test#a source condition becomes the second tile and deselects unrestricted` |
| CND-3 | Parallel sources | WHEN several sources exist, THE SYSTEM SHALL list them as parallel tiles | each condition is independently switchable | `F:visible_range_candidate_test#several sources are parallel tiles` |
| CND-4 | Rule order | WHEN rules are listed, THE SYSTEM SHALL group by kind and put defaults first | the page's stable order | `F:visible_range_candidate_test#rules are grouped by kind and defaults come first` |
| CND-5 | Labels | WHEN a candidate is a built-in, THE SYSTEM SHALL use its key; a rename SHALL be plain text | built-ins are localized, user text is not | `F:visible_range_candidate_test#a built-in label is a key and a rename is plain text`; `F:visible_range_candidate_test#a preset name is localized only for built-ins` |
| CND-6 | Shared stats key | WHEN two candidates share filters, THE SYSTEM SHALL share one stats key | one query per distinct set | `F:visible_range_candidate_test#candidates with the same filters share a stats key` |
| CND-7 | Unrestricted tile | WHEN the unrestricted tile is built, THE SYSTEM SHALL carry no filters | it means 「不限」 | `F:visible_range_candidate_test#the unrestricted tile is const and never carries filters` |
| CND-8 | Active section | WHEN the active section is built, THE SYSTEM SHALL repeat the sources and the enabled rules | the page must describe what is in force | `F:visible_range_candidate_test#the active section repeats the result, the sources and the enabled rules`; `F:visible_range_candidate_test#the active section omits an unrestricted source` |
| CND-9 | Filter conjunction | WHEN a candidate is tested, THE SYSTEM SHALL test the conjunction of its filters | matching mirrors the SQL path | `F:visible_range_candidate_filter_test#a candidate filter tests the conjunction of its filters` |
| CND-10 | Unrestricted match | WHEN a candidate has no filters, THE SYSTEM SHALL match everything | an unrestricted candidate is not a filter | `F:visible_range_candidate_filter_test#an unrestricted candidate matches everything` |
| CND-11 | Fallback label | WHEN a candidate has no explicit label, THE SYSTEM SHALL use its filter labels | user rules need a name without prompting | `F:visible_range_candidate_filter_test#the universal label falls back to the filter labels` |
| CND-12 | Reversed filter | WHEN a filter is reversed, THE SYSTEM SHALL keep the reverse semantics | summary exclusion uses the complement | `F:visible_range_candidate_filter_test#a reversed filter keeps its reverse semantics` |
| SUM-1 | Source named | WHEN a source is named like its group, THE SYSTEM SHALL not repeat it | the summary would read twice | `F:visible_range_summary_test#a base named like its group is not repeated` |
| SUM-2 | Restrictions counted | WHEN active restrictions exist, THE SYSTEM SHALL count them | the summary states how many narrowers apply | `F:visible_range_summary_test#active restrictions are counted` |
| SUM-3 | Supplements ignored | WHEN supplements are active, THE SYSTEM SHALL not count them as narrowers | they widen | `F:visible_range_summary_test#supplements are never counted` |
| SUM-4 | Renamed group | WHEN a group is renamed, THE SYSTEM SHALL name its range from the group | the user sees their own name | `F:visible_range_summary_test#a renamed group still names its range` |
| SUM-5 | Unrestricted source | WHEN the source is unrestricted, THE SYSTEM SHALL not name it | there is nothing to name | `F:visible_range_summary_test#an unrestricted base is not named` |
| SUM-6 | Unnamed source | WHEN the source has no name, THE SYSTEM SHALL fall back to its filters | a saved range still needs a label | `F:visible_range_summary_test#an unnamed base falls back to its filters` |
| SUM-7 | Group 0 | WHEN the wallpaper page shows group 0, THE SYSTEM SHALL report no range description | group 0 means the gallery range alone | `F:visible_range_summary_test#group 0 has no range to describe` |

## Store

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STO-1 | Aggregate round trip | WHEN a range is saved, THE SYSTEM SHALL store the range and its rules together | a reader never sees half a range | `F:visible_range_store_test#round-trips a range and its rules` |
| STO-2 | Group listing | WHEN groups are listed, THE SYSTEM SHALL return only groups in display order | the outside pool is not a browsable group | `F:visible_range_store_test#loadGroups lists only groups in display order` |
| STO-3 | Permissions | WHEN a range is locked, THE SYSTEM SHALL store the edited permissions | the lock outlives the session | `F:visible_range_store_test#stores edited permissions` |
| STO-4 | Unlocked clears | WHEN a range is unlocked, THE SYSTEM SHALL drop stale permissions | an unlocked range must not carry a frozen set | `F:visible_range_store_test#an unlocked range drops stale permissions` |
| STO-5 | Replace rules | WHEN a rule set is replaced, THE SYSTEM SHALL replace the whole set | a partial update leaves orphans | `F:visible_range_store_test#replaceRules replaces the whole set` |
| STO-6 | Delete range | WHEN a range is deleted, THE SYSTEM SHALL delete its rules and applied targets | orphans would point at a missing range | `F:visible_range_store_test#deleting a range clears its rules and applied targets` |
| STO-7 | Presets and state | WHEN presets and view state are written, THE SYSTEM SHALL read them back | the page must survive a restart | `F:visible_range_store_test#presets and state round-trip` |
| STO-8 | Applied targets | WHEN an applied target is recorded, THE SYSTEM SHALL keep it tied to its rule | the pin sheet writes back over it | `F:visible_range_store_test#applied targets round-trip and follow their rule` |

## Defaults

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| DEF-1 | Parse | WHEN the preset document is parsed, THE SYSTEM SHALL skip malformed entries | one bad entry must not drop the bundle | `F:default_presets_test#parses valid presets and skips malformed entries` |
| DEF-2 | Missing list | WHEN the document has no preset list, THE SYSTEM SHALL yield nothing | a broken asset must not throw | `F:default_presets_test#a document without a preset list yields nothing` |
| DEF-3 | Standard directory | WHEN a preset names a standard directory, THE SYSTEM SHALL resolve it instead of hardcoding a path | the path differs per device | `F:default_presets_test#a standard directory is resolved instead of hardcoded` |
| DEF-4 | Unresolvable directory | WHEN a standard directory cannot be resolved, THE SYSTEM SHALL skip that candidate | an unusable candidate must not appear | `F:default_presets_test#an unresolvable standard directory skips the candidate` |
| DEF-5 | Group order | WHEN the bundle is shipped, THE SYSTEM SHALL keep the curated group order | the page reads top to bottom | `F:default_presets_test#the shipped bundle keeps the curated group order` |
| DEF-6 | Time presets | WHEN the bundle is shipped, THE SYSTEM SHALL offer the curated time presets only | 6h, 12h and 7d are the chosen set | `F:default_presets_test#the shipped time presets are 6h, 12h and 7d only` |
| DEF-7 | Unique ids | WHEN the bundle is shipped, THE SYSTEM SHALL have unique ids, declared sections and decodable filters | a duplicate id overwrites a tile | `F:default_presets_test#the shipped bundle parses with unique ids, sections and decodable filters` |

## Controller

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CTL-1 | First start | WHEN the controller starts, THE SYSTEM SHALL browse the unrestricted default with the built-in groups seeded once | a fresh install must not restrict anything | `F:visible_range_controller_test#starts on the unrestricted default with the built-in groups seeded once` |
| CTL-2 | Built-in group | WHEN a built-in definition is seeded, THE SYSTEM SHALL create a group with one source | the old exclusive scenarios become groups | `F:visible_range_controller_test#a built-in group carries one source condition` |
| CTL-3 | Select source | WHEN a source is selected, THE SYSTEM SHALL persist it and resolve it | the choice must survive a restart | `F:visible_range_controller_test#selecting a source persists and resolves` |
| CTL-4 | Clear sources | WHEN the sources are cleared, THE SYSTEM SHALL return to unrestricted | clearing is one action | `F:visible_range_controller_test#clearing the sources returns to unrestricted` |
| CTL-5 | Switch group | WHEN another group is made current, THE SYSTEM SHALL re-resolve browsing from it | groups are the exclusive containers | `F:visible_range_controller_test#switching groups changes the browsing filter` |
| CTL-6 | Rule edits | WHEN a rule is added, toggled or deleted, THE SYSTEM SHALL persist the change | rule state is user data | `F:visible_range_controller_test#rules persist, toggle and delete` |
| CTL-7 | Empty rule | WHEN an empty rule is added, THE SYSTEM SHALL ignore it | an empty rule would show a blank tile | `F:visible_range_controller_test#adding an empty rule is a no-op` |
| CTL-8 | Outside roles | WHEN a source is added to the outside pool, THE SYSTEM SHALL ignore it | the outside pool has no source role | `F:visible_range_controller_test#the outside pool has no source role` |
| CTL-9 | Locked domain | WHEN the gallery is locked, THE SYSTEM SHALL reject edits and group switching | the lock freezes the whole gallery configuration | `F:visible_range_controller_test#a locked gallery freezes group switching and edits` |
| CTL-10 | Quick lock | WHEN the quick lock is used, THE SYSTEM SHALL reuse the last permissions preset | the user should not re-choose | `F:visible_range_controller_test#quick lock reuses the last permissions preset` |
| CTL-11 | View preferences | WHEN the active style changes, THE SYSTEM SHALL persist it across a restart | it is a view preference | `F:visible_range_controller_test#view preferences persist across a restart` |
| CTL-12 | Default style | WHEN no style is stored, THE SYSTEM SHALL use the section style | the default presentation | `F:visible_range_controller_test#the active conditions default to the section style` |
| CTL-13 | Injection memory | WHEN the pin injection mode is remembered, THE SYSTEM SHALL read it back after a restart | the user may not want to choose every time | `F:visible_range_controller_test#the pinned injection mode is remembered only when asked` |
| CTL-14 | Defaults bump | WHEN the defaults version is bumped, THE SYSTEM SHALL add missing groups and keep user work | installs must converge on the bundle without deleting user groups | `F:visible_range_controller_test#a defaults bump adds missing groups and keeps user work` |
| CTL-15 | Re-add defaults | WHEN defaults are re-added, THE SYSTEM SHALL skip existing groups | re-adding must not duplicate | `F:visible_range_controller_test#re-adding defaults skips groups that already exist` |
| CTL-16 | Inactive defaults | WHEN restriction and supplement defaults are seeded, THE SYSTEM SHALL seed them switched off in the outside pool | they are candidates, not decisions | `F:visible_range_controller_test#restriction and supplement defaults are seeded switched off in the outside pool` |
| CTL-17 | Restore default | WHEN a deleted outside default is restored, THE SYSTEM SHALL restore it switched off | restoring must not change the result | `F:visible_range_controller_test#a deleted outside default is restored switched off` |

## Apply and write-back

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| APL-1 | Remember targets | WHEN candidates are applied, THE SYSTEM SHALL remember them deduped by id | the pin sheet writes back over the current view | `F:visible_range_apply_test#taking a rule and a base out remembers both, deduped by id` |
| APL-2 | Deleted rule | WHEN a rule is deleted from its range, THE SYSTEM SHALL drop it from the applied list | a dangling target cannot be written back | `F:visible_range_apply_test#a rule deleted from its range disappears from the list` |
| APL-3 | Write-back scope | WHEN the current filters are written back, THE SYSTEM SHALL overwrite only the selected rule and source | the rest of the range is not the view | `F:visible_range_apply_test#write-back overwrites the selected rule and base only` |
| APL-4 | Locked target | WHEN the selected target is locked, THE SYSTEM SHALL skip it and count it | a locked range must not change | `F:visible_range_apply_test#a locked range is skipped and counted` |
| APL-5 | Empty selection | WHEN nothing is selected, THE SYSTEM SHALL write nothing | an empty view is not a range | `F:visible_range_apply_test#an empty selection writes nothing` |
| APL-6 | Target order | WHEN the pin sheet lists targets, THE SYSTEM SHALL show the gallery group, the outside roles, then the wallpaper groups | the user sees every destination | `F:visible_range_apply_test#the pin sheet lists the gallery group, the outside roles, then the groups` |
| APL-7 | One visit | WHEN a pin request names the gallery and a group, THE SYSTEM SHALL write both in one visit | one confirmation, two targets | `F:visible_range_apply_test#a pin request writes the gallery and the group in one visit` |
| APL-8 | Locked group | WHEN a group target is locked, THE SYSTEM SHALL skip it without failing | the gallery still applies | `F:visible_range_apply_test#a locked group target is skipped, not failed` |
| APL-9 | Group source | WHEN a source is pinned to a group, THE SYSTEM SHALL store it on the range, not in the preset catalog | the preset catalog is global | `F:visible_range_apply_test#a source pinned to a group is stored on the range, not in the preset catalog` |
| APL-10 | Group rule | WHEN a group rule is written back, THE SYSTEM SHALL go through the group's source | the group range owns its rules | `F:visible_range_apply_test#a group rule can be taken out and written back through the source` |
| PIN-1 | Targets | WHEN the pin sheet is built, THE SYSTEM SHALL offer the gallery group, the two outside roles and every registered wallpaper group | every writable place must be reachable from the sheet | `F:visible_range_pin_test#the group plus the two outside roles are the targets without a registered source` |
| PIN-2 | First injection | WHEN filters are pinned into an empty group, THE SYSTEM SHALL enable the new conditions | the first pin is the group's definition | `F:visible_range_pin_test#pinning a media type into an empty group enables the new condition` |
| PIN-3 | Split | WHEN a media set is pinned, THE SYSTEM SHALL split the album into a source and the rest into a restriction | the result must match the media set | `F:visible_range_pin_test#an album becomes a source, the rest becomes a restriction` |
| PIN-4 | Later injection | WHEN filters are pinned into a non-empty group, THE SYSTEM SHALL park the new conditions and keep them on re-pin | a later pin must not silently change the result | `F:visible_range_pin_test#a second pin into a non-empty group is parked and keeps its state on re-pin` |
| PIN-5 | Injection mode | WHEN the injection mode is forced, THE SYSTEM SHALL enable or park every new condition | the user may override the heuristic | `F:visible_range_pin_test#the injection mode can force enabling or parking` |
| PIN-6 | Replace | WHEN the write mode is replace, THE SYSTEM SHALL drop the conditions already in the group | a group is one definition | `F:visible_range_pin_test#replace mode drops the conditions already in the group` |
| PIN-7 | Outside restriction | WHEN the outside restriction target is pinned, THE SYSTEM SHALL write one restriction per filter | the outside pool has no attributes | `F:visible_range_pin_test#the outside restriction target puts every filter in its own restriction` |
| PIN-8 | Outside supplement | WHEN the outside supplement target is pinned, THE SYSTEM SHALL write one supplement per filter | supplements are OR-ed | `F:visible_range_pin_test#the outside supplement target puts every filter in its own supplement` |
| PIN-9 | Forced role | WHEN a role is forced, THE SYSTEM SHALL override the automatic split | forcing is explicit | `F:visible_range_pin_test#a forced role overrides the automatic split` |
| PIN-10 | Unknown target | WHEN a target is unknown, THE SYSTEM SHALL skip it | a stale target must not fail the request | `F:visible_range_pin_test#unknown target ids are skipped` |
| PIN-11 | Locked gallery | WHEN the gallery is locked, THE SYSTEM SHALL skip its targets instead of failing | a locked target is not an error | `F:visible_range_pin_test#a locked gallery is skipped instead of failing the request` |
| PIN-12 | Survives restart | WHEN pinned conditions are written, THE SYSTEM SHALL read them back after a restart | the user's notes are data | `F:visible_range_pin_test#pinned conditions survive a restart` |
| PIN-13 | Empty request | WHEN a pin request is empty, THE SYSTEM SHALL do nothing | no dialog, no write | `F:visible_range_pin_test#an empty request is a no-op` |

## Gate, lock and navigation

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GAT-1 | Intersect match | WHEN the gate applies an intersect-first range, THE SYSTEM SHALL match the in-memory result | all three browsing paths must agree | `F:visible_range_gate_test#intersect-first matches the in-memory result` |
| GAT-2 | Union match | WHEN the gate applies a union-first range, THE SYSTEM SHALL match the in-memory result | the second order must agree too | `F:visible_range_gate_test#union-first matches the in-memory result` |
| GAT-3 | Summary exclusion | WHEN a summary excludes the range, THE SYSTEM SHALL keep only entries inside it | counts must agree with the grid | `F:visible_range_gate_test#the summary exclusion keeps only entries inside the range` |
| GAT-4 | Apply and clear | WHEN the range is set or cleared, THE SYSTEM SHALL apply or clear it | the gate is the one seam | `F:visible_range_gate_test#the gate applies and clears the range` |
| GAT-5 | Wallpaper overlay | WHEN a group scope is published, THE SYSTEM SHALL join it to the gallery range and allow suspending the gallery | the two ranges are independent | `F:visible_range_gate_test#the wallpaper overlay joins the gallery range and can suspend it` |
| GAT-6 | Change only | WHEN the overlay value does not change, THE SYSTEM SHALL not notify | a re-publish must not invalidate every cache | `F:visible_range_gate_test#the overlay notifies only when its value changes` |
| GAT-7 | Suspension owner | WHEN the gallery range is suspended, THE SYSTEM SHALL keep that choice on the overlay | every surface over the page flips the same switch | `F:visible_range_gate_test#suspending the gallery range belongs to the overlay` |
| GAT-8 | Closing the page | WHEN the wallpaper page closes, THE SYSTEM SHALL drop the group scope | browsing returns to the gallery range | `F:visible_range_gate_test#closing the wallpaper page drops the group scope` |
| GAT-9 | Deferred release | WHEN a release runs during a route transition, THE SYSTEM SHALL defer the clear and drop only the scope it owns | notifying inside the tree throws | `F:visible_range_gate_test#is deferred and only clears the scope it owns` |
| GAT-10 | Newer page | WHEN a newer page owns the scope, THE SYSTEM SHALL keep it despite an equal value | value equality cannot identify the owner | `F:visible_range_gate_test#leaves the scope a newer page claimed, even with an equal value` |
| GAT-11 | No owner | WHEN a release has no owner, THE SYSTEM SHALL do nothing | closing twice is not an error | `F:visible_range_gate_test#releasing nothing is a no-op` |
| LCK-1 | Unlocked | WHEN the range is unlocked, THE SYSTEM SHALL withhold nothing | callers need no separate check | `F:visible_range_locks_test#an unlocked range withholds nothing` |
| LCK-2 | Read-only | WHEN the lock is read-only, THE SYSTEM SHALL withhold every edit but sharing | the product default | `F:visible_range_locks_test#a read-only lock withholds every edit but sharing` |
| LCK-3 | Manageable | WHEN the lock is manageable, THE SYSTEM SHALL allow the operations it names | it is the middle preset | `F:visible_range_locks_test#a manageable lock allows the operations it names` |
| LCK-4 | Unlock | WHEN the range is unlocked, THE SYSTEM SHALL restore every operation | unlocking is lossless | `F:visible_range_locks_test#unlocking restores every operation` |
| LCK-5 | Entry-set mapping | WHEN an entry-set action is checked, THE SYSTEM SHALL map it to the permission it needs | one action, one permission | `F:visible_range_locks_test#maps entry-set actions to the permission each one needs` |
| LCK-6 | Viewer mapping | WHEN a viewer or album-grid action is checked, THE SYSTEM SHALL map it to its permission | the same rule outside the grid | `F:visible_range_locks_test#maps viewer and album-grid actions to the permission each one needs` |
| SCO-1 | Drop overlay | WHEN the scope is released, THE SYSTEM SHALL drop the overlay and release the owner | the page's session owns it | `F:visible_range_scope_test#drops the overlay and releases the owner` |
| SCO-2 | Group 0 | WHEN group 0 is published, THE SYSTEM SHALL fall back to the gallery range | group 0 means no group scope | `F:visible_range_scope_test#publishing group 0 falls back to the gallery range` |
| SCO-3 | Suspend needs group | WHEN there is no group scope, THE SYSTEM SHALL refuse to suspend the gallery range | there is nothing to browse instead | `F:visible_range_scope_test#suspending the gallery range needs a group scope` |
| NAV-1 | Append destination | WHEN the range destination is offered, THE SYSTEM SHALL append it at the far right | it is a navigation item | `F:visible_range_nav_test#appends the destination at the far right` |
| NAV-2 | No duplicate | WHEN the destination is already present, THE SYSTEM SHALL not add it twice | one entry per item | `F:visible_range_nav_test#does not duplicate a destination the user already added` |
| NAV-3 | Hidden surface | WHEN the surface hides the destination, THE SYSTEM SHALL leave the list untouched | hiding is not removing | `F:visible_range_nav_test#leaves the list untouched when the surface hides the destination` |
| NAV-4 | Immutable input | WHEN the destination is appended, THE SYSTEM SHALL not mutate the input list | callers reuse the settings value | `F:visible_range_nav_test#does not mutate the input list` |
| NAV-5 | Shared entry | WHEN the destination is shared with another page, THE SYSTEM SHALL keep the shield | the old scenario entry keeps its semantics | `F:visible_range_nav_test#the destination keeps the old scenario shield` |
| DST-1 | Shared mode | WHEN the shared destination is used, THE SYSTEM SHALL follow the stored sub-page | one navigation entry, two pages | `F:visible_range_destination_test#the shared mode follows the stored sub-page` |
| DST-2 | Separate entry | WHEN the destination has its own entry, THE SYSTEM SHALL show the range page | the entry names the page | `F:visible_range_destination_test#a separate entry always shows the range page` |

## Views and migration

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| UI-1 | Target grid columns | WHEN the target grid is laid out, THE SYSTEM SHALL adapt the column count to the width | phones and tablets share the sheet | `F:visible_range_target_grid_test#adapts the column count to the width` |
| UI-2 | Minimum column | WHEN the width is tiny, THE SYSTEM SHALL never drop below one column | a zero-column grid shows nothing | `F:visible_range_target_grid_test#never drops below one column` |
| UI-3 | Target toggling | WHEN a target is unlocked, THE SYSTEM SHALL let it be toggled | the sheet selects write-back targets | `F:visible_range_target_grid_test#renders the gallery and the groups and toggles unlocked targets` |
| UI-4 | Locked target | WHEN a target is locked, THE SYSTEM SHALL not let it be selected | a locked range must not change | `F:visible_range_target_grid_test#locked targets are not selectable` |
| UI-5 | Header count | WHEN a section header counts its choices, THE SYSTEM SHALL advertise the displayed count | the header states what is in force | `F:visible_range_section_key_test#the base header advertises its displayed choice count`; `F:visible_range_section_key_test#rule headers show active over total` |
| UI-6 | Header style | WHEN a header is rendered, THE SYSTEM SHALL keep it a bare group name without the small-caps styling unless it has a count | the page style is shared with the collection | `F:visible_range_section_key_test#headers drop the small-caps styling`; `F:visible_range_section_key_test#a header without a count stays a bare group name` |
| UI-7 | Tile selection | WHEN a tile is selected, THE SYSTEM SHALL draw its own badge, including outside selection mode | the grid is not the collection | `F:visible_range_tile_test#renders without a page Selection provider`; `F:visible_range_tile_test#draws its own selection badge`; `F:visible_range_tile_test#a tile that is not selected shows the hollow mark while selecting`; `F:visible_range_tile_test#no mark is drawn outside selection mode` |
| MIG-1 | Range tables | WHEN a v4 database upgrades, THE SYSTEM SHALL create the visible-range tables | the feature cannot store a range without them | `F:migration_v5_test#a v4 database upgrades with the visible-range tables`; `F:migration_v5_test#a fresh database creates the visible-range tables too` |
| MIG-2 | Descriptions | WHEN a v5 database upgrades, THE SYSTEM SHALL add empty descriptions | the column is part of the rule model | `F:migration_v6_test#a v5 database upgrades to v6 with empty descriptions`; `F:migration_v6_test#a fresh database has the description columns` |
| MIG-3 | Base activation | WHEN a v8 database upgrades, THE SYSTEM SHALL add the base activation flag as active | a group base can be switched off | `F:migration_v9_test#a v8 database gains the base activation flag as active`; `F:migration_v9_test#a fresh database has the legacy column and a group round-trips` |
| MIG-4 | Group shape | WHEN a v18 database upgrades, THE SYSTEM SHALL add the group kind, name and position and keep the legacy base columns for a rollback | the migration must be reversible by an older build | `F:migration_v19_test#upgrades to the visibility-group shape` |
| MIG-5 | Base to source | WHEN a v18 database upgrades, THE SYSTEM SHALL turn each base into a `source` condition and keep its rules and surface marks | the migration must not lose a wallpaper pool | `F:migration_v19_test#a wallpaper base becomes a source condition and keeps its rules` |
| MIG-6 | Gallery reset | WHEN a v19 database upgrades, THE SYSTEM SHALL reset the pre-release gallery scope and keep the wallpaper pool | group 0 is the 「Unrestricted」 sentinel and cannot carry conditions | `F:migration_v20_test#resets the gallery scope and keeps the wallpaper pool`; `F:migration_v19_test#the gallery scope is reset by v20` |

## The gallery page

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| PAGE-1 | Page order | WHEN the gallery page is built, THE SYSTEM SHALL list the groups, then the outside restrictions, then the outside supplements | the page reads in evaluation order | `F:visible_range_page_sections_test#the groups section starts with the sentinel and ends with the add tile` |
| PAGE-2 | Group tile | WHEN a group tile is built, THE SYSTEM SHALL show the group's browsed result | switching to it is what the tile promises | `F:visible_range_page_sections_test#a group tile carries the group joined with the outside pool` |
| PAGE-3 | Outside always | WHEN the outside pool is empty, THE SYSTEM SHALL still show both outside sections | the shared layer must stay visible | `F:visible_range_page_sections_test#the outside sections are always present and read restrictions first` |
| PAGE-4 | Outside headers | WHEN an outside section is titled, THE SYSTEM SHALL name the shared pool, not the group's own rules | the two layers are edited in different places | `F:visible_range_section_key_test#outside headers name the shared pool` |
| PAGE-5 | Groups header | WHEN the groups section is titled, THE SYSTEM SHALL name the group list and count it | the section is the exclusive choice | `F:visible_range_section_key_test#the groups header names the sentinel list` |
| PAGE-6 | Group dim | WHEN a group tile is not the current group, THE SYSTEM SHALL dim it like a switched-off condition | the exclusive choice should read at a glance | `F:visible_range_tile_test#a group that is not current is dimmed like a switched-off condition`; `F:visible_range_tile_test#the current group is drawn at full opacity` |

## Group 0 and the editor

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GRP-1 | Sentinel empty | WHEN group 0 is edited, THE SYSTEM SHALL accept no condition | group 0 means 「Unrestricted」 | `F:visible_range_controller_test#group 0 is the unrestricted sentinel and takes no conditions` |
| GRP-2 | Sentinel target | WHEN the save sheet lists targets, THE SYSTEM SHALL not offer group 0 | a sentinel must stay empty | `F:visible_range_controller_test#group 0 is never a save target` |
| GRP-3 | Sentinel lifecycle | WHEN group 0 is renamed, deleted or moved, THE SYSTEM SHALL refuse and keep it first | it is the fallback browsing state | `F:visible_range_controller_test#group 0 cannot be renamed, deleted or moved out of first place` |
| GRP-4 | Numbering | WHEN a group is numbered, THE SYSTEM SHALL number group 0 as 0 and data groups from 1 | the badge matches the wallpaper page's group 0 | `F:visible_range_controller_test#data groups are numbered from 1 and group 0 stays 0` |
| GRP-5 | Sentinel cleanup | WHEN a stored group 0 carries a condition, THE SYSTEM SHALL clear it on the next start | a pre-refactor base must not linger | `F:visible_range_controller_test#a stored condition in group 0 is cleared on the next start` |
| GRP-6 | Draft save | WHEN the editor saves a draft, THE SYSTEM SHALL replace the group and its conditions together | the page edits one aggregate | `F:visible_range_controller_test#saving a group editor draft persists the whole group` |
| GRP-7 | Current group entry | WHEN the overflow is opened with nothing selected, THE SYSTEM SHALL offer editing the current group and SHALL disable it for group 0 | the same action must not need a long press | `F:visible_range_group_actions_test#with no selection the current group is edited` |
| GRP-8 | Selected group entry | WHEN exactly one group tile is selected, THE SYSTEM SHALL offer editing that group; a condition or multi-group selection SHALL offer none | the edit target follows the selection | `F:visible_range_group_actions_test#one selected group is edited instead of the current one`; `F:visible_range_group_actions_test#a condition or a multi-group selection has no single group to edit` |
| GRP-9 | Parked sources | WHEN 「Unrestricted」 is chosen in the editor, THE SYSTEM SHALL switch the sources off and keep their filters | a parked source can be switched back on instead of being lost | `F:visible_range_model_test#parking the sources keeps their filters and stops restricting`; `F:visible_range_candidate_test#parked sources keep their tiles and light the unrestricted tile` |

## Saving and navigation

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SAVE-1 | Outside badges | WHEN the save sheet shows the two outside targets, THE SYSTEM SHALL label each with its role instead of two identical zeroes | the two targets write the same pool | `F:visible_range_target_grid_test#outside targets show their role instead of two identical zeroes` |
| SAVE-2 | Remember scope | WHEN the save sheet opens, THE SYSTEM SHALL name the injection mode as the only remembered option; role, append/replace and write-back targets reset | an unscoped 「Remember this choice」 named neither its subject nor its limits | `F:visible_range_pin_sheet_test#the remember option names what it stores` |
| SAVE-3 | Forget on clear | WHEN the remember option is cleared, THE SYSTEM SHALL drop the stored mode so the next open starts from `auto` | an unchecked switch must actually forget | `F:visible_range_controller_test#clearing the remember option forgets the stored injection mode` |
| SAVE-4 | Per-save role | WHEN the automatic split is chosen, THE SYSTEM SHALL select it directly, and a custom role SHALL be picked from a menu on every tap for this save only | a role must not silently persist into the next save | `F:visible_range_pin_sheet_test#the role starts from the automatic split on every open`; `F:visible_range_pin_sheet_test#the custom role button opens the role menu on every tap` |
| SAVE-5 | Append or replace | WHEN a group already holds conditions, THE SYSTEM SHALL offer append and replace as two named choices | a switch behind 「Existing conditions / Append」 did not say what the off state meant | `F:visible_range_pin_sheet_test#the existing conditions choice is two named buttons, not a switch` |
| SAVE-6 | Expected write locations | WHEN the save sheet is used, THE SYSTEM SHALL name the checked groups before the checked write-back rules outside the fold, and SHALL update the list on every tick | a folded advanced section must not hide where the confirmation writes | `F:visible_range_expected_writes_test#groups are listed before write-back rules and only selected places appear`; `F:visible_range_write_back_section_test#a ticked rule reaches the summary without a sheet rebuild`; `F:visible_range_pin_sheet_test#ticking a group adds it to the expected write locations`; `F:visible_range_pin_sheet_test#ticking a rule reaches the expected locations without closing the sheet` |
| SAVE-7 | Empty default | WHEN the save sheet opens, THE SYSTEM SHALL start with no group selected and SHALL disable save until a target or a rule is chosen | a save must be an explicit choice, even for the group currently on screen | `F:visible_range_pin_sheet_test#the sheet opens with nothing selected` |
| SAVE-8 | Target section names | WHEN the sheet lists targets, THE SYSTEM SHALL name the gallery section 「Normal groups」 and the scope-wide pool 「Outside groups」 | the gallery groups must not be mistaken for the wallpaper groups below them | `F:visible_range_pin_sheet_test#the gallery section is named apart from the wallpaper one` |
| NAV-6 | Fork order | WHEN the wallpaper page and the group editor are both open, THE SYSTEM SHALL place the first-opened nearest the range entry | opening order is what the user remembers | `F:grouped_wallpaper_nav_test#the two fork entries are ordered by open time, first nearest the range` |
| NAV-7 | Closed editor | WHEN the editor session is closed, THE SYSTEM SHALL render the range page | the page is the session | `F:visible_range_destination_test#a closed editor session falls back to the range page` |
| NAV-8 | Editor entry route | WHEN the editor entry is built, THE SYSTEM SHALL resolve it to the editor page | an unregistered fork route threw `unknown route`, so the entry opened nothing | `F:nav_item_test#the group editor entry opens its page` |
| NAV-9 | Editor entry on itself | WHEN the editor entry is tapped while the editor is on top, THE SYSTEM SHALL not stack a second page | one page is one entry | `F:nav_item_test#tapping the entry of the page already on top does not stack another one` |
