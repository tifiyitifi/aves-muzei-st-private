# Visible range — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-visible-range-rules.ps1` resolves every `F:`
token.

## Model

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| MOD-1 | Empty range | WHEN nothing is active, THE SYSTEM SHALL restrict nothing | a fresh install browses the whole library | `F:visible_range_model_test#an empty range restricts nothing` |
| MOD-2 | Switched-off base | WHEN the base is switched off, THE SYSTEM SHALL keep its filters but not restrict | a wallpaper group can disable its base without losing it | `F:visible_range_model_test#a switched-off base does not restrict and keeps its filters` |
| MOD-3 | Intersect-first | WHEN the order is intersect-first, THE SYSTEM SHALL resolve `base AND restrictions, then OR supplements` | this is the inherited scenario semantics | `F:visible_range_model_test#intersect-first combines base AND restrictions, then OR supplements` |
| MOD-4 | Union-first | WHEN the order is union-first, THE SYSTEM SHALL resolve `base OR supplements, then AND restrictions` | the second inherited order | `F:visible_range_model_test#union-first ORs supplements first, then ANDs restrictions` |
| MOD-5 | Unrestricted base | WHEN the base is unrestricted, THE SYSTEM SHALL make the union step a no-op in both orders | otherwise a supplement would silently restrict | `F:visible_range_model_test#an unrestricted base is a no-op in both orders` |
| MOD-6 | Supplements alone | WHEN only supplements are active, THE SYSTEM SHALL not restrict browsing | a supplement adds entries, it cannot remove them | `F:visible_range_model_test#a supplement alone never restricts browsing` |
| MOD-7 | Inactive rules | WHEN a rule is switched off, THE SYSTEM SHALL ignore its filters | the chip toggle must change the result | `F:visible_range_model_test#inactive rules do not contribute` |
| MOD-8 | Restricted predicate | WHEN `isRestricted` is evaluated, THE SYSTEM SHALL consider only the base and the active restrictions | supplements never narrow | `F:visible_range_model_test#restricted is decided by the base and restrictions only` |
| MOD-9 | Rule conjunction | WHEN a rule holds several filters, THE SYSTEM SHALL AND them | one rule is one condition | `F:visible_range_model_test#every rule filter is AND-ed inside its rule` |
| MOD-10 | Step queries | WHEN the page shows a cumulative count, THE SYSTEM SHALL mirror the evaluation order | a mismatched intermediate shows the wrong total | `F:visible_range_model_test#the step queries mirror the evaluation order` |
| MOD-11 | Union-first intermediate | WHEN the base is unrestricted in union-first, THE SYSTEM SHALL have no intermediate narrowing | the union step excepts everything | `F:visible_range_model_test#an unrestricted base has no intermediate in union-first` |
| MOD-12 | Order independence | WHEN the same filter sets are expressed in another order, THE SYSTEM SHALL compare them as equal | equality drives cache invalidation | `F:visible_range_model_test#is order independent and distinguishes different sets` |
| MOD-13 | Rule target | WHEN a target stands for a rule, THE SYSTEM SHALL keep its global id and kind | write-back needs to find the rule | `F:visible_range_model_test#a rule target keeps its global id and kind` |
| MOD-14 | Base target | WHEN a target stands for a base, THE SYSTEM SHALL address it by its range | a base has no rule row | `F:visible_range_model_test#a base target is addressed by its range` |
| MOD-15 | Stable usage id | WHEN the same target is recorded twice, THE SYSTEM SHALL map it to one usage id | applied targets must not duplicate | `F:visible_range_model_test#the same target maps to one stable usage id` |
| MOD-16 | Fingerprint | WHEN a filter set is fingerprinted, THE SYSTEM SHALL ignore order and distinguish different sets | dedupe of presets and rules relies on it | `F:visible_range_candidate_filter_test#summary and grid copies have different keys`; `F:visible_range_model_test#is order independent and distinguishes different sets` |

