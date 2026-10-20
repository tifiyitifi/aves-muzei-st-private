import 'package:aves/model/entry/entry.dart';

/// Where the import hands over the rows it has written.
///
/// The browse-only surface needs the library before the database has it, but
/// the paging engine must not know that surface exists: this hook is installed
/// by the composition root and is null everywhere else, which also keeps every
/// existing import caller (tests included) on the plain path.
typedef ImportRowsSink = void Function(List<AvesEntry> rows);

ImportRowsSink? importRowsSink;
