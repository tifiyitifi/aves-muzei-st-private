import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

@immutable
class const EntryHeroInfo(
  final CollectionLens? collection,
  final AvesEntry? entry,
) extends Equatable {
  @override
  List<Object?> get props => [collection?.id, entry?.uri];

  // hero tag should include a collection identifier, so that it animates
  // between different views of the entry in the same collection (e.g. thumbnails <-> viewer)
  // but not between different collection instances, even with the same attributes (e.g. reloading collection page via drawer)
  //
  // The row id is part of it because the URI alone does not identify a row: two
  // rows can carry the same media URI (a duplicate the database now rejects, but
  // an older one may still hold), and two tiles sharing a tag abort the
  // transition with Flutter's "multiple heroes" assertion.
  int get tag => Object.hashAll([collection?.id, entry?.id, entry?.uri]);
}