## Candidates and summary

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CND-1 | Base section | WHEN the base section is built, THE SYSTEM SHALL start with the unrestricted tile | clearing a base must stay one tap away | `F:visible_range_candidate_test#the base section starts with the unrestricted tile` |
| CND-2 | Selected base | WHEN a base is chosen, THE SYSTEM SHALL show the unrestricted tile as unselected | one base at a time | `F:visible_range_candidate_test#unrestricted becomes an unselected option when a base is chosen` |
| CND-3 | Deleted preset | WHEN a base preset is deleted, THE SYSTEM SHALL keep its filters as a selected custom tile | deleting a preset must not widen the range | `F:visible_range_candidate_test#a base whose preset was deleted keeps a selected custom tile` |
| CND-4 | Rule order | WHEN rules are listed, THE SYSTEM SHALL group by kind and put defaults first | the page's stable order | `F:visible_range_candidate_test#rules are grouped by kind and defaults come first` |
| CND-5 | Labels | WHEN a candidate is a built-in, THE SYSTEM SHALL use its key; a rename SHALL be plain text | built-ins are localized, user text is not | `F:visible_range_candidate_test#a built-in label is a key and a rename is plain text`; `F:visible_range_candidate_test#a preset name is localized only for built-ins` |
| CND-6 | Shared stats key | WHEN two candidates share filters, THE SYSTEM SHALL share one stats key | one query per distinct set | `F:visible_range_candidate_test#candidates with the same filters share a stats key` |
| CND-7 | Unrestricted tile | WHEN the unrestricted tile is built, THE SYSTEM SHALL carry no filters | it means 「不限」 | `F:visible_range_candidate_test#the unrestricted tile is const and never carries filters` |
| CND-8 | Active section | WHEN the active section is built, THE SYSTEM SHALL repeat the base and the enabled rules | the page must describe what is in force | `F:visible_range_candidate_test#the active section repeats the result, the base and the enabled rules`; `F:visible_range_candidate_test#the active section omits an unrestricted base` |
| CND-9 | Filter conjunction | WHEN a candidate is tested, THE SYSTEM SHALL test the conjunction of its filters | matching mirrors the SQL path | `F:visible_range_candidate_filter_test#a candidate filter tests the conjunction of its filters` |
| CND-10 | Unrestricted match | WHEN a candidate has no filters, THE SYSTEM SHALL match everything | an unrestricted candidate is not a filter | `F:visible_range_candidate_filter_test#an unrestricted candidate matches everything` |
| CND-11 | Fallback label | WHEN a candidate has no explicit label, THE SYSTEM SHALL use its filter labels | user rules need a name without prompting | `F:visible_range_candidate_filter_test#the universal label falls back to the filter labels` |
| CND-12 | Reversed filter | WHEN a filter is reversed, THE SYSTEM SHALL keep the reverse semantics | summary exclusion uses the complement | `F:visible_range_candidate_filter_test#a reversed filter keeps its reverse semantics` |
| SUM-1 | Base named | WHEN a base is named like its group, THE SYSTEM SHALL not repeat it | the summary would read twice | `F:visible_range_summary_test#a base named like its group is not repeated` |
| SUM-2 | Restrictions counted | WHEN active restrictions exist, THE SYSTEM SHALL count them | the summary states how many narrowers apply | `F:visible_range_summary_test#active restrictions are counted` |
| SUM-3 | Supplements ignored | WHEN supplements are active, THE SYSTEM SHALL not count them as narrowers | they widen | `F:visible_range_summary_test#supplements are never counted` |
| SUM-4 | Renamed group | WHEN a group is renamed, THE SYSTEM SHALL name its range from the group | the user sees their own name | `F:visible_range_summary_test#a renamed group still names its range` |
| SUM-5 | Unrestricted base | WHEN the base is unrestricted, THE SYSTEM SHALL not name it | there is nothing to name | `F:visible_range_summary_test#an unrestricted base is not named` |
| SUM-6 | Unnamed base | WHEN the base has no name, THE SYSTEM SHALL fall back to its filters | a saved range still needs a label | `F:visible_range_summary_test#an unnamed base falls back to its filters` |
| SUM-7 | Group 0 | WHEN the wallpaper page shows group 0, THE SYSTEM SHALL report no range description | group 0 means the gallery range alone | `F:visible_range_summary_test#group 0 has no range to describe` |

## Store

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STO-1 | Aggregate round trip | WHEN a range is saved, THE SYSTEM SHALL store the range and its rules together | a reader never sees half a range | `F:visible_range_store_test#round-trips a range and its rules` |
| STO-2 | Permissions | WHEN a range is locked, THE SYSTEM SHALL store the edited permissions | the lock outlives the session | `F:visible_range_store_test#stores edited permissions` |
| STO-3 | Unlocked clears | WHEN a range is unlocked, THE SYSTEM SHALL drop stale permissions | an unlocked range must not carry a frozen set | `F:visible_range_store_test#an unlocked range drops stale permissions` |
| STO-4 | Replace rules | WHEN a rule set is replaced, THE SYSTEM SHALL replace the whole set | a partial update leaves orphans | `F:visible_range_store_test#replaceRules replaces the whole set` |
| STO-5 | Delete range | WHEN a range is deleted, THE SYSTEM SHALL delete its rules and applied targets | orphans would point at a missing range | `F:visible_range_store_test#deleting a range clears its rules and applied targets` |
| STO-6 | Presets and state | WHEN presets and view state are written, THE SYSTEM SHALL read them back | the page must survive a restart | `F:visible_range_store_test#presets and state round-trip` |
| STO-7 | Applied targets | WHEN an applied target is recorded, THE SYSTEM SHALL keep it tied to its rule | the pin sheet writes back over it | `F:visible_range_store_test#applied targets round-trip and follow their rule` |

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
| CTL-1 | First start | WHEN the controller starts, THE SYSTEM SHALL be unrestricted with the built-in presets seeded once | a fresh install must not restrict anything | `F:visible_range_controller_test#starts unrestricted with the built-in presets seeded once` |
| CTL-2 | Select base | WHEN a base is selected, THE SYSTEM SHALL persist it and resolve it | the choice must survive a restart | `F:visible_range_controller_test#selecting a base persists and resolves` |
| CTL-3 | Clear base | WHEN the base is cleared, THE SYSTEM SHALL return to unrestricted | clearing is one action | `F:visible_range_controller_test#clearing the base returns to unrestricted` |
| CTL-4 | Rule edits | WHEN a rule is added, toggled or deleted, THE SYSTEM SHALL persist the change | rule state is user data | `F:visible_range_controller_test#rules persist, toggle and delete` |
| CTL-5 | Empty rule | WHEN an empty rule is added, THE SYSTEM SHALL ignore it | an empty rule would show a blank tile | `F:visible_range_controller_test#adding an empty rule is a no-op` |
| CTL-6 | Locked edits | WHEN the range is locked, THE SYSTEM SHALL reject edits | the lock freezes the range itself | `F:visible_range_controller_test#a locked range rejects edits` |
| CTL-7 | Quick lock | WHEN the quick lock is used, THE SYSTEM SHALL reuse the last permissions preset | the user should not re-choose | `F:visible_range_controller_test#quick lock reuses the last permissions preset` |
| CTL-8 | View preferences | WHEN the active style changes, THE SYSTEM SHALL persist it across a restart | it is a view preference | `F:visible_range_controller_test#view preferences persist across a restart` |
| CTL-9 | Default style | WHEN no style is stored, THE SYSTEM SHALL use the section style | the default presentation | `F:visible_range_controller_test#the active conditions default to the section style` |
| CTL-10 | Defaults bump | WHEN the defaults version is bumped, THE SYSTEM SHALL reorder and prune built-ins while keeping user state | installs must converge on the bundle | `F:visible_range_controller_test#a defaults bump reorders and prunes built-ins while keeping user state` |
| CTL-11 | Re-add defaults | WHEN defaults are re-added, THE SYSTEM SHALL skip existing ids and fingerprints | re-adding must not duplicate | `F:visible_range_controller_test#re-adding defaults skips existing ids and fingerprints` |
| CTL-12 | Inactive defaults | WHEN restriction and supplement defaults are seeded, THE SYSTEM SHALL seed them switched off | they are candidates, not decisions | `F:visible_range_controller_test#restriction and supplement defaults are seeded switched off` |
| CTL-13 | Restore default | WHEN a deleted default is restored, THE SYSTEM SHALL restore it switched off | restoring must not change the result | `F:visible_range_controller_test#a deleted default is restored switched off` |
| CTL-14 | Bundle replacement | WHEN the defaults version bumps, THE SYSTEM SHALL replace the default set but keep user rules | user data outranks the bundle | `F:visible_range_controller_test#a defaults version bump replaces the default set but keeps user rules` |

## Apply and write-back

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| APL-1 | Remember targets | WHEN candidates are applied, THE SYSTEM SHALL remember them deduped by id | the pin sheet writes back over the current view | `F:visible_range_apply_test#taking a rule and a base out remembers both, deduped by id` |
| APL-2 | Deleted rule | WHEN a rule is deleted from its range, THE SYSTEM SHALL drop it from the applied list | a dangling target cannot be written back | `F:visible_range_apply_test#a rule deleted from its range disappears from the list` |
| APL-3 | Write-back scope | WHEN the current filters are written back, THE SYSTEM SHALL overwrite only the selected rule and base | the rest of the range is not the view | `F:visible_range_apply_test#write-back overwrites the selected rule and base only` |
| APL-4 | Locked target | WHEN the selected target is locked, THE SYSTEM SHALL skip it and count it | a locked range must not change | `F:visible_range_apply_test#a locked range is skipped and counted` |
| APL-5 | Empty selection | WHEN nothing is selected, THE SYSTEM SHALL write nothing | an empty view is not a range | `F:visible_range_apply_test#an empty selection writes nothing` |
| APL-6 | Target order | WHEN the pin sheet lists targets, THE SYSTEM SHALL show the gallery first, then the groups | the gallery is the default surface | `F:visible_range_apply_test#the pin sheet lists the gallery first, then the groups` |
| APL-7 | One visit | WHEN a pin request names the gallery and a group, THE SYSTEM SHALL write both in one visit | one confirmation, two targets | `F:visible_range_apply_test#a pin request writes the gallery and the group in one visit` |
| APL-8 | Locked group | WHEN a group target is locked, THE SYSTEM SHALL skip it without failing | the gallery still applies | `F:visible_range_apply_test#a locked group target is skipped, not failed` |
| APL-9 | Group base | WHEN a base is pinned to a group, THE SYSTEM SHALL store it on the range, not in the preset catalog | the preset catalog is global | `F:visible_range_apply_test#a base pinned to a group is stored on the range, not in the preset catalog` |
| APL-10 | Group rule | WHEN a group rule is written back, THE SYSTEM SHALL go through the group's source | the group range owns its rules | `F:visible_range_apply_test#a group rule can be taken out and written back through the source` |
| PIN-1 | Targets | WHEN the pin sheet is built, THE SYSTEM SHALL treat the gallery as the only target without a registered source | groups come from the group store | `F:visible_range_pin_test#the gallery is the only target without a registered source` |
| PIN-2 | Pin a restriction | WHEN filters are pinned to a restriction, THE SYSTEM SHALL add one active rule with name and description | the user's note is the rule's label | `F:visible_range_pin_test#pinning a restriction adds one active rule with name and description` |
| PIN-3 | Two kinds | WHEN filters are pinned to both kinds, THE SYSTEM SHALL write one rule per kind | restriction and supplement are separate sets | `F:visible_range_pin_test#pinning to restriction and supplement writes one rule per group` |
| PIN-4 | Re-pin | WHEN the same conditions are pinned again, THE SYSTEM SHALL update the existing rule | pinning must not stack duplicates | `F:visible_range_pin_test#re-pinning the same conditions updates the rule instead of stacking` |
| PIN-5 | Unknown target | WHEN a target is unknown or locked, THE SYSTEM SHALL skip it | a stale target must not fail the request | `F:visible_range_pin_test#unknown or locked target ids are skipped` |
| PIN-6 | Base preset | WHEN a base is pinned, THE SYSTEM SHALL create a preset, select it and reuse it on re-pin | the base section is preset-driven | `F:visible_range_pin_test#pinning a base creates a preset, selects it and reuses it on re-pin` |
| PIN-7 | Second preset | WHEN a different name is pinned for the same filters, THE SYSTEM SHALL create a second preset | two named ranges may share conditions | `F:visible_range_pin_test#a different name creates a second base preset for the same filters` |
| PIN-8 | Both kinds | WHEN a base and a restriction are pinned in one request, THE SYSTEM SHALL write both | one dialog, one write | `F:visible_range_pin_test#base and restriction can be pinned in one request` |
| PIN-9 | Locked range | WHEN the range is locked, THE SYSTEM SHALL skip it instead of failing | a locked target is not an error | `F:visible_range_pin_test#a locked range is skipped instead of failing the request` |
| PIN-10 | Survives restart | WHEN pinned rules and notes are written, THE SYSTEM SHALL read them back after a restart | the user's notes are data | `F:visible_range_pin_test#pinned rules and notes survive a restart` |
| PIN-11 | Edit preset | WHEN a user base preset is edited, THE SYSTEM SHALL update its name and description | a preset is renameable | `F:visible_range_pin_test#editing a user base preset updates its name and description` |
| PIN-12 | Empty request | WHEN a pin request is empty, THE SYSTEM SHALL do nothing | no dialog, no write | `F:visible_range_pin_test#an empty request is a no-op` |
| PIN-13 | Video filter | WHEN the video filter is pinned, THE SYSTEM SHALL keep it independent of the image one | they are distinct conditions | `F:visible_range_pin_test#the video filter can be pinned independently of the image one` |

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
| MIG-3 | Base activation | WHEN a v8 database upgrades, THE SYSTEM SHALL add the base activation flag as active | a group base can be switched off | `F:migration_v9_test#a v8 database gains the base activation flag as active`; `F:migration_v9_test#a fresh database has the column and it defaults to active` |
