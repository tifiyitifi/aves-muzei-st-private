// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $EntriesTableTable extends EntriesTable
    with TableInfo<$EntriesTableTable, EntriesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentIdMeta = const VerificationMeta(
    'contentId',
  );
  @override
  late final GeneratedColumn<int> contentId = GeneratedColumn<int>(
    'contentId',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
    'uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMimeTypeMeta = const VerificationMeta(
    'sourceMimeType',
  );
  @override
  late final GeneratedColumn<String> sourceMimeType = GeneratedColumn<String>(
    'sourceMimeType',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceRotationDegreesMeta =
      const VerificationMeta('sourceRotationDegrees');
  @override
  late final GeneratedColumn<int> sourceRotationDegrees = GeneratedColumn<int>(
    'sourceRotationDegrees',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'sizeBytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateAddedSecsMeta = const VerificationMeta(
    'dateAddedSecs',
  );
  @override
  late final GeneratedColumn<int> dateAddedSecs = GeneratedColumn<int>(
    'dateAddedSecs',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateModifiedMillisMeta =
      const VerificationMeta('dateModifiedMillis');
  @override
  late final GeneratedColumn<int> dateModifiedMillis = GeneratedColumn<int>(
    'dateModifiedMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceDateTakenMillisMeta =
      const VerificationMeta('sourceDateTakenMillis');
  @override
  late final GeneratedColumn<int> sourceDateTakenMillis = GeneratedColumn<int>(
    'sourceDateTakenMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMillisMeta = const VerificationMeta(
    'durationMillis',
  );
  @override
  late final GeneratedColumn<int> durationMillis = GeneratedColumn<int>(
    'durationMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trashedMeta = const VerificationMeta(
    'trashed',
  );
  @override
  late final GeneratedColumn<int> trashed = GeneratedColumn<int>(
    'trashed',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<int> origin = GeneratedColumn<int>(
    'origin',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseNameMeta = const VerificationMeta(
    'baseName',
  );
  @override
  late final GeneratedColumn<String> baseName = GeneratedColumn<String>(
    'baseName',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stackKeyMeta = const VerificationMeta(
    'stackKey',
  );
  @override
  late final GeneratedColumn<String> stackKey = GeneratedColumn<String>(
    'stackKey',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stackTileIdMeta = const VerificationMeta(
    'stackTileId',
  );
  @override
  late final GeneratedColumn<int> stackTileId = GeneratedColumn<int>(
    'stackTileId',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    contentId,
    uri,
    path,
    sourceMimeType,
    width,
    height,
    sourceRotationDegrees,
    sizeBytes,
    title,
    dateAddedSecs,
    dateModifiedMillis,
    sourceDateTakenMillis,
    durationMillis,
    trashed,
    origin,
    directory,
    baseName,
    stackKey,
    stackTileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntriesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('contentId')) {
      context.handle(
        _contentIdMeta,
        contentId.isAcceptableOrUnknown(data['contentId']!, _contentIdMeta),
      );
    }
    if (data.containsKey('uri')) {
      context.handle(
        _uriMeta,
        uri.isAcceptableOrUnknown(data['uri']!, _uriMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('sourceMimeType')) {
      context.handle(
        _sourceMimeTypeMeta,
        sourceMimeType.isAcceptableOrUnknown(
          data['sourceMimeType']!,
          _sourceMimeTypeMeta,
        ),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('sourceRotationDegrees')) {
      context.handle(
        _sourceRotationDegreesMeta,
        sourceRotationDegrees.isAcceptableOrUnknown(
          data['sourceRotationDegrees']!,
          _sourceRotationDegreesMeta,
        ),
      );
    }
    if (data.containsKey('sizeBytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['sizeBytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('dateAddedSecs')) {
      context.handle(
        _dateAddedSecsMeta,
        dateAddedSecs.isAcceptableOrUnknown(
          data['dateAddedSecs']!,
          _dateAddedSecsMeta,
        ),
      );
    }
    if (data.containsKey('dateModifiedMillis')) {
      context.handle(
        _dateModifiedMillisMeta,
        dateModifiedMillis.isAcceptableOrUnknown(
          data['dateModifiedMillis']!,
          _dateModifiedMillisMeta,
        ),
      );
    }
    if (data.containsKey('sourceDateTakenMillis')) {
      context.handle(
        _sourceDateTakenMillisMeta,
        sourceDateTakenMillis.isAcceptableOrUnknown(
          data['sourceDateTakenMillis']!,
          _sourceDateTakenMillisMeta,
        ),
      );
    }
    if (data.containsKey('durationMillis')) {
      context.handle(
        _durationMillisMeta,
        durationMillis.isAcceptableOrUnknown(
          data['durationMillis']!,
          _durationMillisMeta,
        ),
      );
    }
    if (data.containsKey('trashed')) {
      context.handle(
        _trashedMeta,
        trashed.isAcceptableOrUnknown(data['trashed']!, _trashedMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    }
    if (data.containsKey('baseName')) {
      context.handle(
        _baseNameMeta,
        baseName.isAcceptableOrUnknown(data['baseName']!, _baseNameMeta),
      );
    }
    if (data.containsKey('stackKey')) {
      context.handle(
        _stackKeyMeta,
        stackKey.isAcceptableOrUnknown(data['stackKey']!, _stackKeyMeta),
      );
    }
    if (data.containsKey('stackTileId')) {
      context.handle(
        _stackTileIdMeta,
        stackTileId.isAcceptableOrUnknown(
          data['stackTileId']!,
          _stackTileIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntriesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntriesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      contentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}contentId'],
      ),
      uri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uri'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      sourceMimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sourceMimeType'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      sourceRotationDegrees: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sourceRotationDegrees'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sizeBytes'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      dateAddedSecs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dateAddedSecs'],
      ),
      dateModifiedMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dateModifiedMillis'],
      ),
      sourceDateTakenMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sourceDateTakenMillis'],
      ),
      durationMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}durationMillis'],
      ),
      trashed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}trashed'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}origin'],
      ),
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      ),
      baseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baseName'],
      ),
      stackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stackKey'],
      ),
      stackTileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stackTileId'],
      ),
    );
  }

  @override
  $EntriesTableTable createAlias(String alias) {
    return $EntriesTableTable(attachedDatabase, alias);
  }
}

class EntriesTableData extends DataClass
    implements Insertable<EntriesTableData> {
  final int id;
  final int? contentId;
  final String? uri;
  final String? path;
  final String? sourceMimeType;
  final int? width;
  final int? height;
  final int? sourceRotationDegrees;
  final int? sizeBytes;
  final String? title;
  final int? dateAddedSecs;
  final int? dateModifiedMillis;
  final int? sourceDateTakenMillis;
  final int? durationMillis;
  final int? trashed;
  final int? origin;

  /// Raw single-level parent directory (`dirname(path)`), maintained by the
  /// entries domain on every write and backfilled by `MigrationV3`.
  ///
  /// Powers indexed album grouping and single-level directory filters without
  /// scanning paths. Display names still resolve through `entryDirRepo`, which
  /// may disambiguate case variants against the filesystem.
  final String? directory;

  /// Raw `basenameWithoutExtension(path)`, maintained by the entries domain on
  /// every write and backfilled by `MigrationV4`.
  ///
  /// Gives the title search and the stack keys a SQL-visible file name: SQLite
  /// has no reverse `instr`, so neither the base name nor the extension can be
  /// derived from `path` inside a query.
  final String? baseName;

  /// Burst group key (`'<directory>/<burst key>'`), or NULL when no configured
  /// pattern matches the entry's name. Maintained on every write.
  final String? stackKey;

  /// The row a stack member hides behind, or NULL when the row shows itself
  /// (the tile of its group, a row in no group, or a group with no single tile).
  ///
  /// Materialized because which member shows is a group-level decision (and, for
  /// bursts, needs a natural name order SQLite cannot express). The paged view
  /// hides a member only while its tile is in the same scope, so it tests
  /// `stackTileId IS NULL OR stackTileId IN (<tile ids the predicate admits>)`.
  final int? stackTileId;
  const EntriesTableData({
    required this.id,
    this.contentId,
    this.uri,
    this.path,
    this.sourceMimeType,
    this.width,
    this.height,
    this.sourceRotationDegrees,
    this.sizeBytes,
    this.title,
    this.dateAddedSecs,
    this.dateModifiedMillis,
    this.sourceDateTakenMillis,
    this.durationMillis,
    this.trashed,
    this.origin,
    this.directory,
    this.baseName,
    this.stackKey,
    this.stackTileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || contentId != null) {
      map['contentId'] = Variable<int>(contentId);
    }
    if (!nullToAbsent || uri != null) {
      map['uri'] = Variable<String>(uri);
    }
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || sourceMimeType != null) {
      map['sourceMimeType'] = Variable<String>(sourceMimeType);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || sourceRotationDegrees != null) {
      map['sourceRotationDegrees'] = Variable<int>(sourceRotationDegrees);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['sizeBytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || dateAddedSecs != null) {
      map['dateAddedSecs'] = Variable<int>(dateAddedSecs);
    }
    if (!nullToAbsent || dateModifiedMillis != null) {
      map['dateModifiedMillis'] = Variable<int>(dateModifiedMillis);
    }
    if (!nullToAbsent || sourceDateTakenMillis != null) {
      map['sourceDateTakenMillis'] = Variable<int>(sourceDateTakenMillis);
    }
    if (!nullToAbsent || durationMillis != null) {
      map['durationMillis'] = Variable<int>(durationMillis);
    }
    if (!nullToAbsent || trashed != null) {
      map['trashed'] = Variable<int>(trashed);
    }
    if (!nullToAbsent || origin != null) {
      map['origin'] = Variable<int>(origin);
    }
    if (!nullToAbsent || directory != null) {
      map['directory'] = Variable<String>(directory);
    }
    if (!nullToAbsent || baseName != null) {
      map['baseName'] = Variable<String>(baseName);
    }
    if (!nullToAbsent || stackKey != null) {
      map['stackKey'] = Variable<String>(stackKey);
    }
    if (!nullToAbsent || stackTileId != null) {
      map['stackTileId'] = Variable<int>(stackTileId);
    }
    return map;
  }

  EntriesTableCompanion toCompanion(bool nullToAbsent) {
    return EntriesTableCompanion(
      id: Value(id),
      contentId: contentId == null && nullToAbsent
          ? const Value.absent()
          : Value(contentId),
      uri: uri == null && nullToAbsent ? const Value.absent() : Value(uri),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      sourceMimeType: sourceMimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMimeType),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      sourceRotationDegrees: sourceRotationDegrees == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceRotationDegrees),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      dateAddedSecs: dateAddedSecs == null && nullToAbsent
          ? const Value.absent()
          : Value(dateAddedSecs),
      dateModifiedMillis: dateModifiedMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(dateModifiedMillis),
      sourceDateTakenMillis: sourceDateTakenMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDateTakenMillis),
      durationMillis: durationMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMillis),
      trashed: trashed == null && nullToAbsent
          ? const Value.absent()
          : Value(trashed),
      origin: origin == null && nullToAbsent
          ? const Value.absent()
          : Value(origin),
      directory: directory == null && nullToAbsent
          ? const Value.absent()
          : Value(directory),
      baseName: baseName == null && nullToAbsent
          ? const Value.absent()
          : Value(baseName),
      stackKey: stackKey == null && nullToAbsent
          ? const Value.absent()
          : Value(stackKey),
      stackTileId: stackTileId == null && nullToAbsent
          ? const Value.absent()
          : Value(stackTileId),
    );
  }

  factory EntriesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntriesTableData(
      id: serializer.fromJson<int>(json['id']),
      contentId: serializer.fromJson<int?>(json['contentId']),
      uri: serializer.fromJson<String?>(json['uri']),
      path: serializer.fromJson<String?>(json['path']),
      sourceMimeType: serializer.fromJson<String?>(json['sourceMimeType']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      sourceRotationDegrees: serializer.fromJson<int?>(
        json['sourceRotationDegrees'],
      ),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      title: serializer.fromJson<String?>(json['title']),
      dateAddedSecs: serializer.fromJson<int?>(json['dateAddedSecs']),
      dateModifiedMillis: serializer.fromJson<int?>(json['dateModifiedMillis']),
      sourceDateTakenMillis: serializer.fromJson<int?>(
        json['sourceDateTakenMillis'],
      ),
      durationMillis: serializer.fromJson<int?>(json['durationMillis']),
      trashed: serializer.fromJson<int?>(json['trashed']),
      origin: serializer.fromJson<int?>(json['origin']),
      directory: serializer.fromJson<String?>(json['directory']),
      baseName: serializer.fromJson<String?>(json['baseName']),
      stackKey: serializer.fromJson<String?>(json['stackKey']),
      stackTileId: serializer.fromJson<int?>(json['stackTileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'contentId': serializer.toJson<int?>(contentId),
      'uri': serializer.toJson<String?>(uri),
      'path': serializer.toJson<String?>(path),
      'sourceMimeType': serializer.toJson<String?>(sourceMimeType),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'sourceRotationDegrees': serializer.toJson<int?>(sourceRotationDegrees),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'title': serializer.toJson<String?>(title),
      'dateAddedSecs': serializer.toJson<int?>(dateAddedSecs),
      'dateModifiedMillis': serializer.toJson<int?>(dateModifiedMillis),
      'sourceDateTakenMillis': serializer.toJson<int?>(sourceDateTakenMillis),
      'durationMillis': serializer.toJson<int?>(durationMillis),
      'trashed': serializer.toJson<int?>(trashed),
      'origin': serializer.toJson<int?>(origin),
      'directory': serializer.toJson<String?>(directory),
      'baseName': serializer.toJson<String?>(baseName),
      'stackKey': serializer.toJson<String?>(stackKey),
      'stackTileId': serializer.toJson<int?>(stackTileId),
    };
  }

  EntriesTableData copyWith({
    int? id,
    Value<int?> contentId = const Value.absent(),
    Value<String?> uri = const Value.absent(),
    Value<String?> path = const Value.absent(),
    Value<String?> sourceMimeType = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> sourceRotationDegrees = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<int?> dateAddedSecs = const Value.absent(),
    Value<int?> dateModifiedMillis = const Value.absent(),
    Value<int?> sourceDateTakenMillis = const Value.absent(),
    Value<int?> durationMillis = const Value.absent(),
    Value<int?> trashed = const Value.absent(),
    Value<int?> origin = const Value.absent(),
    Value<String?> directory = const Value.absent(),
    Value<String?> baseName = const Value.absent(),
    Value<String?> stackKey = const Value.absent(),
    Value<int?> stackTileId = const Value.absent(),
  }) => EntriesTableData(
    id: id ?? this.id,
    contentId: contentId.present ? contentId.value : this.contentId,
    uri: uri.present ? uri.value : this.uri,
    path: path.present ? path.value : this.path,
    sourceMimeType: sourceMimeType.present
        ? sourceMimeType.value
        : this.sourceMimeType,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    sourceRotationDegrees: sourceRotationDegrees.present
        ? sourceRotationDegrees.value
        : this.sourceRotationDegrees,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    title: title.present ? title.value : this.title,
    dateAddedSecs: dateAddedSecs.present
        ? dateAddedSecs.value
        : this.dateAddedSecs,
    dateModifiedMillis: dateModifiedMillis.present
        ? dateModifiedMillis.value
        : this.dateModifiedMillis,
    sourceDateTakenMillis: sourceDateTakenMillis.present
        ? sourceDateTakenMillis.value
        : this.sourceDateTakenMillis,
    durationMillis: durationMillis.present
        ? durationMillis.value
        : this.durationMillis,
    trashed: trashed.present ? trashed.value : this.trashed,
    origin: origin.present ? origin.value : this.origin,
    directory: directory.present ? directory.value : this.directory,
    baseName: baseName.present ? baseName.value : this.baseName,
    stackKey: stackKey.present ? stackKey.value : this.stackKey,
    stackTileId: stackTileId.present ? stackTileId.value : this.stackTileId,
  );
  EntriesTableData copyWithCompanion(EntriesTableCompanion data) {
    return EntriesTableData(
      id: data.id.present ? data.id.value : this.id,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
      uri: data.uri.present ? data.uri.value : this.uri,
      path: data.path.present ? data.path.value : this.path,
      sourceMimeType: data.sourceMimeType.present
          ? data.sourceMimeType.value
          : this.sourceMimeType,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      sourceRotationDegrees: data.sourceRotationDegrees.present
          ? data.sourceRotationDegrees.value
          : this.sourceRotationDegrees,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      title: data.title.present ? data.title.value : this.title,
      dateAddedSecs: data.dateAddedSecs.present
          ? data.dateAddedSecs.value
          : this.dateAddedSecs,
      dateModifiedMillis: data.dateModifiedMillis.present
          ? data.dateModifiedMillis.value
          : this.dateModifiedMillis,
      sourceDateTakenMillis: data.sourceDateTakenMillis.present
          ? data.sourceDateTakenMillis.value
          : this.sourceDateTakenMillis,
      durationMillis: data.durationMillis.present
          ? data.durationMillis.value
          : this.durationMillis,
      trashed: data.trashed.present ? data.trashed.value : this.trashed,
      origin: data.origin.present ? data.origin.value : this.origin,
      directory: data.directory.present ? data.directory.value : this.directory,
      baseName: data.baseName.present ? data.baseName.value : this.baseName,
      stackKey: data.stackKey.present ? data.stackKey.value : this.stackKey,
      stackTileId: data.stackTileId.present
          ? data.stackTileId.value
          : this.stackTileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntriesTableData(')
          ..write('id: $id, ')
          ..write('contentId: $contentId, ')
          ..write('uri: $uri, ')
          ..write('path: $path, ')
          ..write('sourceMimeType: $sourceMimeType, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('sourceRotationDegrees: $sourceRotationDegrees, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('title: $title, ')
          ..write('dateAddedSecs: $dateAddedSecs, ')
          ..write('dateModifiedMillis: $dateModifiedMillis, ')
          ..write('sourceDateTakenMillis: $sourceDateTakenMillis, ')
          ..write('durationMillis: $durationMillis, ')
          ..write('trashed: $trashed, ')
          ..write('origin: $origin, ')
          ..write('directory: $directory, ')
          ..write('baseName: $baseName, ')
          ..write('stackKey: $stackKey, ')
          ..write('stackTileId: $stackTileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    contentId,
    uri,
    path,
    sourceMimeType,
    width,
    height,
    sourceRotationDegrees,
    sizeBytes,
    title,
    dateAddedSecs,
    dateModifiedMillis,
    sourceDateTakenMillis,
    durationMillis,
    trashed,
    origin,
    directory,
    baseName,
    stackKey,
    stackTileId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntriesTableData &&
          other.id == this.id &&
          other.contentId == this.contentId &&
          other.uri == this.uri &&
          other.path == this.path &&
          other.sourceMimeType == this.sourceMimeType &&
          other.width == this.width &&
          other.height == this.height &&
          other.sourceRotationDegrees == this.sourceRotationDegrees &&
          other.sizeBytes == this.sizeBytes &&
          other.title == this.title &&
          other.dateAddedSecs == this.dateAddedSecs &&
          other.dateModifiedMillis == this.dateModifiedMillis &&
          other.sourceDateTakenMillis == this.sourceDateTakenMillis &&
          other.durationMillis == this.durationMillis &&
          other.trashed == this.trashed &&
          other.origin == this.origin &&
          other.directory == this.directory &&
          other.baseName == this.baseName &&
          other.stackKey == this.stackKey &&
          other.stackTileId == this.stackTileId);
}

class EntriesTableCompanion extends UpdateCompanion<EntriesTableData> {
  final Value<int> id;
  final Value<int?> contentId;
  final Value<String?> uri;
  final Value<String?> path;
  final Value<String?> sourceMimeType;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> sourceRotationDegrees;
  final Value<int?> sizeBytes;
  final Value<String?> title;
  final Value<int?> dateAddedSecs;
  final Value<int?> dateModifiedMillis;
  final Value<int?> sourceDateTakenMillis;
  final Value<int?> durationMillis;
  final Value<int?> trashed;
  final Value<int?> origin;
  final Value<String?> directory;
  final Value<String?> baseName;
  final Value<String?> stackKey;
  final Value<int?> stackTileId;
  const EntriesTableCompanion({
    this.id = const Value.absent(),
    this.contentId = const Value.absent(),
    this.uri = const Value.absent(),
    this.path = const Value.absent(),
    this.sourceMimeType = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.sourceRotationDegrees = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.title = const Value.absent(),
    this.dateAddedSecs = const Value.absent(),
    this.dateModifiedMillis = const Value.absent(),
    this.sourceDateTakenMillis = const Value.absent(),
    this.durationMillis = const Value.absent(),
    this.trashed = const Value.absent(),
    this.origin = const Value.absent(),
    this.directory = const Value.absent(),
    this.baseName = const Value.absent(),
    this.stackKey = const Value.absent(),
    this.stackTileId = const Value.absent(),
  });
  EntriesTableCompanion.insert({
    this.id = const Value.absent(),
    this.contentId = const Value.absent(),
    this.uri = const Value.absent(),
    this.path = const Value.absent(),
    this.sourceMimeType = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.sourceRotationDegrees = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.title = const Value.absent(),
    this.dateAddedSecs = const Value.absent(),
    this.dateModifiedMillis = const Value.absent(),
    this.sourceDateTakenMillis = const Value.absent(),
    this.durationMillis = const Value.absent(),
    this.trashed = const Value.absent(),
    this.origin = const Value.absent(),
    this.directory = const Value.absent(),
    this.baseName = const Value.absent(),
    this.stackKey = const Value.absent(),
    this.stackTileId = const Value.absent(),
  });
  static Insertable<EntriesTableData> custom({
    Expression<int>? id,
    Expression<int>? contentId,
    Expression<String>? uri,
    Expression<String>? path,
    Expression<String>? sourceMimeType,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? sourceRotationDegrees,
    Expression<int>? sizeBytes,
    Expression<String>? title,
    Expression<int>? dateAddedSecs,
    Expression<int>? dateModifiedMillis,
    Expression<int>? sourceDateTakenMillis,
    Expression<int>? durationMillis,
    Expression<int>? trashed,
    Expression<int>? origin,
    Expression<String>? directory,
    Expression<String>? baseName,
    Expression<String>? stackKey,
    Expression<int>? stackTileId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contentId != null) 'contentId': contentId,
      if (uri != null) 'uri': uri,
      if (path != null) 'path': path,
      if (sourceMimeType != null) 'sourceMimeType': sourceMimeType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (sourceRotationDegrees != null)
        'sourceRotationDegrees': sourceRotationDegrees,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (title != null) 'title': title,
      if (dateAddedSecs != null) 'dateAddedSecs': dateAddedSecs,
      if (dateModifiedMillis != null) 'dateModifiedMillis': dateModifiedMillis,
      if (sourceDateTakenMillis != null)
        'sourceDateTakenMillis': sourceDateTakenMillis,
      if (durationMillis != null) 'durationMillis': durationMillis,
      if (trashed != null) 'trashed': trashed,
      if (origin != null) 'origin': origin,
      if (directory != null) 'directory': directory,
      if (baseName != null) 'baseName': baseName,
      if (stackKey != null) 'stackKey': stackKey,
      if (stackTileId != null) 'stackTileId': stackTileId,
    });
  }

  EntriesTableCompanion copyWith({
    Value<int>? id,
    Value<int?>? contentId,
    Value<String?>? uri,
    Value<String?>? path,
    Value<String?>? sourceMimeType,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? sourceRotationDegrees,
    Value<int?>? sizeBytes,
    Value<String?>? title,
    Value<int?>? dateAddedSecs,
    Value<int?>? dateModifiedMillis,
    Value<int?>? sourceDateTakenMillis,
    Value<int?>? durationMillis,
    Value<int?>? trashed,
    Value<int?>? origin,
    Value<String?>? directory,
    Value<String?>? baseName,
    Value<String?>? stackKey,
    Value<int?>? stackTileId,
  }) {
    return EntriesTableCompanion(
      id: id ?? this.id,
      contentId: contentId ?? this.contentId,
      uri: uri ?? this.uri,
      path: path ?? this.path,
      sourceMimeType: sourceMimeType ?? this.sourceMimeType,
      width: width ?? this.width,
      height: height ?? this.height,
      sourceRotationDegrees:
          sourceRotationDegrees ?? this.sourceRotationDegrees,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      title: title ?? this.title,
      dateAddedSecs: dateAddedSecs ?? this.dateAddedSecs,
      dateModifiedMillis: dateModifiedMillis ?? this.dateModifiedMillis,
      sourceDateTakenMillis:
          sourceDateTakenMillis ?? this.sourceDateTakenMillis,
      durationMillis: durationMillis ?? this.durationMillis,
      trashed: trashed ?? this.trashed,
      origin: origin ?? this.origin,
      directory: directory ?? this.directory,
      baseName: baseName ?? this.baseName,
      stackKey: stackKey ?? this.stackKey,
      stackTileId: stackTileId ?? this.stackTileId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (contentId.present) {
      map['contentId'] = Variable<int>(contentId.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sourceMimeType.present) {
      map['sourceMimeType'] = Variable<String>(sourceMimeType.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (sourceRotationDegrees.present) {
      map['sourceRotationDegrees'] = Variable<int>(sourceRotationDegrees.value);
    }
    if (sizeBytes.present) {
      map['sizeBytes'] = Variable<int>(sizeBytes.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (dateAddedSecs.present) {
      map['dateAddedSecs'] = Variable<int>(dateAddedSecs.value);
    }
    if (dateModifiedMillis.present) {
      map['dateModifiedMillis'] = Variable<int>(dateModifiedMillis.value);
    }
    if (sourceDateTakenMillis.present) {
      map['sourceDateTakenMillis'] = Variable<int>(sourceDateTakenMillis.value);
    }
    if (durationMillis.present) {
      map['durationMillis'] = Variable<int>(durationMillis.value);
    }
    if (trashed.present) {
      map['trashed'] = Variable<int>(trashed.value);
    }
    if (origin.present) {
      map['origin'] = Variable<int>(origin.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (baseName.present) {
      map['baseName'] = Variable<String>(baseName.value);
    }
    if (stackKey.present) {
      map['stackKey'] = Variable<String>(stackKey.value);
    }
    if (stackTileId.present) {
      map['stackTileId'] = Variable<int>(stackTileId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesTableCompanion(')
          ..write('id: $id, ')
          ..write('contentId: $contentId, ')
          ..write('uri: $uri, ')
          ..write('path: $path, ')
          ..write('sourceMimeType: $sourceMimeType, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('sourceRotationDegrees: $sourceRotationDegrees, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('title: $title, ')
          ..write('dateAddedSecs: $dateAddedSecs, ')
          ..write('dateModifiedMillis: $dateModifiedMillis, ')
          ..write('sourceDateTakenMillis: $sourceDateTakenMillis, ')
          ..write('durationMillis: $durationMillis, ')
          ..write('trashed: $trashed, ')
          ..write('origin: $origin, ')
          ..write('directory: $directory, ')
          ..write('baseName: $baseName, ')
          ..write('stackKey: $stackKey, ')
          ..write('stackTileId: $stackTileId')
          ..write(')'))
        .toString();
  }
}

class $DateTakenTableTable extends DateTakenTable
    with TableInfo<$DateTakenTableTable, DateTakenTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DateTakenTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMillisMeta = const VerificationMeta(
    'dateMillis',
  );
  @override
  late final GeneratedColumn<int> dateMillis = GeneratedColumn<int>(
    'dateMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dateMillis];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dateTaken';
  @override
  VerificationContext validateIntegrity(
    Insertable<DateTakenTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('dateMillis')) {
      context.handle(
        _dateMillisMeta,
        dateMillis.isAcceptableOrUnknown(data['dateMillis']!, _dateMillisMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DateTakenTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DateTakenTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dateMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dateMillis'],
      ),
    );
  }

  @override
  $DateTakenTableTable createAlias(String alias) {
    return $DateTakenTableTable(attachedDatabase, alias);
  }
}

class DateTakenTableData extends DataClass
    implements Insertable<DateTakenTableData> {
  final int id;
  final int? dateMillis;
  const DateTakenTableData({required this.id, this.dateMillis});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || dateMillis != null) {
      map['dateMillis'] = Variable<int>(dateMillis);
    }
    return map;
  }

  DateTakenTableCompanion toCompanion(bool nullToAbsent) {
    return DateTakenTableCompanion(
      id: Value(id),
      dateMillis: dateMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(dateMillis),
    );
  }

  factory DateTakenTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DateTakenTableData(
      id: serializer.fromJson<int>(json['id']),
      dateMillis: serializer.fromJson<int?>(json['dateMillis']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dateMillis': serializer.toJson<int?>(dateMillis),
    };
  }

  DateTakenTableData copyWith({
    int? id,
    Value<int?> dateMillis = const Value.absent(),
  }) => DateTakenTableData(
    id: id ?? this.id,
    dateMillis: dateMillis.present ? dateMillis.value : this.dateMillis,
  );
  DateTakenTableData copyWithCompanion(DateTakenTableCompanion data) {
    return DateTakenTableData(
      id: data.id.present ? data.id.value : this.id,
      dateMillis: data.dateMillis.present
          ? data.dateMillis.value
          : this.dateMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DateTakenTableData(')
          ..write('id: $id, ')
          ..write('dateMillis: $dateMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dateMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DateTakenTableData &&
          other.id == this.id &&
          other.dateMillis == this.dateMillis);
}

class DateTakenTableCompanion extends UpdateCompanion<DateTakenTableData> {
  final Value<int> id;
  final Value<int?> dateMillis;
  const DateTakenTableCompanion({
    this.id = const Value.absent(),
    this.dateMillis = const Value.absent(),
  });
  DateTakenTableCompanion.insert({
    this.id = const Value.absent(),
    this.dateMillis = const Value.absent(),
  });
  static Insertable<DateTakenTableData> custom({
    Expression<int>? id,
    Expression<int>? dateMillis,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dateMillis != null) 'dateMillis': dateMillis,
    });
  }

  DateTakenTableCompanion copyWith({Value<int>? id, Value<int?>? dateMillis}) {
    return DateTakenTableCompanion(
      id: id ?? this.id,
      dateMillis: dateMillis ?? this.dateMillis,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dateMillis.present) {
      map['dateMillis'] = Variable<int>(dateMillis.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DateTakenTableCompanion(')
          ..write('id: $id, ')
          ..write('dateMillis: $dateMillis')
          ..write(')'))
        .toString();
  }
}

class $MetadataTableTable extends MetadataTable
    with TableInfo<$MetadataTableTable, MetadataTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetadataTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mimeType',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMillisMeta = const VerificationMeta(
    'dateMillis',
  );
  @override
  late final GeneratedColumn<int> dateMillis = GeneratedColumn<int>(
    'dateMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
    'flags',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rotationDegreesMeta = const VerificationMeta(
    'rotationDegrees',
  );
  @override
  late final GeneratedColumn<int> rotationDegrees = GeneratedColumn<int>(
    'rotationDegrees',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _xmpSubjectsMeta = const VerificationMeta(
    'xmpSubjects',
  );
  @override
  late final GeneratedColumn<String> xmpSubjects = GeneratedColumn<String>(
    'xmpSubjects',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _xmpTitleMeta = const VerificationMeta(
    'xmpTitle',
  );
  @override
  late final GeneratedColumn<String> xmpTitle = GeneratedColumn<String>(
    'xmpTitle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mimeType,
    dateMillis,
    flags,
    rotationDegrees,
    xmpSubjects,
    xmpTitle,
    latitude,
    longitude,
    rating,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetadataTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('mimeType')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mimeType']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('dateMillis')) {
      context.handle(
        _dateMillisMeta,
        dateMillis.isAcceptableOrUnknown(data['dateMillis']!, _dateMillisMeta),
      );
    }
    if (data.containsKey('flags')) {
      context.handle(
        _flagsMeta,
        flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta),
      );
    }
    if (data.containsKey('rotationDegrees')) {
      context.handle(
        _rotationDegreesMeta,
        rotationDegrees.isAcceptableOrUnknown(
          data['rotationDegrees']!,
          _rotationDegreesMeta,
        ),
      );
    }
    if (data.containsKey('xmpSubjects')) {
      context.handle(
        _xmpSubjectsMeta,
        xmpSubjects.isAcceptableOrUnknown(
          data['xmpSubjects']!,
          _xmpSubjectsMeta,
        ),
      );
    }
    if (data.containsKey('xmpTitle')) {
      context.handle(
        _xmpTitleMeta,
        xmpTitle.isAcceptableOrUnknown(data['xmpTitle']!, _xmpTitleMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MetadataTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetadataTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mimeType'],
      ),
      dateMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dateMillis'],
      ),
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      ),
      rotationDegrees: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rotationDegrees'],
      ),
      xmpSubjects: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xmpSubjects'],
      ),
      xmpTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xmpTitle'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
    );
  }

  @override
  $MetadataTableTable createAlias(String alias) {
    return $MetadataTableTable(attachedDatabase, alias);
  }
}

class MetadataTableData extends DataClass
    implements Insertable<MetadataTableData> {
  final int id;
  final String? mimeType;
  final int? dateMillis;
  final int? flags;
  final int? rotationDegrees;
  final String? xmpSubjects;
  final String? xmpTitle;
  final double? latitude;
  final double? longitude;
  final int? rating;
  const MetadataTableData({
    required this.id,
    this.mimeType,
    this.dateMillis,
    this.flags,
    this.rotationDegrees,
    this.xmpSubjects,
    this.xmpTitle,
    this.latitude,
    this.longitude,
    this.rating,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mimeType != null) {
      map['mimeType'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || dateMillis != null) {
      map['dateMillis'] = Variable<int>(dateMillis);
    }
    if (!nullToAbsent || flags != null) {
      map['flags'] = Variable<int>(flags);
    }
    if (!nullToAbsent || rotationDegrees != null) {
      map['rotationDegrees'] = Variable<int>(rotationDegrees);
    }
    if (!nullToAbsent || xmpSubjects != null) {
      map['xmpSubjects'] = Variable<String>(xmpSubjects);
    }
    if (!nullToAbsent || xmpTitle != null) {
      map['xmpTitle'] = Variable<String>(xmpTitle);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    return map;
  }

  MetadataTableCompanion toCompanion(bool nullToAbsent) {
    return MetadataTableCompanion(
      id: Value(id),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      dateMillis: dateMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(dateMillis),
      flags: flags == null && nullToAbsent
          ? const Value.absent()
          : Value(flags),
      rotationDegrees: rotationDegrees == null && nullToAbsent
          ? const Value.absent()
          : Value(rotationDegrees),
      xmpSubjects: xmpSubjects == null && nullToAbsent
          ? const Value.absent()
          : Value(xmpSubjects),
      xmpTitle: xmpTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(xmpTitle),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
    );
  }

  factory MetadataTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetadataTableData(
      id: serializer.fromJson<int>(json['id']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      dateMillis: serializer.fromJson<int?>(json['dateMillis']),
      flags: serializer.fromJson<int?>(json['flags']),
      rotationDegrees: serializer.fromJson<int?>(json['rotationDegrees']),
      xmpSubjects: serializer.fromJson<String?>(json['xmpSubjects']),
      xmpTitle: serializer.fromJson<String?>(json['xmpTitle']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      rating: serializer.fromJson<int?>(json['rating']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mimeType': serializer.toJson<String?>(mimeType),
      'dateMillis': serializer.toJson<int?>(dateMillis),
      'flags': serializer.toJson<int?>(flags),
      'rotationDegrees': serializer.toJson<int?>(rotationDegrees),
      'xmpSubjects': serializer.toJson<String?>(xmpSubjects),
      'xmpTitle': serializer.toJson<String?>(xmpTitle),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'rating': serializer.toJson<int?>(rating),
    };
  }

  MetadataTableData copyWith({
    int? id,
    Value<String?> mimeType = const Value.absent(),
    Value<int?> dateMillis = const Value.absent(),
    Value<int?> flags = const Value.absent(),
    Value<int?> rotationDegrees = const Value.absent(),
    Value<String?> xmpSubjects = const Value.absent(),
    Value<String?> xmpTitle = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<int?> rating = const Value.absent(),
  }) => MetadataTableData(
    id: id ?? this.id,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    dateMillis: dateMillis.present ? dateMillis.value : this.dateMillis,
    flags: flags.present ? flags.value : this.flags,
    rotationDegrees: rotationDegrees.present
        ? rotationDegrees.value
        : this.rotationDegrees,
    xmpSubjects: xmpSubjects.present ? xmpSubjects.value : this.xmpSubjects,
    xmpTitle: xmpTitle.present ? xmpTitle.value : this.xmpTitle,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    rating: rating.present ? rating.value : this.rating,
  );
  MetadataTableData copyWithCompanion(MetadataTableCompanion data) {
    return MetadataTableData(
      id: data.id.present ? data.id.value : this.id,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      dateMillis: data.dateMillis.present
          ? data.dateMillis.value
          : this.dateMillis,
      flags: data.flags.present ? data.flags.value : this.flags,
      rotationDegrees: data.rotationDegrees.present
          ? data.rotationDegrees.value
          : this.rotationDegrees,
      xmpSubjects: data.xmpSubjects.present
          ? data.xmpSubjects.value
          : this.xmpSubjects,
      xmpTitle: data.xmpTitle.present ? data.xmpTitle.value : this.xmpTitle,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      rating: data.rating.present ? data.rating.value : this.rating,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetadataTableData(')
          ..write('id: $id, ')
          ..write('mimeType: $mimeType, ')
          ..write('dateMillis: $dateMillis, ')
          ..write('flags: $flags, ')
          ..write('rotationDegrees: $rotationDegrees, ')
          ..write('xmpSubjects: $xmpSubjects, ')
          ..write('xmpTitle: $xmpTitle, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rating: $rating')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mimeType,
    dateMillis,
    flags,
    rotationDegrees,
    xmpSubjects,
    xmpTitle,
    latitude,
    longitude,
    rating,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetadataTableData &&
          other.id == this.id &&
          other.mimeType == this.mimeType &&
          other.dateMillis == this.dateMillis &&
          other.flags == this.flags &&
          other.rotationDegrees == this.rotationDegrees &&
          other.xmpSubjects == this.xmpSubjects &&
          other.xmpTitle == this.xmpTitle &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.rating == this.rating);
}

class MetadataTableCompanion extends UpdateCompanion<MetadataTableData> {
  final Value<int> id;
  final Value<String?> mimeType;
  final Value<int?> dateMillis;
  final Value<int?> flags;
  final Value<int?> rotationDegrees;
  final Value<String?> xmpSubjects;
  final Value<String?> xmpTitle;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<int?> rating;
  const MetadataTableCompanion({
    this.id = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.dateMillis = const Value.absent(),
    this.flags = const Value.absent(),
    this.rotationDegrees = const Value.absent(),
    this.xmpSubjects = const Value.absent(),
    this.xmpTitle = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rating = const Value.absent(),
  });
  MetadataTableCompanion.insert({
    this.id = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.dateMillis = const Value.absent(),
    this.flags = const Value.absent(),
    this.rotationDegrees = const Value.absent(),
    this.xmpSubjects = const Value.absent(),
    this.xmpTitle = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rating = const Value.absent(),
  });
  static Insertable<MetadataTableData> custom({
    Expression<int>? id,
    Expression<String>? mimeType,
    Expression<int>? dateMillis,
    Expression<int>? flags,
    Expression<int>? rotationDegrees,
    Expression<String>? xmpSubjects,
    Expression<String>? xmpTitle,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? rating,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mimeType != null) 'mimeType': mimeType,
      if (dateMillis != null) 'dateMillis': dateMillis,
      if (flags != null) 'flags': flags,
      if (rotationDegrees != null) 'rotationDegrees': rotationDegrees,
      if (xmpSubjects != null) 'xmpSubjects': xmpSubjects,
      if (xmpTitle != null) 'xmpTitle': xmpTitle,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (rating != null) 'rating': rating,
    });
  }

  MetadataTableCompanion copyWith({
    Value<int>? id,
    Value<String?>? mimeType,
    Value<int?>? dateMillis,
    Value<int?>? flags,
    Value<int?>? rotationDegrees,
    Value<String?>? xmpSubjects,
    Value<String?>? xmpTitle,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<int?>? rating,
  }) {
    return MetadataTableCompanion(
      id: id ?? this.id,
      mimeType: mimeType ?? this.mimeType,
      dateMillis: dateMillis ?? this.dateMillis,
      flags: flags ?? this.flags,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      xmpSubjects: xmpSubjects ?? this.xmpSubjects,
      xmpTitle: xmpTitle ?? this.xmpTitle,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rating: rating ?? this.rating,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mimeType.present) {
      map['mimeType'] = Variable<String>(mimeType.value);
    }
    if (dateMillis.present) {
      map['dateMillis'] = Variable<int>(dateMillis.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (rotationDegrees.present) {
      map['rotationDegrees'] = Variable<int>(rotationDegrees.value);
    }
    if (xmpSubjects.present) {
      map['xmpSubjects'] = Variable<String>(xmpSubjects.value);
    }
    if (xmpTitle.present) {
      map['xmpTitle'] = Variable<String>(xmpTitle.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetadataTableCompanion(')
          ..write('id: $id, ')
          ..write('mimeType: $mimeType, ')
          ..write('dateMillis: $dateMillis, ')
          ..write('flags: $flags, ')
          ..write('rotationDegrees: $rotationDegrees, ')
          ..write('xmpSubjects: $xmpSubjects, ')
          ..write('xmpTitle: $xmpTitle, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rating: $rating')
          ..write(')'))
        .toString();
  }
}

class $AddressesTableTable extends AddressesTable
    with TableInfo<$AddressesTableTable, AddressesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddressesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressLineMeta = const VerificationMeta(
    'addressLine',
  );
  @override
  late final GeneratedColumn<String> addressLine = GeneratedColumn<String>(
    'addressLine',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countryCodeMeta = const VerificationMeta(
    'countryCode',
  );
  @override
  late final GeneratedColumn<String> countryCode = GeneratedColumn<String>(
    'countryCode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countryNameMeta = const VerificationMeta(
    'countryName',
  );
  @override
  late final GeneratedColumn<String> countryName = GeneratedColumn<String>(
    'countryName',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _adminAreaMeta = const VerificationMeta(
    'adminArea',
  );
  @override
  late final GeneratedColumn<String> adminArea = GeneratedColumn<String>(
    'adminArea',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localityMeta = const VerificationMeta(
    'locality',
  );
  @override
  late final GeneratedColumn<String> locality = GeneratedColumn<String>(
    'locality',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    addressLine,
    countryCode,
    countryName,
    adminArea,
    locality,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'address';
  @override
  VerificationContext validateIntegrity(
    Insertable<AddressesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('addressLine')) {
      context.handle(
        _addressLineMeta,
        addressLine.isAcceptableOrUnknown(
          data['addressLine']!,
          _addressLineMeta,
        ),
      );
    }
    if (data.containsKey('countryCode')) {
      context.handle(
        _countryCodeMeta,
        countryCode.isAcceptableOrUnknown(
          data['countryCode']!,
          _countryCodeMeta,
        ),
      );
    }
    if (data.containsKey('countryName')) {
      context.handle(
        _countryNameMeta,
        countryName.isAcceptableOrUnknown(
          data['countryName']!,
          _countryNameMeta,
        ),
      );
    }
    if (data.containsKey('adminArea')) {
      context.handle(
        _adminAreaMeta,
        adminArea.isAcceptableOrUnknown(data['adminArea']!, _adminAreaMeta),
      );
    }
    if (data.containsKey('locality')) {
      context.handle(
        _localityMeta,
        locality.isAcceptableOrUnknown(data['locality']!, _localityMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AddressesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AddressesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      addressLine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addressLine'],
      ),
      countryCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}countryCode'],
      ),
      countryName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}countryName'],
      ),
      adminArea: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}adminArea'],
      ),
      locality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locality'],
      ),
    );
  }

  @override
  $AddressesTableTable createAlias(String alias) {
    return $AddressesTableTable(attachedDatabase, alias);
  }
}

class AddressesTableData extends DataClass
    implements Insertable<AddressesTableData> {
  final int id;
  final String? addressLine;
  final String? countryCode;
  final String? countryName;
  final String? adminArea;
  final String? locality;
  const AddressesTableData({
    required this.id,
    this.addressLine,
    this.countryCode,
    this.countryName,
    this.adminArea,
    this.locality,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || addressLine != null) {
      map['addressLine'] = Variable<String>(addressLine);
    }
    if (!nullToAbsent || countryCode != null) {
      map['countryCode'] = Variable<String>(countryCode);
    }
    if (!nullToAbsent || countryName != null) {
      map['countryName'] = Variable<String>(countryName);
    }
    if (!nullToAbsent || adminArea != null) {
      map['adminArea'] = Variable<String>(adminArea);
    }
    if (!nullToAbsent || locality != null) {
      map['locality'] = Variable<String>(locality);
    }
    return map;
  }

  AddressesTableCompanion toCompanion(bool nullToAbsent) {
    return AddressesTableCompanion(
      id: Value(id),
      addressLine: addressLine == null && nullToAbsent
          ? const Value.absent()
          : Value(addressLine),
      countryCode: countryCode == null && nullToAbsent
          ? const Value.absent()
          : Value(countryCode),
      countryName: countryName == null && nullToAbsent
          ? const Value.absent()
          : Value(countryName),
      adminArea: adminArea == null && nullToAbsent
          ? const Value.absent()
          : Value(adminArea),
      locality: locality == null && nullToAbsent
          ? const Value.absent()
          : Value(locality),
    );
  }

  factory AddressesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AddressesTableData(
      id: serializer.fromJson<int>(json['id']),
      addressLine: serializer.fromJson<String?>(json['addressLine']),
      countryCode: serializer.fromJson<String?>(json['countryCode']),
      countryName: serializer.fromJson<String?>(json['countryName']),
      adminArea: serializer.fromJson<String?>(json['adminArea']),
      locality: serializer.fromJson<String?>(json['locality']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'addressLine': serializer.toJson<String?>(addressLine),
      'countryCode': serializer.toJson<String?>(countryCode),
      'countryName': serializer.toJson<String?>(countryName),
      'adminArea': serializer.toJson<String?>(adminArea),
      'locality': serializer.toJson<String?>(locality),
    };
  }

  AddressesTableData copyWith({
    int? id,
    Value<String?> addressLine = const Value.absent(),
    Value<String?> countryCode = const Value.absent(),
    Value<String?> countryName = const Value.absent(),
    Value<String?> adminArea = const Value.absent(),
    Value<String?> locality = const Value.absent(),
  }) => AddressesTableData(
    id: id ?? this.id,
    addressLine: addressLine.present ? addressLine.value : this.addressLine,
    countryCode: countryCode.present ? countryCode.value : this.countryCode,
    countryName: countryName.present ? countryName.value : this.countryName,
    adminArea: adminArea.present ? adminArea.value : this.adminArea,
    locality: locality.present ? locality.value : this.locality,
  );
  AddressesTableData copyWithCompanion(AddressesTableCompanion data) {
    return AddressesTableData(
      id: data.id.present ? data.id.value : this.id,
      addressLine: data.addressLine.present
          ? data.addressLine.value
          : this.addressLine,
      countryCode: data.countryCode.present
          ? data.countryCode.value
          : this.countryCode,
      countryName: data.countryName.present
          ? data.countryName.value
          : this.countryName,
      adminArea: data.adminArea.present ? data.adminArea.value : this.adminArea,
      locality: data.locality.present ? data.locality.value : this.locality,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AddressesTableData(')
          ..write('id: $id, ')
          ..write('addressLine: $addressLine, ')
          ..write('countryCode: $countryCode, ')
          ..write('countryName: $countryName, ')
          ..write('adminArea: $adminArea, ')
          ..write('locality: $locality')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    addressLine,
    countryCode,
    countryName,
    adminArea,
    locality,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddressesTableData &&
          other.id == this.id &&
          other.addressLine == this.addressLine &&
          other.countryCode == this.countryCode &&
          other.countryName == this.countryName &&
          other.adminArea == this.adminArea &&
          other.locality == this.locality);
}

class AddressesTableCompanion extends UpdateCompanion<AddressesTableData> {
  final Value<int> id;
  final Value<String?> addressLine;
  final Value<String?> countryCode;
  final Value<String?> countryName;
  final Value<String?> adminArea;
  final Value<String?> locality;
  const AddressesTableCompanion({
    this.id = const Value.absent(),
    this.addressLine = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.countryName = const Value.absent(),
    this.adminArea = const Value.absent(),
    this.locality = const Value.absent(),
  });
  AddressesTableCompanion.insert({
    this.id = const Value.absent(),
    this.addressLine = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.countryName = const Value.absent(),
    this.adminArea = const Value.absent(),
    this.locality = const Value.absent(),
  });
  static Insertable<AddressesTableData> custom({
    Expression<int>? id,
    Expression<String>? addressLine,
    Expression<String>? countryCode,
    Expression<String>? countryName,
    Expression<String>? adminArea,
    Expression<String>? locality,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (addressLine != null) 'addressLine': addressLine,
      if (countryCode != null) 'countryCode': countryCode,
      if (countryName != null) 'countryName': countryName,
      if (adminArea != null) 'adminArea': adminArea,
      if (locality != null) 'locality': locality,
    });
  }

  AddressesTableCompanion copyWith({
    Value<int>? id,
    Value<String?>? addressLine,
    Value<String?>? countryCode,
    Value<String?>? countryName,
    Value<String?>? adminArea,
    Value<String?>? locality,
  }) {
    return AddressesTableCompanion(
      id: id ?? this.id,
      addressLine: addressLine ?? this.addressLine,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      adminArea: adminArea ?? this.adminArea,
      locality: locality ?? this.locality,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (addressLine.present) {
      map['addressLine'] = Variable<String>(addressLine.value);
    }
    if (countryCode.present) {
      map['countryCode'] = Variable<String>(countryCode.value);
    }
    if (countryName.present) {
      map['countryName'] = Variable<String>(countryName.value);
    }
    if (adminArea.present) {
      map['adminArea'] = Variable<String>(adminArea.value);
    }
    if (locality.present) {
      map['locality'] = Variable<String>(locality.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddressesTableCompanion(')
          ..write('id: $id, ')
          ..write('addressLine: $addressLine, ')
          ..write('countryCode: $countryCode, ')
          ..write('countryName: $countryName, ')
          ..write('adminArea: $adminArea, ')
          ..write('locality: $locality')
          ..write(')'))
        .toString();
  }
}

class $FavouritesTableTable extends FavouritesTable
    with TableInfo<$FavouritesTableTable, FavouritesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavouritesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favourites';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavouritesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FavouritesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavouritesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
    );
  }

  @override
  $FavouritesTableTable createAlias(String alias) {
    return $FavouritesTableTable(attachedDatabase, alias);
  }
}

class FavouritesTableData extends DataClass
    implements Insertable<FavouritesTableData> {
  final int id;
  const FavouritesTableData({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  FavouritesTableCompanion toCompanion(bool nullToAbsent) {
    return FavouritesTableCompanion(id: Value(id));
  }

  factory FavouritesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavouritesTableData(id: serializer.fromJson<int>(json['id']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'id': serializer.toJson<int>(id)};
  }

  FavouritesTableData copyWith({int? id}) =>
      FavouritesTableData(id: id ?? this.id);
  FavouritesTableData copyWithCompanion(FavouritesTableCompanion data) {
    return FavouritesTableData(id: data.id.present ? data.id.value : this.id);
  }

  @override
  String toString() {
    return (StringBuffer('FavouritesTableData(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavouritesTableData && other.id == this.id);
}

class FavouritesTableCompanion extends UpdateCompanion<FavouritesTableData> {
  final Value<int> id;
  const FavouritesTableCompanion({this.id = const Value.absent()});
  FavouritesTableCompanion.insert({this.id = const Value.absent()});
  static Insertable<FavouritesTableData> custom({Expression<int>? id}) {
    return RawValuesInsertable({if (id != null) 'id': id});
  }

  FavouritesTableCompanion copyWith({Value<int>? id}) {
    return FavouritesTableCompanion(id: id ?? this.id);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavouritesTableCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $CoversTableTable extends CoversTable
    with TableInfo<$CoversTableTable, CoversTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoversTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _filterMeta = const VerificationMeta('filter');
  @override
  late final GeneratedColumn<String> filter = GeneratedColumn<String>(
    'filter',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entryId',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packageNameMeta = const VerificationMeta(
    'packageName',
  );
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
    'packageName',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [filter, entryId, packageName, color];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'covers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoversTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('filter')) {
      context.handle(
        _filterMeta,
        filter.isAcceptableOrUnknown(data['filter']!, _filterMeta),
      );
    } else if (isInserting) {
      context.missing(_filterMeta);
    }
    if (data.containsKey('entryId')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entryId']!, _entryIdMeta),
      );
    }
    if (data.containsKey('packageName')) {
      context.handle(
        _packageNameMeta,
        packageName.isAcceptableOrUnknown(
          data['packageName']!,
          _packageNameMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {filter};
  @override
  CoversTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoversTableData(
      filter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entryId'],
      ),
      packageName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}packageName'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
    );
  }

  @override
  $CoversTableTable createAlias(String alias) {
    return $CoversTableTable(attachedDatabase, alias);
  }
}

class CoversTableData extends DataClass implements Insertable<CoversTableData> {
  final String filter;
  final int? entryId;
  final String? packageName;
  final String? color;
  const CoversTableData({
    required this.filter,
    this.entryId,
    this.packageName,
    this.color,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['filter'] = Variable<String>(filter);
    if (!nullToAbsent || entryId != null) {
      map['entryId'] = Variable<int>(entryId);
    }
    if (!nullToAbsent || packageName != null) {
      map['packageName'] = Variable<String>(packageName);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    return map;
  }

  CoversTableCompanion toCompanion(bool nullToAbsent) {
    return CoversTableCompanion(
      filter: Value(filter),
      entryId: entryId == null && nullToAbsent
          ? const Value.absent()
          : Value(entryId),
      packageName: packageName == null && nullToAbsent
          ? const Value.absent()
          : Value(packageName),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
    );
  }

  factory CoversTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoversTableData(
      filter: serializer.fromJson<String>(json['filter']),
      entryId: serializer.fromJson<int?>(json['entryId']),
      packageName: serializer.fromJson<String?>(json['packageName']),
      color: serializer.fromJson<String?>(json['color']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'filter': serializer.toJson<String>(filter),
      'entryId': serializer.toJson<int?>(entryId),
      'packageName': serializer.toJson<String?>(packageName),
      'color': serializer.toJson<String?>(color),
    };
  }

  CoversTableData copyWith({
    String? filter,
    Value<int?> entryId = const Value.absent(),
    Value<String?> packageName = const Value.absent(),
    Value<String?> color = const Value.absent(),
  }) => CoversTableData(
    filter: filter ?? this.filter,
    entryId: entryId.present ? entryId.value : this.entryId,
    packageName: packageName.present ? packageName.value : this.packageName,
    color: color.present ? color.value : this.color,
  );
  CoversTableData copyWithCompanion(CoversTableCompanion data) {
    return CoversTableData(
      filter: data.filter.present ? data.filter.value : this.filter,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      packageName: data.packageName.present
          ? data.packageName.value
          : this.packageName,
      color: data.color.present ? data.color.value : this.color,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoversTableData(')
          ..write('filter: $filter, ')
          ..write('entryId: $entryId, ')
          ..write('packageName: $packageName, ')
          ..write('color: $color')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(filter, entryId, packageName, color);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoversTableData &&
          other.filter == this.filter &&
          other.entryId == this.entryId &&
          other.packageName == this.packageName &&
          other.color == this.color);
}

class CoversTableCompanion extends UpdateCompanion<CoversTableData> {
  final Value<String> filter;
  final Value<int?> entryId;
  final Value<String?> packageName;
  final Value<String?> color;
  final Value<int> rowid;
  const CoversTableCompanion({
    this.filter = const Value.absent(),
    this.entryId = const Value.absent(),
    this.packageName = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoversTableCompanion.insert({
    required String filter,
    this.entryId = const Value.absent(),
    this.packageName = const Value.absent(),
    this.color = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : filter = Value(filter);
  static Insertable<CoversTableData> custom({
    Expression<String>? filter,
    Expression<int>? entryId,
    Expression<String>? packageName,
    Expression<String>? color,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (filter != null) 'filter': filter,
      if (entryId != null) 'entryId': entryId,
      if (packageName != null) 'packageName': packageName,
      if (color != null) 'color': color,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoversTableCompanion copyWith({
    Value<String>? filter,
    Value<int?>? entryId,
    Value<String?>? packageName,
    Value<String?>? color,
    Value<int>? rowid,
  }) {
    return CoversTableCompanion(
      filter: filter ?? this.filter,
      entryId: entryId ?? this.entryId,
      packageName: packageName ?? this.packageName,
      color: color ?? this.color,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (filter.present) {
      map['filter'] = Variable<String>(filter.value);
    }
    if (entryId.present) {
      map['entryId'] = Variable<int>(entryId.value);
    }
    if (packageName.present) {
      map['packageName'] = Variable<String>(packageName.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoversTableCompanion(')
          ..write('filter: $filter, ')
          ..write('entryId: $entryId, ')
          ..write('packageName: $packageName, ')
          ..write('color: $color, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DynamicAlbumsTableTable extends DynamicAlbumsTable
    with TableInfo<$DynamicAlbumsTableTable, DynamicAlbumsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DynamicAlbumsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filterMeta = const VerificationMeta('filter');
  @override
  late final GeneratedColumn<String> filter = GeneratedColumn<String>(
    'filter',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [name, filter];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dynamicAlbums';
  @override
  VerificationContext validateIntegrity(
    Insertable<DynamicAlbumsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('filter')) {
      context.handle(
        _filterMeta,
        filter.isAcceptableOrUnknown(data['filter']!, _filterMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  DynamicAlbumsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DynamicAlbumsTableData(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      filter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter'],
      ),
    );
  }

  @override
  $DynamicAlbumsTableTable createAlias(String alias) {
    return $DynamicAlbumsTableTable(attachedDatabase, alias);
  }
}

class DynamicAlbumsTableData extends DataClass
    implements Insertable<DynamicAlbumsTableData> {
  final String name;
  final String? filter;
  const DynamicAlbumsTableData({required this.name, this.filter});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || filter != null) {
      map['filter'] = Variable<String>(filter);
    }
    return map;
  }

  DynamicAlbumsTableCompanion toCompanion(bool nullToAbsent) {
    return DynamicAlbumsTableCompanion(
      name: Value(name),
      filter: filter == null && nullToAbsent
          ? const Value.absent()
          : Value(filter),
    );
  }

  factory DynamicAlbumsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DynamicAlbumsTableData(
      name: serializer.fromJson<String>(json['name']),
      filter: serializer.fromJson<String?>(json['filter']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'filter': serializer.toJson<String?>(filter),
    };
  }

  DynamicAlbumsTableData copyWith({
    String? name,
    Value<String?> filter = const Value.absent(),
  }) => DynamicAlbumsTableData(
    name: name ?? this.name,
    filter: filter.present ? filter.value : this.filter,
  );
  DynamicAlbumsTableData copyWithCompanion(DynamicAlbumsTableCompanion data) {
    return DynamicAlbumsTableData(
      name: data.name.present ? data.name.value : this.name,
      filter: data.filter.present ? data.filter.value : this.filter,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DynamicAlbumsTableData(')
          ..write('name: $name, ')
          ..write('filter: $filter')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, filter);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DynamicAlbumsTableData &&
          other.name == this.name &&
          other.filter == this.filter);
}

class DynamicAlbumsTableCompanion
    extends UpdateCompanion<DynamicAlbumsTableData> {
  final Value<String> name;
  final Value<String?> filter;
  final Value<int> rowid;
  const DynamicAlbumsTableCompanion({
    this.name = const Value.absent(),
    this.filter = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DynamicAlbumsTableCompanion.insert({
    required String name,
    this.filter = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<DynamicAlbumsTableData> custom({
    Expression<String>? name,
    Expression<String>? filter,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (filter != null) 'filter': filter,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DynamicAlbumsTableCompanion copyWith({
    Value<String>? name,
    Value<String?>? filter,
    Value<int>? rowid,
  }) {
    return DynamicAlbumsTableCompanion(
      name: name ?? this.name,
      filter: filter ?? this.filter,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (filter.present) {
      map['filter'] = Variable<String>(filter.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DynamicAlbumsTableCompanion(')
          ..write('name: $name, ')
          ..write('filter: $filter, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VaultsTableTable extends VaultsTable
    with TableInfo<$VaultsTableTable, VaultsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _autoLockMeta = const VerificationMeta(
    'autoLock',
  );
  @override
  late final GeneratedColumn<int> autoLock = GeneratedColumn<int>(
    'autoLock',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _useBinMeta = const VerificationMeta('useBin');
  @override
  late final GeneratedColumn<int> useBin = GeneratedColumn<int>(
    'useBin',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lockTypeMeta = const VerificationMeta(
    'lockType',
  );
  @override
  late final GeneratedColumn<String> lockType = GeneratedColumn<String>(
    'lockType',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [name, autoLock, useBin, lockType];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vaults';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('autoLock')) {
      context.handle(
        _autoLockMeta,
        autoLock.isAcceptableOrUnknown(data['autoLock']!, _autoLockMeta),
      );
    }
    if (data.containsKey('useBin')) {
      context.handle(
        _useBinMeta,
        useBin.isAcceptableOrUnknown(data['useBin']!, _useBinMeta),
      );
    }
    if (data.containsKey('lockType')) {
      context.handle(
        _lockTypeMeta,
        lockType.isAcceptableOrUnknown(data['lockType']!, _lockTypeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  VaultsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultsTableData(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      autoLock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}autoLock'],
      ),
      useBin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}useBin'],
      ),
      lockType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lockType'],
      ),
    );
  }

  @override
  $VaultsTableTable createAlias(String alias) {
    return $VaultsTableTable(attachedDatabase, alias);
  }
}

class VaultsTableData extends DataClass implements Insertable<VaultsTableData> {
  final String name;
  final int? autoLock;
  final int? useBin;
  final String? lockType;
  const VaultsTableData({
    required this.name,
    this.autoLock,
    this.useBin,
    this.lockType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || autoLock != null) {
      map['autoLock'] = Variable<int>(autoLock);
    }
    if (!nullToAbsent || useBin != null) {
      map['useBin'] = Variable<int>(useBin);
    }
    if (!nullToAbsent || lockType != null) {
      map['lockType'] = Variable<String>(lockType);
    }
    return map;
  }

  VaultsTableCompanion toCompanion(bool nullToAbsent) {
    return VaultsTableCompanion(
      name: Value(name),
      autoLock: autoLock == null && nullToAbsent
          ? const Value.absent()
          : Value(autoLock),
      useBin: useBin == null && nullToAbsent
          ? const Value.absent()
          : Value(useBin),
      lockType: lockType == null && nullToAbsent
          ? const Value.absent()
          : Value(lockType),
    );
  }

  factory VaultsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultsTableData(
      name: serializer.fromJson<String>(json['name']),
      autoLock: serializer.fromJson<int?>(json['autoLock']),
      useBin: serializer.fromJson<int?>(json['useBin']),
      lockType: serializer.fromJson<String?>(json['lockType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'autoLock': serializer.toJson<int?>(autoLock),
      'useBin': serializer.toJson<int?>(useBin),
      'lockType': serializer.toJson<String?>(lockType),
    };
  }

  VaultsTableData copyWith({
    String? name,
    Value<int?> autoLock = const Value.absent(),
    Value<int?> useBin = const Value.absent(),
    Value<String?> lockType = const Value.absent(),
  }) => VaultsTableData(
    name: name ?? this.name,
    autoLock: autoLock.present ? autoLock.value : this.autoLock,
    useBin: useBin.present ? useBin.value : this.useBin,
    lockType: lockType.present ? lockType.value : this.lockType,
  );
  VaultsTableData copyWithCompanion(VaultsTableCompanion data) {
    return VaultsTableData(
      name: data.name.present ? data.name.value : this.name,
      autoLock: data.autoLock.present ? data.autoLock.value : this.autoLock,
      useBin: data.useBin.present ? data.useBin.value : this.useBin,
      lockType: data.lockType.present ? data.lockType.value : this.lockType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultsTableData(')
          ..write('name: $name, ')
          ..write('autoLock: $autoLock, ')
          ..write('useBin: $useBin, ')
          ..write('lockType: $lockType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, autoLock, useBin, lockType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultsTableData &&
          other.name == this.name &&
          other.autoLock == this.autoLock &&
          other.useBin == this.useBin &&
          other.lockType == this.lockType);
}

class VaultsTableCompanion extends UpdateCompanion<VaultsTableData> {
  final Value<String> name;
  final Value<int?> autoLock;
  final Value<int?> useBin;
  final Value<String?> lockType;
  final Value<int> rowid;
  const VaultsTableCompanion({
    this.name = const Value.absent(),
    this.autoLock = const Value.absent(),
    this.useBin = const Value.absent(),
    this.lockType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VaultsTableCompanion.insert({
    required String name,
    this.autoLock = const Value.absent(),
    this.useBin = const Value.absent(),
    this.lockType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<VaultsTableData> custom({
    Expression<String>? name,
    Expression<int>? autoLock,
    Expression<int>? useBin,
    Expression<String>? lockType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (autoLock != null) 'autoLock': autoLock,
      if (useBin != null) 'useBin': useBin,
      if (lockType != null) 'lockType': lockType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VaultsTableCompanion copyWith({
    Value<String>? name,
    Value<int?>? autoLock,
    Value<int?>? useBin,
    Value<String?>? lockType,
    Value<int>? rowid,
  }) {
    return VaultsTableCompanion(
      name: name ?? this.name,
      autoLock: autoLock ?? this.autoLock,
      useBin: useBin ?? this.useBin,
      lockType: lockType ?? this.lockType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (autoLock.present) {
      map['autoLock'] = Variable<int>(autoLock.value);
    }
    if (useBin.present) {
      map['useBin'] = Variable<int>(useBin.value);
    }
    if (lockType.present) {
      map['lockType'] = Variable<String>(lockType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultsTableCompanion(')
          ..write('name: $name, ')
          ..write('autoLock: $autoLock, ')
          ..write('useBin: $useBin, ')
          ..write('lockType: $lockType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrashTableTable extends TrashTable
    with TableInfo<$TrashTableTable, TrashTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrashTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMillisMeta = const VerificationMeta(
    'dateMillis',
  );
  @override
  late final GeneratedColumn<int> dateMillis = GeneratedColumn<int>(
    'dateMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, path, dateMillis];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trash';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrashTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('dateMillis')) {
      context.handle(
        _dateMillisMeta,
        dateMillis.isAcceptableOrUnknown(data['dateMillis']!, _dateMillisMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrashTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrashTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      dateMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dateMillis'],
      ),
    );
  }

  @override
  $TrashTableTable createAlias(String alias) {
    return $TrashTableTable(attachedDatabase, alias);
  }
}

class TrashTableData extends DataClass implements Insertable<TrashTableData> {
  final int id;
  final String? path;
  final int? dateMillis;
  const TrashTableData({required this.id, this.path, this.dateMillis});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || dateMillis != null) {
      map['dateMillis'] = Variable<int>(dateMillis);
    }
    return map;
  }

  TrashTableCompanion toCompanion(bool nullToAbsent) {
    return TrashTableCompanion(
      id: Value(id),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      dateMillis: dateMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(dateMillis),
    );
  }

  factory TrashTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrashTableData(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String?>(json['path']),
      dateMillis: serializer.fromJson<int?>(json['dateMillis']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String?>(path),
      'dateMillis': serializer.toJson<int?>(dateMillis),
    };
  }

  TrashTableData copyWith({
    int? id,
    Value<String?> path = const Value.absent(),
    Value<int?> dateMillis = const Value.absent(),
  }) => TrashTableData(
    id: id ?? this.id,
    path: path.present ? path.value : this.path,
    dateMillis: dateMillis.present ? dateMillis.value : this.dateMillis,
  );
  TrashTableData copyWithCompanion(TrashTableCompanion data) {
    return TrashTableData(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      dateMillis: data.dateMillis.present
          ? data.dateMillis.value
          : this.dateMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrashTableData(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('dateMillis: $dateMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, dateMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrashTableData &&
          other.id == this.id &&
          other.path == this.path &&
          other.dateMillis == this.dateMillis);
}

class TrashTableCompanion extends UpdateCompanion<TrashTableData> {
  final Value<int> id;
  final Value<String?> path;
  final Value<int?> dateMillis;
  const TrashTableCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.dateMillis = const Value.absent(),
  });
  TrashTableCompanion.insert({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.dateMillis = const Value.absent(),
  });
  static Insertable<TrashTableData> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<int>? dateMillis,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (dateMillis != null) 'dateMillis': dateMillis,
    });
  }

  TrashTableCompanion copyWith({
    Value<int>? id,
    Value<String?>? path,
    Value<int?>? dateMillis,
  }) {
    return TrashTableCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      dateMillis: dateMillis ?? this.dateMillis,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (dateMillis.present) {
      map['dateMillis'] = Variable<int>(dateMillis.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrashTableCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('dateMillis: $dateMillis')
          ..write(')'))
        .toString();
  }
}

class $VideoPlaybackTableTable extends VideoPlaybackTable
    with TableInfo<$VideoPlaybackTableTable, VideoPlaybackTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideoPlaybackTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resumeTimeMillisMeta = const VerificationMeta(
    'resumeTimeMillis',
  );
  @override
  late final GeneratedColumn<int> resumeTimeMillis = GeneratedColumn<int>(
    'resumeTimeMillis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, resumeTimeMillis];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'videoPlayback';
  @override
  VerificationContext validateIntegrity(
    Insertable<VideoPlaybackTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('resumeTimeMillis')) {
      context.handle(
        _resumeTimeMillisMeta,
        resumeTimeMillis.isAcceptableOrUnknown(
          data['resumeTimeMillis']!,
          _resumeTimeMillisMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VideoPlaybackTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VideoPlaybackTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      resumeTimeMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resumeTimeMillis'],
      ),
    );
  }

  @override
  $VideoPlaybackTableTable createAlias(String alias) {
    return $VideoPlaybackTableTable(attachedDatabase, alias);
  }
}

class VideoPlaybackTableData extends DataClass
    implements Insertable<VideoPlaybackTableData> {
  final int id;
  final int? resumeTimeMillis;
  const VideoPlaybackTableData({required this.id, this.resumeTimeMillis});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || resumeTimeMillis != null) {
      map['resumeTimeMillis'] = Variable<int>(resumeTimeMillis);
    }
    return map;
  }

  VideoPlaybackTableCompanion toCompanion(bool nullToAbsent) {
    return VideoPlaybackTableCompanion(
      id: Value(id),
      resumeTimeMillis: resumeTimeMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(resumeTimeMillis),
    );
  }

  factory VideoPlaybackTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VideoPlaybackTableData(
      id: serializer.fromJson<int>(json['id']),
      resumeTimeMillis: serializer.fromJson<int?>(json['resumeTimeMillis']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'resumeTimeMillis': serializer.toJson<int?>(resumeTimeMillis),
    };
  }

  VideoPlaybackTableData copyWith({
    int? id,
    Value<int?> resumeTimeMillis = const Value.absent(),
  }) => VideoPlaybackTableData(
    id: id ?? this.id,
    resumeTimeMillis: resumeTimeMillis.present
        ? resumeTimeMillis.value
        : this.resumeTimeMillis,
  );
  VideoPlaybackTableData copyWithCompanion(VideoPlaybackTableCompanion data) {
    return VideoPlaybackTableData(
      id: data.id.present ? data.id.value : this.id,
      resumeTimeMillis: data.resumeTimeMillis.present
          ? data.resumeTimeMillis.value
          : this.resumeTimeMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VideoPlaybackTableData(')
          ..write('id: $id, ')
          ..write('resumeTimeMillis: $resumeTimeMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, resumeTimeMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VideoPlaybackTableData &&
          other.id == this.id &&
          other.resumeTimeMillis == this.resumeTimeMillis);
}

class VideoPlaybackTableCompanion
    extends UpdateCompanion<VideoPlaybackTableData> {
  final Value<int> id;
  final Value<int?> resumeTimeMillis;
  const VideoPlaybackTableCompanion({
    this.id = const Value.absent(),
    this.resumeTimeMillis = const Value.absent(),
  });
  VideoPlaybackTableCompanion.insert({
    this.id = const Value.absent(),
    this.resumeTimeMillis = const Value.absent(),
  });
  static Insertable<VideoPlaybackTableData> custom({
    Expression<int>? id,
    Expression<int>? resumeTimeMillis,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (resumeTimeMillis != null) 'resumeTimeMillis': resumeTimeMillis,
    });
  }

  VideoPlaybackTableCompanion copyWith({
    Value<int>? id,
    Value<int?>? resumeTimeMillis,
  }) {
    return VideoPlaybackTableCompanion(
      id: id ?? this.id,
      resumeTimeMillis: resumeTimeMillis ?? this.resumeTimeMillis,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (resumeTimeMillis.present) {
      map['resumeTimeMillis'] = Variable<int>(resumeTimeMillis.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideoPlaybackTableCompanion(')
          ..write('id: $id, ')
          ..write('resumeTimeMillis: $resumeTimeMillis')
          ..write(')'))
        .toString();
  }
}

class $DebugTableTable extends DebugTable
    with TableInfo<$DebugTableTable, DebugTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DebugTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, message];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'debug';
  @override
  VerificationContext validateIntegrity(
    Insertable<DebugTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DebugTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DebugTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
    );
  }

  @override
  $DebugTableTable createAlias(String alias) {
    return $DebugTableTable(attachedDatabase, alias);
  }
}

class DebugTableData extends DataClass implements Insertable<DebugTableData> {
  final int id;
  final String? message;
  const DebugTableData({required this.id, this.message});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    return map;
  }

  DebugTableCompanion toCompanion(bool nullToAbsent) {
    return DebugTableCompanion(
      id: Value(id),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
    );
  }

  factory DebugTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DebugTableData(
      id: serializer.fromJson<int>(json['id']),
      message: serializer.fromJson<String?>(json['message']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'message': serializer.toJson<String?>(message),
    };
  }

  DebugTableData copyWith({
    int? id,
    Value<String?> message = const Value.absent(),
  }) => DebugTableData(
    id: id ?? this.id,
    message: message.present ? message.value : this.message,
  );
  DebugTableData copyWithCompanion(DebugTableCompanion data) {
    return DebugTableData(
      id: data.id.present ? data.id.value : this.id,
      message: data.message.present ? data.message.value : this.message,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DebugTableData(')
          ..write('id: $id, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, message);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DebugTableData &&
          other.id == this.id &&
          other.message == this.message);
}

class DebugTableCompanion extends UpdateCompanion<DebugTableData> {
  final Value<int> id;
  final Value<String?> message;
  const DebugTableCompanion({
    this.id = const Value.absent(),
    this.message = const Value.absent(),
  });
  DebugTableCompanion.insert({
    this.id = const Value.absent(),
    this.message = const Value.absent(),
  });
  static Insertable<DebugTableData> custom({
    Expression<int>? id,
    Expression<String>? message,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (message != null) 'message': message,
    });
  }

  DebugTableCompanion copyWith({Value<int>? id, Value<String?>? message}) {
    return DebugTableCompanion(
      id: id ?? this.id,
      message: message ?? this.message,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DebugTableCompanion(')
          ..write('id: $id, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }
}

class $AppMetaTableTable extends AppMetaTable
    with TableInfo<$AppMetaTableTable, AppMetaTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appMeta';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppMetaTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppMetaTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetaTableData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $AppMetaTableTable createAlias(String alias) {
    return $AppMetaTableTable(attachedDatabase, alias);
  }
}

class AppMetaTableData extends DataClass
    implements Insertable<AppMetaTableData> {
  final String key;
  final String? value;
  const AppMetaTableData({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  AppMetaTableCompanion toCompanion(bool nullToAbsent) {
    return AppMetaTableCompanion(
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory AppMetaTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetaTableData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  AppMetaTableData copyWith({
    String? key,
    Value<String?> value = const Value.absent(),
  }) => AppMetaTableData(
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  AppMetaTableData copyWithCompanion(AppMetaTableCompanion data) {
    return AppMetaTableData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaTableData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetaTableData &&
          other.key == this.key &&
          other.value == this.value);
}

class AppMetaTableCompanion extends UpdateCompanion<AppMetaTableData> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const AppMetaTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppMetaTableCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<AppMetaTableData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppMetaTableCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return AppMetaTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsValuesTableTable extends SettingsValuesTable
    with TableInfo<$SettingsValuesTableTable, SettingsValuesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsValuesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [key, type, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settingsValues';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingsValuesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingsValuesTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsValuesTableData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsValuesTableTable createAlias(String alias) {
    return $SettingsValuesTableTable(attachedDatabase, alias);
  }
}

class SettingsValuesTableData extends DataClass
    implements Insertable<SettingsValuesTableData> {
  final String key;

  /// `SettingValueType` name (`bool` / `int` / `double` / `string` /
  /// `stringList`).
  final String type;

  /// Codec-encoded value (see `MetaSettingsValueCodec`).
  final String value;
  final DateTime updatedAt;
  const SettingsValuesTableData({
    required this.key,
    required this.type,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['type'] = Variable<String>(type);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsValuesTableCompanion toCompanion(bool nullToAbsent) {
    return SettingsValuesTableCompanion(
      key: Value(key),
      type: Value(type),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingsValuesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsValuesTableData(
      key: serializer.fromJson<String>(json['key']),
      type: serializer.fromJson<String>(json['type']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'type': serializer.toJson<String>(type),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SettingsValuesTableData copyWith({
    String? key,
    String? type,
    String? value,
    DateTime? updatedAt,
  }) => SettingsValuesTableData(
    key: key ?? this.key,
    type: type ?? this.type,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SettingsValuesTableData copyWithCompanion(SettingsValuesTableCompanion data) {
    return SettingsValuesTableData(
      key: data.key.present ? data.key.value : this.key,
      type: data.type.present ? data.type.value : this.type,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsValuesTableData(')
          ..write('key: $key, ')
          ..write('type: $type, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, type, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsValuesTableData &&
          other.key == this.key &&
          other.type == this.type &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsValuesTableCompanion
    extends UpdateCompanion<SettingsValuesTableData> {
  final Value<String> key;
  final Value<String> type;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsValuesTableCompanion({
    this.key = const Value.absent(),
    this.type = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsValuesTableCompanion.insert({
    required String key,
    required String type,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       type = Value(type),
       value = Value(value);
  static Insertable<SettingsValuesTableData> custom({
    Expression<String>? key,
    Expression<String>? type,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (type != null) 'type': type,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsValuesTableCompanion copyWith({
    Value<String>? key,
    Value<String>? type,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsValuesTableCompanion(
      key: key ?? this.key,
      type: type ?? this.type,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsValuesTableCompanion(')
          ..write('key: $key, ')
          ..write('type: $type, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisibleRangePresetRowsTable extends VisibleRangePresetRows
    with TableInfo<$VisibleRangePresetRowsTable, VisibleRangePresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisibleRangePresetRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _filtersMeta = const VerificationMeta(
    'filters',
  );
  @override
  late final GeneratedColumn<String> filters = GeneratedColumn<String>(
    'filters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _builtinMeta = const VerificationMeta(
    'builtin',
  );
  @override
  late final GeneratedColumn<bool> builtin = GeneratedColumn<bool>(
    'builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    filters,
    builtin,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visible_range_presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisibleRangePresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('filters')) {
      context.handle(
        _filtersMeta,
        filters.isAcceptableOrUnknown(data['filters']!, _filtersMeta),
      );
    }
    if (data.containsKey('builtin')) {
      context.handle(
        _builtinMeta,
        builtin.isAcceptableOrUnknown(data['builtin']!, _builtinMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisibleRangePresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisibleRangePresetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      filters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filters'],
      )!,
      builtin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}builtin'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $VisibleRangePresetRowsTable createAlias(String alias) {
    return $VisibleRangePresetRowsTable(attachedDatabase, alias);
  }
}

class VisibleRangePresetRow extends DataClass
    implements Insertable<VisibleRangePresetRow> {
  final String id;
  final String name;

  /// Free-form user note, e.g. when and from what the base was pinned.
  final String description;

  /// JSON array of `CollectionFilter.toJsonMap()` bodies, AND-ed together.
  final String filters;

  /// Built-in presets are read-only and re-addable through the "re-add default
  /// restrictions" action.
  final bool builtin;
  final int position;
  const VisibleRangePresetRow({
    required this.id,
    required this.name,
    required this.description,
    required this.filters,
    required this.builtin,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['filters'] = Variable<String>(filters);
    map['builtin'] = Variable<bool>(builtin);
    map['position'] = Variable<int>(position);
    return map;
  }

  VisibleRangePresetRowsCompanion toCompanion(bool nullToAbsent) {
    return VisibleRangePresetRowsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      filters: Value(filters),
      builtin: Value(builtin),
      position: Value(position),
    );
  }

  factory VisibleRangePresetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisibleRangePresetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      filters: serializer.fromJson<String>(json['filters']),
      builtin: serializer.fromJson<bool>(json['builtin']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'filters': serializer.toJson<String>(filters),
      'builtin': serializer.toJson<bool>(builtin),
      'position': serializer.toJson<int>(position),
    };
  }

  VisibleRangePresetRow copyWith({
    String? id,
    String? name,
    String? description,
    String? filters,
    bool? builtin,
    int? position,
  }) => VisibleRangePresetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    filters: filters ?? this.filters,
    builtin: builtin ?? this.builtin,
    position: position ?? this.position,
  );
  VisibleRangePresetRow copyWithCompanion(
    VisibleRangePresetRowsCompanion data,
  ) {
    return VisibleRangePresetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      filters: data.filters.present ? data.filters.value : this.filters,
      builtin: data.builtin.present ? data.builtin.value : this.builtin,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangePresetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('filters: $filters, ')
          ..write('builtin: $builtin, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, filters, builtin, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisibleRangePresetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.filters == this.filters &&
          other.builtin == this.builtin &&
          other.position == this.position);
}

class VisibleRangePresetRowsCompanion
    extends UpdateCompanion<VisibleRangePresetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> filters;
  final Value<bool> builtin;
  final Value<int> position;
  final Value<int> rowid;
  const VisibleRangePresetRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.filters = const Value.absent(),
    this.builtin = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisibleRangePresetRowsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.filters = const Value.absent(),
    this.builtin = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<VisibleRangePresetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? filters,
    Expression<bool>? builtin,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (filters != null) 'filters': filters,
      if (builtin != null) 'builtin': builtin,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisibleRangePresetRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? description,
    Value<String>? filters,
    Value<bool>? builtin,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return VisibleRangePresetRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      builtin: builtin ?? this.builtin,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (filters.present) {
      map['filters'] = Variable<String>(filters.value);
    }
    if (builtin.present) {
      map['builtin'] = Variable<bool>(builtin.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangePresetRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('filters: $filters, ')
          ..write('builtin: $builtin, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisibleRangeRowsTable extends VisibleRangeRows
    with TableInfo<$VisibleRangeRowsTable, VisibleRangeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisibleRangeRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'ownerId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseNameMeta = const VerificationMeta(
    'baseName',
  );
  @override
  late final GeneratedColumn<String> baseName = GeneratedColumn<String>(
    'baseName',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _basePresetIdMeta = const VerificationMeta(
    'basePresetId',
  );
  @override
  late final GeneratedColumn<String> basePresetId = GeneratedColumn<String>(
    'basePresetId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _baseFiltersMeta = const VerificationMeta(
    'baseFilters',
  );
  @override
  late final GeneratedColumn<String> baseFilters = GeneratedColumn<String>(
    'baseFilters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _orderModeMeta = const VerificationMeta(
    'orderMode',
  );
  @override
  late final GeneratedColumn<String> orderMode = GeneratedColumn<String>(
    'orderMode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('intersectFirst'),
  );
  static const VerificationMeta _lockedMeta = const VerificationMeta('locked');
  @override
  late final GeneratedColumn<bool> locked = GeneratedColumn<bool>(
    'locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("locked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _permissionsMeta = const VerificationMeta(
    'permissions',
  );
  @override
  late final GeneratedColumn<String> permissions = GeneratedColumn<String>(
    'permissions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updatedAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scope,
    ownerId,
    baseName,
    basePresetId,
    baseFilters,
    orderMode,
    locked,
    permissions,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visible_ranges';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisibleRangeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('ownerId')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['ownerId']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('baseName')) {
      context.handle(
        _baseNameMeta,
        baseName.isAcceptableOrUnknown(data['baseName']!, _baseNameMeta),
      );
    }
    if (data.containsKey('basePresetId')) {
      context.handle(
        _basePresetIdMeta,
        basePresetId.isAcceptableOrUnknown(
          data['basePresetId']!,
          _basePresetIdMeta,
        ),
      );
    }
    if (data.containsKey('baseFilters')) {
      context.handle(
        _baseFiltersMeta,
        baseFilters.isAcceptableOrUnknown(
          data['baseFilters']!,
          _baseFiltersMeta,
        ),
      );
    }
    if (data.containsKey('orderMode')) {
      context.handle(
        _orderModeMeta,
        orderMode.isAcceptableOrUnknown(data['orderMode']!, _orderModeMeta),
      );
    }
    if (data.containsKey('locked')) {
      context.handle(
        _lockedMeta,
        locked.isAcceptableOrUnknown(data['locked']!, _lockedMeta),
      );
    }
    if (data.containsKey('permissions')) {
      context.handle(
        _permissionsMeta,
        permissions.isAcceptableOrUnknown(
          data['permissions']!,
          _permissionsMeta,
        ),
      );
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updatedAt')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updatedAt']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisibleRangeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisibleRangeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ownerId'],
      )!,
      baseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baseName'],
      )!,
      basePresetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}basePresetId'],
      )!,
      baseFilters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baseFilters'],
      )!,
      orderMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}orderMode'],
      )!,
      locked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}locked'],
      )!,
      permissions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permissions'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}createdAt'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updatedAt'],
      )!,
    );
  }

  @override
  $VisibleRangeRowsTable createAlias(String alias) {
    return $VisibleRangeRowsTable(attachedDatabase, alias);
  }
}

class VisibleRangeRow extends DataClass implements Insertable<VisibleRangeRow> {
  final String id;
  final String scope;

  /// Owner of the range: `gallery` for the single gallery range, otherwise the
  /// wallpaper group id.
  final String ownerId;

  /// Display name of the selected base (empty when [baseFilters] is empty).
  final String baseName;

  /// Preset this base was last copied from, or empty for unrestricted/custom.
  final String basePresetId;

  /// JSON array, AND-ed together. Empty means unrestricted.
  final String baseFilters;

  /// `intersectFirst` (restrictions before supplements) or `unionFirst`
  /// (supplements before restrictions).
  final String orderMode;
  final bool locked;

  /// JSON of `VisibleRangePermissions`; null means the default (read-only with
  /// sharing allowed).
  final String? permissions;
  final int createdAt;
  final int updatedAt;
  const VisibleRangeRow({
    required this.id,
    required this.scope,
    required this.ownerId,
    required this.baseName,
    required this.basePresetId,
    required this.baseFilters,
    required this.orderMode,
    required this.locked,
    this.permissions,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['scope'] = Variable<String>(scope);
    map['ownerId'] = Variable<String>(ownerId);
    map['baseName'] = Variable<String>(baseName);
    map['basePresetId'] = Variable<String>(basePresetId);
    map['baseFilters'] = Variable<String>(baseFilters);
    map['orderMode'] = Variable<String>(orderMode);
    map['locked'] = Variable<bool>(locked);
    if (!nullToAbsent || permissions != null) {
      map['permissions'] = Variable<String>(permissions);
    }
    map['createdAt'] = Variable<int>(createdAt);
    map['updatedAt'] = Variable<int>(updatedAt);
    return map;
  }

  VisibleRangeRowsCompanion toCompanion(bool nullToAbsent) {
    return VisibleRangeRowsCompanion(
      id: Value(id),
      scope: Value(scope),
      ownerId: Value(ownerId),
      baseName: Value(baseName),
      basePresetId: Value(basePresetId),
      baseFilters: Value(baseFilters),
      orderMode: Value(orderMode),
      locked: Value(locked),
      permissions: permissions == null && nullToAbsent
          ? const Value.absent()
          : Value(permissions),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory VisibleRangeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisibleRangeRow(
      id: serializer.fromJson<String>(json['id']),
      scope: serializer.fromJson<String>(json['scope']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      baseName: serializer.fromJson<String>(json['baseName']),
      basePresetId: serializer.fromJson<String>(json['basePresetId']),
      baseFilters: serializer.fromJson<String>(json['baseFilters']),
      orderMode: serializer.fromJson<String>(json['orderMode']),
      locked: serializer.fromJson<bool>(json['locked']),
      permissions: serializer.fromJson<String?>(json['permissions']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scope': serializer.toJson<String>(scope),
      'ownerId': serializer.toJson<String>(ownerId),
      'baseName': serializer.toJson<String>(baseName),
      'basePresetId': serializer.toJson<String>(basePresetId),
      'baseFilters': serializer.toJson<String>(baseFilters),
      'orderMode': serializer.toJson<String>(orderMode),
      'locked': serializer.toJson<bool>(locked),
      'permissions': serializer.toJson<String?>(permissions),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  VisibleRangeRow copyWith({
    String? id,
    String? scope,
    String? ownerId,
    String? baseName,
    String? basePresetId,
    String? baseFilters,
    String? orderMode,
    bool? locked,
    Value<String?> permissions = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => VisibleRangeRow(
    id: id ?? this.id,
    scope: scope ?? this.scope,
    ownerId: ownerId ?? this.ownerId,
    baseName: baseName ?? this.baseName,
    basePresetId: basePresetId ?? this.basePresetId,
    baseFilters: baseFilters ?? this.baseFilters,
    orderMode: orderMode ?? this.orderMode,
    locked: locked ?? this.locked,
    permissions: permissions.present ? permissions.value : this.permissions,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VisibleRangeRow copyWithCompanion(VisibleRangeRowsCompanion data) {
    return VisibleRangeRow(
      id: data.id.present ? data.id.value : this.id,
      scope: data.scope.present ? data.scope.value : this.scope,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      baseName: data.baseName.present ? data.baseName.value : this.baseName,
      basePresetId: data.basePresetId.present
          ? data.basePresetId.value
          : this.basePresetId,
      baseFilters: data.baseFilters.present
          ? data.baseFilters.value
          : this.baseFilters,
      orderMode: data.orderMode.present ? data.orderMode.value : this.orderMode,
      locked: data.locked.present ? data.locked.value : this.locked,
      permissions: data.permissions.present
          ? data.permissions.value
          : this.permissions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeRow(')
          ..write('id: $id, ')
          ..write('scope: $scope, ')
          ..write('ownerId: $ownerId, ')
          ..write('baseName: $baseName, ')
          ..write('basePresetId: $basePresetId, ')
          ..write('baseFilters: $baseFilters, ')
          ..write('orderMode: $orderMode, ')
          ..write('locked: $locked, ')
          ..write('permissions: $permissions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    scope,
    ownerId,
    baseName,
    basePresetId,
    baseFilters,
    orderMode,
    locked,
    permissions,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisibleRangeRow &&
          other.id == this.id &&
          other.scope == this.scope &&
          other.ownerId == this.ownerId &&
          other.baseName == this.baseName &&
          other.basePresetId == this.basePresetId &&
          other.baseFilters == this.baseFilters &&
          other.orderMode == this.orderMode &&
          other.locked == this.locked &&
          other.permissions == this.permissions &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VisibleRangeRowsCompanion extends UpdateCompanion<VisibleRangeRow> {
  final Value<String> id;
  final Value<String> scope;
  final Value<String> ownerId;
  final Value<String> baseName;
  final Value<String> basePresetId;
  final Value<String> baseFilters;
  final Value<String> orderMode;
  final Value<bool> locked;
  final Value<String?> permissions;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const VisibleRangeRowsCompanion({
    this.id = const Value.absent(),
    this.scope = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.baseName = const Value.absent(),
    this.basePresetId = const Value.absent(),
    this.baseFilters = const Value.absent(),
    this.orderMode = const Value.absent(),
    this.locked = const Value.absent(),
    this.permissions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisibleRangeRowsCompanion.insert({
    required String id,
    required String scope,
    required String ownerId,
    this.baseName = const Value.absent(),
    this.basePresetId = const Value.absent(),
    this.baseFilters = const Value.absent(),
    this.orderMode = const Value.absent(),
    this.locked = const Value.absent(),
    this.permissions = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       scope = Value(scope),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<VisibleRangeRow> custom({
    Expression<String>? id,
    Expression<String>? scope,
    Expression<String>? ownerId,
    Expression<String>? baseName,
    Expression<String>? basePresetId,
    Expression<String>? baseFilters,
    Expression<String>? orderMode,
    Expression<bool>? locked,
    Expression<String>? permissions,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scope != null) 'scope': scope,
      if (ownerId != null) 'ownerId': ownerId,
      if (baseName != null) 'baseName': baseName,
      if (basePresetId != null) 'basePresetId': basePresetId,
      if (baseFilters != null) 'baseFilters': baseFilters,
      if (orderMode != null) 'orderMode': orderMode,
      if (locked != null) 'locked': locked,
      if (permissions != null) 'permissions': permissions,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisibleRangeRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? scope,
    Value<String>? ownerId,
    Value<String>? baseName,
    Value<String>? basePresetId,
    Value<String>? baseFilters,
    Value<String>? orderMode,
    Value<bool>? locked,
    Value<String?>? permissions,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return VisibleRangeRowsCompanion(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      ownerId: ownerId ?? this.ownerId,
      baseName: baseName ?? this.baseName,
      basePresetId: basePresetId ?? this.basePresetId,
      baseFilters: baseFilters ?? this.baseFilters,
      orderMode: orderMode ?? this.orderMode,
      locked: locked ?? this.locked,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (ownerId.present) {
      map['ownerId'] = Variable<String>(ownerId.value);
    }
    if (baseName.present) {
      map['baseName'] = Variable<String>(baseName.value);
    }
    if (basePresetId.present) {
      map['basePresetId'] = Variable<String>(basePresetId.value);
    }
    if (baseFilters.present) {
      map['baseFilters'] = Variable<String>(baseFilters.value);
    }
    if (orderMode.present) {
      map['orderMode'] = Variable<String>(orderMode.value);
    }
    if (locked.present) {
      map['locked'] = Variable<bool>(locked.value);
    }
    if (permissions.present) {
      map['permissions'] = Variable<String>(permissions.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updatedAt'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeRowsCompanion(')
          ..write('id: $id, ')
          ..write('scope: $scope, ')
          ..write('ownerId: $ownerId, ')
          ..write('baseName: $baseName, ')
          ..write('basePresetId: $basePresetId, ')
          ..write('baseFilters: $baseFilters, ')
          ..write('orderMode: $orderMode, ')
          ..write('locked: $locked, ')
          ..write('permissions: $permissions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisibleRangeRuleRowsTable extends VisibleRangeRuleRows
    with TableInfo<$VisibleRangeRuleRowsTable, VisibleRangeRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisibleRangeRuleRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rangeIdMeta = const VerificationMeta(
    'rangeId',
  );
  @override
  late final GeneratedColumn<String> rangeId = GeneratedColumn<String>(
    'rangeId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _filtersMeta = const VerificationMeta(
    'filters',
  );
  @override
  late final GeneratedColumn<String> filters = GeneratedColumn<String>(
    'filters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rangeId,
    kind,
    position,
    label,
    description,
    filters,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visible_range_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisibleRangeRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rangeId')) {
      context.handle(
        _rangeIdMeta,
        rangeId.isAcceptableOrUnknown(data['rangeId']!, _rangeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rangeIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('filters')) {
      context.handle(
        _filtersMeta,
        filters.isAcceptableOrUnknown(data['filters']!, _filtersMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisibleRangeRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisibleRangeRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      rangeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rangeId'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      filters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filters'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $VisibleRangeRuleRowsTable createAlias(String alias) {
    return $VisibleRangeRuleRowsTable(attachedDatabase, alias);
  }
}

class VisibleRangeRuleRow extends DataClass
    implements Insertable<VisibleRangeRuleRow> {
  final String id;
  final String rangeId;
  final String kind;
  final int position;
  final String label;

  /// Free-form user note, e.g. when and from what the rule was pinned.
  final String description;

  /// JSON array of filter bodies.
  final String filters;
  final bool active;
  const VisibleRangeRuleRow({
    required this.id,
    required this.rangeId,
    required this.kind,
    required this.position,
    required this.label,
    required this.description,
    required this.filters,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['rangeId'] = Variable<String>(rangeId);
    map['kind'] = Variable<String>(kind);
    map['position'] = Variable<int>(position);
    map['label'] = Variable<String>(label);
    map['description'] = Variable<String>(description);
    map['filters'] = Variable<String>(filters);
    map['active'] = Variable<bool>(active);
    return map;
  }

  VisibleRangeRuleRowsCompanion toCompanion(bool nullToAbsent) {
    return VisibleRangeRuleRowsCompanion(
      id: Value(id),
      rangeId: Value(rangeId),
      kind: Value(kind),
      position: Value(position),
      label: Value(label),
      description: Value(description),
      filters: Value(filters),
      active: Value(active),
    );
  }

  factory VisibleRangeRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisibleRangeRuleRow(
      id: serializer.fromJson<String>(json['id']),
      rangeId: serializer.fromJson<String>(json['rangeId']),
      kind: serializer.fromJson<String>(json['kind']),
      position: serializer.fromJson<int>(json['position']),
      label: serializer.fromJson<String>(json['label']),
      description: serializer.fromJson<String>(json['description']),
      filters: serializer.fromJson<String>(json['filters']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rangeId': serializer.toJson<String>(rangeId),
      'kind': serializer.toJson<String>(kind),
      'position': serializer.toJson<int>(position),
      'label': serializer.toJson<String>(label),
      'description': serializer.toJson<String>(description),
      'filters': serializer.toJson<String>(filters),
      'active': serializer.toJson<bool>(active),
    };
  }

  VisibleRangeRuleRow copyWith({
    String? id,
    String? rangeId,
    String? kind,
    int? position,
    String? label,
    String? description,
    String? filters,
    bool? active,
  }) => VisibleRangeRuleRow(
    id: id ?? this.id,
    rangeId: rangeId ?? this.rangeId,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    label: label ?? this.label,
    description: description ?? this.description,
    filters: filters ?? this.filters,
    active: active ?? this.active,
  );
  VisibleRangeRuleRow copyWithCompanion(VisibleRangeRuleRowsCompanion data) {
    return VisibleRangeRuleRow(
      id: data.id.present ? data.id.value : this.id,
      rangeId: data.rangeId.present ? data.rangeId.value : this.rangeId,
      kind: data.kind.present ? data.kind.value : this.kind,
      position: data.position.present ? data.position.value : this.position,
      label: data.label.present ? data.label.value : this.label,
      description: data.description.present
          ? data.description.value
          : this.description,
      filters: data.filters.present ? data.filters.value : this.filters,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeRuleRow(')
          ..write('id: $id, ')
          ..write('rangeId: $rangeId, ')
          ..write('kind: $kind, ')
          ..write('position: $position, ')
          ..write('label: $label, ')
          ..write('description: $description, ')
          ..write('filters: $filters, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rangeId,
    kind,
    position,
    label,
    description,
    filters,
    active,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisibleRangeRuleRow &&
          other.id == this.id &&
          other.rangeId == this.rangeId &&
          other.kind == this.kind &&
          other.position == this.position &&
          other.label == this.label &&
          other.description == this.description &&
          other.filters == this.filters &&
          other.active == this.active);
}

class VisibleRangeRuleRowsCompanion
    extends UpdateCompanion<VisibleRangeRuleRow> {
  final Value<String> id;
  final Value<String> rangeId;
  final Value<String> kind;
  final Value<int> position;
  final Value<String> label;
  final Value<String> description;
  final Value<String> filters;
  final Value<bool> active;
  final Value<int> rowid;
  const VisibleRangeRuleRowsCompanion({
    this.id = const Value.absent(),
    this.rangeId = const Value.absent(),
    this.kind = const Value.absent(),
    this.position = const Value.absent(),
    this.label = const Value.absent(),
    this.description = const Value.absent(),
    this.filters = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisibleRangeRuleRowsCompanion.insert({
    required String id,
    required String rangeId,
    required String kind,
    this.position = const Value.absent(),
    this.label = const Value.absent(),
    this.description = const Value.absent(),
    this.filters = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       rangeId = Value(rangeId),
       kind = Value(kind);
  static Insertable<VisibleRangeRuleRow> custom({
    Expression<String>? id,
    Expression<String>? rangeId,
    Expression<String>? kind,
    Expression<int>? position,
    Expression<String>? label,
    Expression<String>? description,
    Expression<String>? filters,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rangeId != null) 'rangeId': rangeId,
      if (kind != null) 'kind': kind,
      if (position != null) 'position': position,
      if (label != null) 'label': label,
      if (description != null) 'description': description,
      if (filters != null) 'filters': filters,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisibleRangeRuleRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? rangeId,
    Value<String>? kind,
    Value<int>? position,
    Value<String>? label,
    Value<String>? description,
    Value<String>? filters,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return VisibleRangeRuleRowsCompanion(
      id: id ?? this.id,
      rangeId: rangeId ?? this.rangeId,
      kind: kind ?? this.kind,
      position: position ?? this.position,
      label: label ?? this.label,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rangeId.present) {
      map['rangeId'] = Variable<String>(rangeId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (filters.present) {
      map['filters'] = Variable<String>(filters.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeRuleRowsCompanion(')
          ..write('id: $id, ')
          ..write('rangeId: $rangeId, ')
          ..write('kind: $kind, ')
          ..write('position: $position, ')
          ..write('label: $label, ')
          ..write('description: $description, ')
          ..write('filters: $filters, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisibleRangeSessionRowsTable extends VisibleRangeSessionRows
    with TableInfo<$VisibleRangeSessionRowsTable, VisibleRangeSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisibleRangeSessionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rangeIdMeta = const VerificationMeta(
    'rangeId',
  );
  @override
  late final GeneratedColumn<String> rangeId = GeneratedColumn<String>(
    'rangeId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<String> ruleId = GeneratedColumn<String>(
    'ruleId',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _initialFiltersMeta = const VerificationMeta(
    'initialFilters',
  );
  @override
  late final GeneratedColumn<String> initialFilters = GeneratedColumn<String>(
    'initialFilters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _finalFiltersMeta = const VerificationMeta(
    'finalFilters',
  );
  @override
  late final GeneratedColumn<String> finalFilters = GeneratedColumn<String>(
    'finalFilters',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'createdAt',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rangeId,
    ruleId,
    kind,
    mode,
    initialFilters,
    finalFilters,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visible_range_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisibleRangeSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rangeId')) {
      context.handle(
        _rangeIdMeta,
        rangeId.isAcceptableOrUnknown(data['rangeId']!, _rangeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rangeIdMeta);
    }
    if (data.containsKey('ruleId')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['ruleId']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('initialFilters')) {
      context.handle(
        _initialFiltersMeta,
        initialFilters.isAcceptableOrUnknown(
          data['initialFilters']!,
          _initialFiltersMeta,
        ),
      );
    }
    if (data.containsKey('finalFilters')) {
      context.handle(
        _finalFiltersMeta,
        finalFilters.isAcceptableOrUnknown(
          data['finalFilters']!,
          _finalFiltersMeta,
        ),
      );
    }
    if (data.containsKey('createdAt')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['createdAt']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisibleRangeSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisibleRangeSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      rangeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rangeId'],
      )!,
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ruleId'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      initialFilters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}initialFilters'],
      )!,
      finalFilters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finalFilters'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}createdAt'],
      )!,
    );
  }

  @override
  $VisibleRangeSessionRowsTable createAlias(String alias) {
    return $VisibleRangeSessionRowsTable(attachedDatabase, alias);
  }
}

class VisibleRangeSessionRow extends DataClass
    implements Insertable<VisibleRangeSessionRow> {
  final String id;
  final String rangeId;
  final String ruleId;
  final String kind;

  /// `override` or `append`.
  final String mode;

  /// JSON array of the media-set filters right after activation.
  final String initialFilters;

  /// JSON array of the media-set filters when the session ended.
  final String finalFilters;
  final int createdAt;
  const VisibleRangeSessionRow({
    required this.id,
    required this.rangeId,
    required this.ruleId,
    required this.kind,
    required this.mode,
    required this.initialFilters,
    required this.finalFilters,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['rangeId'] = Variable<String>(rangeId);
    map['ruleId'] = Variable<String>(ruleId);
    map['kind'] = Variable<String>(kind);
    map['mode'] = Variable<String>(mode);
    map['initialFilters'] = Variable<String>(initialFilters);
    map['finalFilters'] = Variable<String>(finalFilters);
    map['createdAt'] = Variable<int>(createdAt);
    return map;
  }

  VisibleRangeSessionRowsCompanion toCompanion(bool nullToAbsent) {
    return VisibleRangeSessionRowsCompanion(
      id: Value(id),
      rangeId: Value(rangeId),
      ruleId: Value(ruleId),
      kind: Value(kind),
      mode: Value(mode),
      initialFilters: Value(initialFilters),
      finalFilters: Value(finalFilters),
      createdAt: Value(createdAt),
    );
  }

  factory VisibleRangeSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisibleRangeSessionRow(
      id: serializer.fromJson<String>(json['id']),
      rangeId: serializer.fromJson<String>(json['rangeId']),
      ruleId: serializer.fromJson<String>(json['ruleId']),
      kind: serializer.fromJson<String>(json['kind']),
      mode: serializer.fromJson<String>(json['mode']),
      initialFilters: serializer.fromJson<String>(json['initialFilters']),
      finalFilters: serializer.fromJson<String>(json['finalFilters']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rangeId': serializer.toJson<String>(rangeId),
      'ruleId': serializer.toJson<String>(ruleId),
      'kind': serializer.toJson<String>(kind),
      'mode': serializer.toJson<String>(mode),
      'initialFilters': serializer.toJson<String>(initialFilters),
      'finalFilters': serializer.toJson<String>(finalFilters),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  VisibleRangeSessionRow copyWith({
    String? id,
    String? rangeId,
    String? ruleId,
    String? kind,
    String? mode,
    String? initialFilters,
    String? finalFilters,
    int? createdAt,
  }) => VisibleRangeSessionRow(
    id: id ?? this.id,
    rangeId: rangeId ?? this.rangeId,
    ruleId: ruleId ?? this.ruleId,
    kind: kind ?? this.kind,
    mode: mode ?? this.mode,
    initialFilters: initialFilters ?? this.initialFilters,
    finalFilters: finalFilters ?? this.finalFilters,
    createdAt: createdAt ?? this.createdAt,
  );
  VisibleRangeSessionRow copyWithCompanion(
    VisibleRangeSessionRowsCompanion data,
  ) {
    return VisibleRangeSessionRow(
      id: data.id.present ? data.id.value : this.id,
      rangeId: data.rangeId.present ? data.rangeId.value : this.rangeId,
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      kind: data.kind.present ? data.kind.value : this.kind,
      mode: data.mode.present ? data.mode.value : this.mode,
      initialFilters: data.initialFilters.present
          ? data.initialFilters.value
          : this.initialFilters,
      finalFilters: data.finalFilters.present
          ? data.finalFilters.value
          : this.finalFilters,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeSessionRow(')
          ..write('id: $id, ')
          ..write('rangeId: $rangeId, ')
          ..write('ruleId: $ruleId, ')
          ..write('kind: $kind, ')
          ..write('mode: $mode, ')
          ..write('initialFilters: $initialFilters, ')
          ..write('finalFilters: $finalFilters, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rangeId,
    ruleId,
    kind,
    mode,
    initialFilters,
    finalFilters,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisibleRangeSessionRow &&
          other.id == this.id &&
          other.rangeId == this.rangeId &&
          other.ruleId == this.ruleId &&
          other.kind == this.kind &&
          other.mode == this.mode &&
          other.initialFilters == this.initialFilters &&
          other.finalFilters == this.finalFilters &&
          other.createdAt == this.createdAt);
}

class VisibleRangeSessionRowsCompanion
    extends UpdateCompanion<VisibleRangeSessionRow> {
  final Value<String> id;
  final Value<String> rangeId;
  final Value<String> ruleId;
  final Value<String> kind;
  final Value<String> mode;
  final Value<String> initialFilters;
  final Value<String> finalFilters;
  final Value<int> createdAt;
  final Value<int> rowid;
  const VisibleRangeSessionRowsCompanion({
    this.id = const Value.absent(),
    this.rangeId = const Value.absent(),
    this.ruleId = const Value.absent(),
    this.kind = const Value.absent(),
    this.mode = const Value.absent(),
    this.initialFilters = const Value.absent(),
    this.finalFilters = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisibleRangeSessionRowsCompanion.insert({
    required String id,
    required String rangeId,
    required String ruleId,
    required String kind,
    required String mode,
    this.initialFilters = const Value.absent(),
    this.finalFilters = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       rangeId = Value(rangeId),
       ruleId = Value(ruleId),
       kind = Value(kind),
       mode = Value(mode),
       createdAt = Value(createdAt);
  static Insertable<VisibleRangeSessionRow> custom({
    Expression<String>? id,
    Expression<String>? rangeId,
    Expression<String>? ruleId,
    Expression<String>? kind,
    Expression<String>? mode,
    Expression<String>? initialFilters,
    Expression<String>? finalFilters,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rangeId != null) 'rangeId': rangeId,
      if (ruleId != null) 'ruleId': ruleId,
      if (kind != null) 'kind': kind,
      if (mode != null) 'mode': mode,
      if (initialFilters != null) 'initialFilters': initialFilters,
      if (finalFilters != null) 'finalFilters': finalFilters,
      if (createdAt != null) 'createdAt': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisibleRangeSessionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? rangeId,
    Value<String>? ruleId,
    Value<String>? kind,
    Value<String>? mode,
    Value<String>? initialFilters,
    Value<String>? finalFilters,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return VisibleRangeSessionRowsCompanion(
      id: id ?? this.id,
      rangeId: rangeId ?? this.rangeId,
      ruleId: ruleId ?? this.ruleId,
      kind: kind ?? this.kind,
      mode: mode ?? this.mode,
      initialFilters: initialFilters ?? this.initialFilters,
      finalFilters: finalFilters ?? this.finalFilters,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rangeId.present) {
      map['rangeId'] = Variable<String>(rangeId.value);
    }
    if (ruleId.present) {
      map['ruleId'] = Variable<String>(ruleId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (initialFilters.present) {
      map['initialFilters'] = Variable<String>(initialFilters.value);
    }
    if (finalFilters.present) {
      map['finalFilters'] = Variable<String>(finalFilters.value);
    }
    if (createdAt.present) {
      map['createdAt'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeSessionRowsCompanion(')
          ..write('id: $id, ')
          ..write('rangeId: $rangeId, ')
          ..write('ruleId: $ruleId, ')
          ..write('kind: $kind, ')
          ..write('mode: $mode, ')
          ..write('initialFilters: $initialFilters, ')
          ..write('finalFilters: $finalFilters, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisibleRangeKeyValuesTable extends VisibleRangeKeyValues
    with TableInfo<$VisibleRangeKeyValuesTable, VisibleRangeKeyValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisibleRangeKeyValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visible_range_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisibleRangeKeyValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  VisibleRangeKeyValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisibleRangeKeyValue(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $VisibleRangeKeyValuesTable createAlias(String alias) {
    return $VisibleRangeKeyValuesTable(attachedDatabase, alias);
  }
}

class VisibleRangeKeyValue extends DataClass
    implements Insertable<VisibleRangeKeyValue> {
  final String key;
  final String? value;
  const VisibleRangeKeyValue({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  VisibleRangeKeyValuesCompanion toCompanion(bool nullToAbsent) {
    return VisibleRangeKeyValuesCompanion(
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory VisibleRangeKeyValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisibleRangeKeyValue(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  VisibleRangeKeyValue copyWith({
    String? key,
    Value<String?> value = const Value.absent(),
  }) => VisibleRangeKeyValue(
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  VisibleRangeKeyValue copyWithCompanion(VisibleRangeKeyValuesCompanion data) {
    return VisibleRangeKeyValue(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeKeyValue(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisibleRangeKeyValue &&
          other.key == this.key &&
          other.value == this.value);
}

class VisibleRangeKeyValuesCompanion
    extends UpdateCompanion<VisibleRangeKeyValue> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const VisibleRangeKeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisibleRangeKeyValuesCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<VisibleRangeKeyValue> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisibleRangeKeyValuesCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return VisibleRangeKeyValuesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisibleRangeKeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EntriesTableTable entriesTable = $EntriesTableTable(this);
  late final $DateTakenTableTable dateTakenTable = $DateTakenTableTable(this);
  late final $MetadataTableTable metadataTable = $MetadataTableTable(this);
  late final $AddressesTableTable addressesTable = $AddressesTableTable(this);
  late final $FavouritesTableTable favouritesTable = $FavouritesTableTable(
    this,
  );
  late final $CoversTableTable coversTable = $CoversTableTable(this);
  late final $DynamicAlbumsTableTable dynamicAlbumsTable =
      $DynamicAlbumsTableTable(this);
  late final $VaultsTableTable vaultsTable = $VaultsTableTable(this);
  late final $TrashTableTable trashTable = $TrashTableTable(this);
  late final $VideoPlaybackTableTable videoPlaybackTable =
      $VideoPlaybackTableTable(this);
  late final $DebugTableTable debugTable = $DebugTableTable(this);
  late final $AppMetaTableTable appMetaTable = $AppMetaTableTable(this);
  late final $SettingsValuesTableTable settingsValuesTable =
      $SettingsValuesTableTable(this);
  late final $VisibleRangePresetRowsTable visibleRangePresetRows =
      $VisibleRangePresetRowsTable(this);
  late final $VisibleRangeRowsTable visibleRangeRows = $VisibleRangeRowsTable(
    this,
  );
  late final $VisibleRangeRuleRowsTable visibleRangeRuleRows =
      $VisibleRangeRuleRowsTable(this);
  late final $VisibleRangeSessionRowsTable visibleRangeSessionRows =
      $VisibleRangeSessionRowsTable(this);
  late final $VisibleRangeKeyValuesTable visibleRangeKeyValues =
      $VisibleRangeKeyValuesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    entriesTable,
    dateTakenTable,
    metadataTable,
    addressesTable,
    favouritesTable,
    coversTable,
    dynamicAlbumsTable,
    vaultsTable,
    trashTable,
    videoPlaybackTable,
    debugTable,
    appMetaTable,
    settingsValuesTable,
    visibleRangePresetRows,
    visibleRangeRows,
    visibleRangeRuleRows,
    visibleRangeSessionRows,
    visibleRangeKeyValues,
  ];
}

typedef $$EntriesTableTableCreateCompanionBuilder =
    EntriesTableCompanion Function({
      Value<int> id,
      Value<int?> contentId,
      Value<String?> uri,
      Value<String?> path,
      Value<String?> sourceMimeType,
      Value<int?> width,
      Value<int?> height,
      Value<int?> sourceRotationDegrees,
      Value<int?> sizeBytes,
      Value<String?> title,
      Value<int?> dateAddedSecs,
      Value<int?> dateModifiedMillis,
      Value<int?> sourceDateTakenMillis,
      Value<int?> durationMillis,
      Value<int?> trashed,
      Value<int?> origin,
      Value<String?> directory,
      Value<String?> baseName,
      Value<String?> stackKey,
      Value<int?> stackTileId,
    });
typedef $$EntriesTableTableUpdateCompanionBuilder =
    EntriesTableCompanion Function({
      Value<int> id,
      Value<int?> contentId,
      Value<String?> uri,
      Value<String?> path,
      Value<String?> sourceMimeType,
      Value<int?> width,
      Value<int?> height,
      Value<int?> sourceRotationDegrees,
      Value<int?> sizeBytes,
      Value<String?> title,
      Value<int?> dateAddedSecs,
      Value<int?> dateModifiedMillis,
      Value<int?> sourceDateTakenMillis,
      Value<int?> durationMillis,
      Value<int?> trashed,
      Value<int?> origin,
      Value<String?> directory,
      Value<String?> baseName,
      Value<String?> stackKey,
      Value<int?> stackTileId,
    });

class $$EntriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $EntriesTableTable> {
  $$EntriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMimeType => $composableBuilder(
    column: $table.sourceMimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceRotationDegrees => $composableBuilder(
    column: $table.sourceRotationDegrees,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateAddedSecs => $composableBuilder(
    column: $table.dateAddedSecs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateModifiedMillis => $composableBuilder(
    column: $table.dateModifiedMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceDateTakenMillis => $composableBuilder(
    column: $table.sourceDateTakenMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trashed => $composableBuilder(
    column: $table.trashed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseName => $composableBuilder(
    column: $table.baseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stackKey => $composableBuilder(
    column: $table.stackKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stackTileId => $composableBuilder(
    column: $table.stackTileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $EntriesTableTable> {
  $$EntriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMimeType => $composableBuilder(
    column: $table.sourceMimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceRotationDegrees => $composableBuilder(
    column: $table.sourceRotationDegrees,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateAddedSecs => $composableBuilder(
    column: $table.dateAddedSecs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateModifiedMillis => $composableBuilder(
    column: $table.dateModifiedMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceDateTakenMillis => $composableBuilder(
    column: $table.sourceDateTakenMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trashed => $composableBuilder(
    column: $table.trashed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseName => $composableBuilder(
    column: $table.baseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stackKey => $composableBuilder(
    column: $table.stackKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stackTileId => $composableBuilder(
    column: $table.stackTileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntriesTableTable> {
  $$EntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get sourceMimeType => $composableBuilder(
    column: $table.sourceMimeType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get sourceRotationDegrees => $composableBuilder(
    column: $table.sourceRotationDegrees,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get dateAddedSecs => $composableBuilder(
    column: $table.dateAddedSecs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dateModifiedMillis => $composableBuilder(
    column: $table.dateModifiedMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceDateTakenMillis => $composableBuilder(
    column: $table.sourceDateTakenMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMillis => $composableBuilder(
    column: $table.durationMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trashed =>
      $composableBuilder(column: $table.trashed, builder: (column) => column);

  GeneratedColumn<int> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<String> get baseName =>
      $composableBuilder(column: $table.baseName, builder: (column) => column);

  GeneratedColumn<String> get stackKey =>
      $composableBuilder(column: $table.stackKey, builder: (column) => column);

  GeneratedColumn<int> get stackTileId => $composableBuilder(
    column: $table.stackTileId,
    builder: (column) => column,
  );
}

class $$EntriesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntriesTableTable,
          EntriesTableData,
          $$EntriesTableTableFilterComposer,
          $$EntriesTableTableOrderingComposer,
          $$EntriesTableTableAnnotationComposer,
          $$EntriesTableTableCreateCompanionBuilder,
          $$EntriesTableTableUpdateCompanionBuilder,
          (
            EntriesTableData,
            BaseReferences<_$AppDatabase, $EntriesTableTable, EntriesTableData>,
          ),
          EntriesTableData,
          PrefetchHooks Function()
        > {
  $$EntriesTableTableTableManager(_$AppDatabase db, $EntriesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> contentId = const Value.absent(),
                Value<String?> uri = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<String?> sourceMimeType = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> sourceRotationDegrees = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<int?> dateAddedSecs = const Value.absent(),
                Value<int?> dateModifiedMillis = const Value.absent(),
                Value<int?> sourceDateTakenMillis = const Value.absent(),
                Value<int?> durationMillis = const Value.absent(),
                Value<int?> trashed = const Value.absent(),
                Value<int?> origin = const Value.absent(),
                Value<String?> directory = const Value.absent(),
                Value<String?> baseName = const Value.absent(),
                Value<String?> stackKey = const Value.absent(),
                Value<int?> stackTileId = const Value.absent(),
              }) => EntriesTableCompanion(
                id: id,
                contentId: contentId,
                uri: uri,
                path: path,
                sourceMimeType: sourceMimeType,
                width: width,
                height: height,
                sourceRotationDegrees: sourceRotationDegrees,
                sizeBytes: sizeBytes,
                title: title,
                dateAddedSecs: dateAddedSecs,
                dateModifiedMillis: dateModifiedMillis,
                sourceDateTakenMillis: sourceDateTakenMillis,
                durationMillis: durationMillis,
                trashed: trashed,
                origin: origin,
                directory: directory,
                baseName: baseName,
                stackKey: stackKey,
                stackTileId: stackTileId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> contentId = const Value.absent(),
                Value<String?> uri = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<String?> sourceMimeType = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> sourceRotationDegrees = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<int?> dateAddedSecs = const Value.absent(),
                Value<int?> dateModifiedMillis = const Value.absent(),
                Value<int?> sourceDateTakenMillis = const Value.absent(),
                Value<int?> durationMillis = const Value.absent(),
                Value<int?> trashed = const Value.absent(),
                Value<int?> origin = const Value.absent(),
                Value<String?> directory = const Value.absent(),
                Value<String?> baseName = const Value.absent(),
                Value<String?> stackKey = const Value.absent(),
                Value<int?> stackTileId = const Value.absent(),
              }) => EntriesTableCompanion.insert(
                id: id,
                contentId: contentId,
                uri: uri,
                path: path,
                sourceMimeType: sourceMimeType,
                width: width,
                height: height,
                sourceRotationDegrees: sourceRotationDegrees,
                sizeBytes: sizeBytes,
                title: title,
                dateAddedSecs: dateAddedSecs,
                dateModifiedMillis: dateModifiedMillis,
                sourceDateTakenMillis: sourceDateTakenMillis,
                durationMillis: durationMillis,
                trashed: trashed,
                origin: origin,
                directory: directory,
                baseName: baseName,
                stackKey: stackKey,
                stackTileId: stackTileId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntriesTableTable,
      EntriesTableData,
      $$EntriesTableTableFilterComposer,
      $$EntriesTableTableOrderingComposer,
      $$EntriesTableTableAnnotationComposer,
      $$EntriesTableTableCreateCompanionBuilder,
      $$EntriesTableTableUpdateCompanionBuilder,
      (
        EntriesTableData,
        BaseReferences<_$AppDatabase, $EntriesTableTable, EntriesTableData>,
      ),
      EntriesTableData,
      PrefetchHooks Function()
    >;
typedef $$DateTakenTableTableCreateCompanionBuilder =
    DateTakenTableCompanion Function({Value<int> id, Value<int?> dateMillis});
typedef $$DateTakenTableTableUpdateCompanionBuilder =
    DateTakenTableCompanion Function({Value<int> id, Value<int?> dateMillis});

class $$DateTakenTableTableFilterComposer
    extends Composer<_$AppDatabase, $DateTakenTableTable> {
  $$DateTakenTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DateTakenTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DateTakenTableTable> {
  $$DateTakenTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DateTakenTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DateTakenTableTable> {
  $$DateTakenTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => column,
  );
}

class $$DateTakenTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DateTakenTableTable,
          DateTakenTableData,
          $$DateTakenTableTableFilterComposer,
          $$DateTakenTableTableOrderingComposer,
          $$DateTakenTableTableAnnotationComposer,
          $$DateTakenTableTableCreateCompanionBuilder,
          $$DateTakenTableTableUpdateCompanionBuilder,
          (
            DateTakenTableData,
            BaseReferences<
              _$AppDatabase,
              $DateTakenTableTable,
              DateTakenTableData
            >,
          ),
          DateTakenTableData,
          PrefetchHooks Function()
        > {
  $$DateTakenTableTableTableManager(
    _$AppDatabase db,
    $DateTakenTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DateTakenTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DateTakenTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DateTakenTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
              }) => DateTakenTableCompanion(id: id, dateMillis: dateMillis),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
              }) => DateTakenTableCompanion.insert(
                id: id,
                dateMillis: dateMillis,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DateTakenTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DateTakenTableTable,
      DateTakenTableData,
      $$DateTakenTableTableFilterComposer,
      $$DateTakenTableTableOrderingComposer,
      $$DateTakenTableTableAnnotationComposer,
      $$DateTakenTableTableCreateCompanionBuilder,
      $$DateTakenTableTableUpdateCompanionBuilder,
      (
        DateTakenTableData,
        BaseReferences<_$AppDatabase, $DateTakenTableTable, DateTakenTableData>,
      ),
      DateTakenTableData,
      PrefetchHooks Function()
    >;
typedef $$MetadataTableTableCreateCompanionBuilder =
    MetadataTableCompanion Function({
      Value<int> id,
      Value<String?> mimeType,
      Value<int?> dateMillis,
      Value<int?> flags,
      Value<int?> rotationDegrees,
      Value<String?> xmpSubjects,
      Value<String?> xmpTitle,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> rating,
    });
typedef $$MetadataTableTableUpdateCompanionBuilder =
    MetadataTableCompanion Function({
      Value<int> id,
      Value<String?> mimeType,
      Value<int?> dateMillis,
      Value<int?> flags,
      Value<int?> rotationDegrees,
      Value<String?> xmpSubjects,
      Value<String?> xmpTitle,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> rating,
    });

class $$MetadataTableTableFilterComposer
    extends Composer<_$AppDatabase, $MetadataTableTable> {
  $$MetadataTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rotationDegrees => $composableBuilder(
    column: $table.rotationDegrees,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get xmpSubjects => $composableBuilder(
    column: $table.xmpSubjects,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get xmpTitle => $composableBuilder(
    column: $table.xmpTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetadataTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MetadataTableTable> {
  $$MetadataTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rotationDegrees => $composableBuilder(
    column: $table.rotationDegrees,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get xmpSubjects => $composableBuilder(
    column: $table.xmpSubjects,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get xmpTitle => $composableBuilder(
    column: $table.xmpTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetadataTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetadataTableTable> {
  $$MetadataTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<int> get rotationDegrees => $composableBuilder(
    column: $table.rotationDegrees,
    builder: (column) => column,
  );

  GeneratedColumn<String> get xmpSubjects => $composableBuilder(
    column: $table.xmpSubjects,
    builder: (column) => column,
  );

  GeneratedColumn<String> get xmpTitle =>
      $composableBuilder(column: $table.xmpTitle, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);
}

class $$MetadataTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetadataTableTable,
          MetadataTableData,
          $$MetadataTableTableFilterComposer,
          $$MetadataTableTableOrderingComposer,
          $$MetadataTableTableAnnotationComposer,
          $$MetadataTableTableCreateCompanionBuilder,
          $$MetadataTableTableUpdateCompanionBuilder,
          (
            MetadataTableData,
            BaseReferences<
              _$AppDatabase,
              $MetadataTableTable,
              MetadataTableData
            >,
          ),
          MetadataTableData,
          PrefetchHooks Function()
        > {
  $$MetadataTableTableTableManager(_$AppDatabase db, $MetadataTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetadataTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetadataTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetadataTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
                Value<int?> flags = const Value.absent(),
                Value<int?> rotationDegrees = const Value.absent(),
                Value<String?> xmpSubjects = const Value.absent(),
                Value<String?> xmpTitle = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> rating = const Value.absent(),
              }) => MetadataTableCompanion(
                id: id,
                mimeType: mimeType,
                dateMillis: dateMillis,
                flags: flags,
                rotationDegrees: rotationDegrees,
                xmpSubjects: xmpSubjects,
                xmpTitle: xmpTitle,
                latitude: latitude,
                longitude: longitude,
                rating: rating,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
                Value<int?> flags = const Value.absent(),
                Value<int?> rotationDegrees = const Value.absent(),
                Value<String?> xmpSubjects = const Value.absent(),
                Value<String?> xmpTitle = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> rating = const Value.absent(),
              }) => MetadataTableCompanion.insert(
                id: id,
                mimeType: mimeType,
                dateMillis: dateMillis,
                flags: flags,
                rotationDegrees: rotationDegrees,
                xmpSubjects: xmpSubjects,
                xmpTitle: xmpTitle,
                latitude: latitude,
                longitude: longitude,
                rating: rating,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetadataTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetadataTableTable,
      MetadataTableData,
      $$MetadataTableTableFilterComposer,
      $$MetadataTableTableOrderingComposer,
      $$MetadataTableTableAnnotationComposer,
      $$MetadataTableTableCreateCompanionBuilder,
      $$MetadataTableTableUpdateCompanionBuilder,
      (
        MetadataTableData,
        BaseReferences<_$AppDatabase, $MetadataTableTable, MetadataTableData>,
      ),
      MetadataTableData,
      PrefetchHooks Function()
    >;
typedef $$AddressesTableTableCreateCompanionBuilder =
    AddressesTableCompanion Function({
      Value<int> id,
      Value<String?> addressLine,
      Value<String?> countryCode,
      Value<String?> countryName,
      Value<String?> adminArea,
      Value<String?> locality,
    });
typedef $$AddressesTableTableUpdateCompanionBuilder =
    AddressesTableCompanion Function({
      Value<int> id,
      Value<String?> addressLine,
      Value<String?> countryCode,
      Value<String?> countryName,
      Value<String?> adminArea,
      Value<String?> locality,
    });

class $$AddressesTableTableFilterComposer
    extends Composer<_$AppDatabase, $AddressesTableTable> {
  $$AddressesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressLine => $composableBuilder(
    column: $table.addressLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryName => $composableBuilder(
    column: $table.countryName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get adminArea => $composableBuilder(
    column: $table.adminArea,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddressesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AddressesTableTable> {
  $$AddressesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressLine => $composableBuilder(
    column: $table.addressLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryName => $composableBuilder(
    column: $table.countryName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get adminArea => $composableBuilder(
    column: $table.adminArea,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddressesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AddressesTableTable> {
  $$AddressesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get addressLine => $composableBuilder(
    column: $table.addressLine,
    builder: (column) => column,
  );

  GeneratedColumn<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get countryName => $composableBuilder(
    column: $table.countryName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get adminArea =>
      $composableBuilder(column: $table.adminArea, builder: (column) => column);

  GeneratedColumn<String> get locality =>
      $composableBuilder(column: $table.locality, builder: (column) => column);
}

class $$AddressesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AddressesTableTable,
          AddressesTableData,
          $$AddressesTableTableFilterComposer,
          $$AddressesTableTableOrderingComposer,
          $$AddressesTableTableAnnotationComposer,
          $$AddressesTableTableCreateCompanionBuilder,
          $$AddressesTableTableUpdateCompanionBuilder,
          (
            AddressesTableData,
            BaseReferences<
              _$AppDatabase,
              $AddressesTableTable,
              AddressesTableData
            >,
          ),
          AddressesTableData,
          PrefetchHooks Function()
        > {
  $$AddressesTableTableTableManager(
    _$AppDatabase db,
    $AddressesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddressesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddressesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddressesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> addressLine = const Value.absent(),
                Value<String?> countryCode = const Value.absent(),
                Value<String?> countryName = const Value.absent(),
                Value<String?> adminArea = const Value.absent(),
                Value<String?> locality = const Value.absent(),
              }) => AddressesTableCompanion(
                id: id,
                addressLine: addressLine,
                countryCode: countryCode,
                countryName: countryName,
                adminArea: adminArea,
                locality: locality,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> addressLine = const Value.absent(),
                Value<String?> countryCode = const Value.absent(),
                Value<String?> countryName = const Value.absent(),
                Value<String?> adminArea = const Value.absent(),
                Value<String?> locality = const Value.absent(),
              }) => AddressesTableCompanion.insert(
                id: id,
                addressLine: addressLine,
                countryCode: countryCode,
                countryName: countryName,
                adminArea: adminArea,
                locality: locality,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AddressesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AddressesTableTable,
      AddressesTableData,
      $$AddressesTableTableFilterComposer,
      $$AddressesTableTableOrderingComposer,
      $$AddressesTableTableAnnotationComposer,
      $$AddressesTableTableCreateCompanionBuilder,
      $$AddressesTableTableUpdateCompanionBuilder,
      (
        AddressesTableData,
        BaseReferences<_$AppDatabase, $AddressesTableTable, AddressesTableData>,
      ),
      AddressesTableData,
      PrefetchHooks Function()
    >;
typedef $$FavouritesTableTableCreateCompanionBuilder =
    FavouritesTableCompanion Function({Value<int> id});
typedef $$FavouritesTableTableUpdateCompanionBuilder =
    FavouritesTableCompanion Function({Value<int> id});

class $$FavouritesTableTableFilterComposer
    extends Composer<_$AppDatabase, $FavouritesTableTable> {
  $$FavouritesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavouritesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $FavouritesTableTable> {
  $$FavouritesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavouritesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavouritesTableTable> {
  $$FavouritesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$FavouritesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavouritesTableTable,
          FavouritesTableData,
          $$FavouritesTableTableFilterComposer,
          $$FavouritesTableTableOrderingComposer,
          $$FavouritesTableTableAnnotationComposer,
          $$FavouritesTableTableCreateCompanionBuilder,
          $$FavouritesTableTableUpdateCompanionBuilder,
          (
            FavouritesTableData,
            BaseReferences<
              _$AppDatabase,
              $FavouritesTableTable,
              FavouritesTableData
            >,
          ),
          FavouritesTableData,
          PrefetchHooks Function()
        > {
  $$FavouritesTableTableTableManager(
    _$AppDatabase db,
    $FavouritesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavouritesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavouritesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavouritesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              FavouritesTableCompanion(id: id),
          createCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              FavouritesTableCompanion.insert(id: id),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavouritesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavouritesTableTable,
      FavouritesTableData,
      $$FavouritesTableTableFilterComposer,
      $$FavouritesTableTableOrderingComposer,
      $$FavouritesTableTableAnnotationComposer,
      $$FavouritesTableTableCreateCompanionBuilder,
      $$FavouritesTableTableUpdateCompanionBuilder,
      (
        FavouritesTableData,
        BaseReferences<
          _$AppDatabase,
          $FavouritesTableTable,
          FavouritesTableData
        >,
      ),
      FavouritesTableData,
      PrefetchHooks Function()
    >;
typedef $$CoversTableTableCreateCompanionBuilder =
    CoversTableCompanion Function({
      required String filter,
      Value<int?> entryId,
      Value<String?> packageName,
      Value<String?> color,
      Value<int> rowid,
    });
typedef $$CoversTableTableUpdateCompanionBuilder =
    CoversTableCompanion Function({
      Value<String> filter,
      Value<int?> entryId,
      Value<String?> packageName,
      Value<String?> color,
      Value<int> rowid,
    });

class $$CoversTableTableFilterComposer
    extends Composer<_$AppDatabase, $CoversTableTable> {
  $$CoversTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get filter => $composableBuilder(
    column: $table.filter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoversTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CoversTableTable> {
  $$CoversTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get filter => $composableBuilder(
    column: $table.filter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoversTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoversTableTable> {
  $$CoversTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get filter =>
      $composableBuilder(column: $table.filter, builder: (column) => column);

  GeneratedColumn<int> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);
}

class $$CoversTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoversTableTable,
          CoversTableData,
          $$CoversTableTableFilterComposer,
          $$CoversTableTableOrderingComposer,
          $$CoversTableTableAnnotationComposer,
          $$CoversTableTableCreateCompanionBuilder,
          $$CoversTableTableUpdateCompanionBuilder,
          (
            CoversTableData,
            BaseReferences<_$AppDatabase, $CoversTableTable, CoversTableData>,
          ),
          CoversTableData,
          PrefetchHooks Function()
        > {
  $$CoversTableTableTableManager(_$AppDatabase db, $CoversTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoversTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoversTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoversTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> filter = const Value.absent(),
                Value<int?> entryId = const Value.absent(),
                Value<String?> packageName = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoversTableCompanion(
                filter: filter,
                entryId: entryId,
                packageName: packageName,
                color: color,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String filter,
                Value<int?> entryId = const Value.absent(),
                Value<String?> packageName = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoversTableCompanion.insert(
                filter: filter,
                entryId: entryId,
                packageName: packageName,
                color: color,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoversTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoversTableTable,
      CoversTableData,
      $$CoversTableTableFilterComposer,
      $$CoversTableTableOrderingComposer,
      $$CoversTableTableAnnotationComposer,
      $$CoversTableTableCreateCompanionBuilder,
      $$CoversTableTableUpdateCompanionBuilder,
      (
        CoversTableData,
        BaseReferences<_$AppDatabase, $CoversTableTable, CoversTableData>,
      ),
      CoversTableData,
      PrefetchHooks Function()
    >;
typedef $$DynamicAlbumsTableTableCreateCompanionBuilder =
    DynamicAlbumsTableCompanion Function({
      required String name,
      Value<String?> filter,
      Value<int> rowid,
    });
typedef $$DynamicAlbumsTableTableUpdateCompanionBuilder =
    DynamicAlbumsTableCompanion Function({
      Value<String> name,
      Value<String?> filter,
      Value<int> rowid,
    });

class $$DynamicAlbumsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DynamicAlbumsTableTable> {
  $$DynamicAlbumsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filter => $composableBuilder(
    column: $table.filter,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DynamicAlbumsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DynamicAlbumsTableTable> {
  $$DynamicAlbumsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filter => $composableBuilder(
    column: $table.filter,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DynamicAlbumsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DynamicAlbumsTableTable> {
  $$DynamicAlbumsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get filter =>
      $composableBuilder(column: $table.filter, builder: (column) => column);
}

class $$DynamicAlbumsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DynamicAlbumsTableTable,
          DynamicAlbumsTableData,
          $$DynamicAlbumsTableTableFilterComposer,
          $$DynamicAlbumsTableTableOrderingComposer,
          $$DynamicAlbumsTableTableAnnotationComposer,
          $$DynamicAlbumsTableTableCreateCompanionBuilder,
          $$DynamicAlbumsTableTableUpdateCompanionBuilder,
          (
            DynamicAlbumsTableData,
            BaseReferences<
              _$AppDatabase,
              $DynamicAlbumsTableTable,
              DynamicAlbumsTableData
            >,
          ),
          DynamicAlbumsTableData,
          PrefetchHooks Function()
        > {
  $$DynamicAlbumsTableTableTableManager(
    _$AppDatabase db,
    $DynamicAlbumsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DynamicAlbumsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DynamicAlbumsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DynamicAlbumsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<String?> filter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DynamicAlbumsTableCompanion(
                name: name,
                filter: filter,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                Value<String?> filter = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DynamicAlbumsTableCompanion.insert(
                name: name,
                filter: filter,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DynamicAlbumsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DynamicAlbumsTableTable,
      DynamicAlbumsTableData,
      $$DynamicAlbumsTableTableFilterComposer,
      $$DynamicAlbumsTableTableOrderingComposer,
      $$DynamicAlbumsTableTableAnnotationComposer,
      $$DynamicAlbumsTableTableCreateCompanionBuilder,
      $$DynamicAlbumsTableTableUpdateCompanionBuilder,
      (
        DynamicAlbumsTableData,
        BaseReferences<
          _$AppDatabase,
          $DynamicAlbumsTableTable,
          DynamicAlbumsTableData
        >,
      ),
      DynamicAlbumsTableData,
      PrefetchHooks Function()
    >;
typedef $$VaultsTableTableCreateCompanionBuilder =
    VaultsTableCompanion Function({
      required String name,
      Value<int?> autoLock,
      Value<int?> useBin,
      Value<String?> lockType,
      Value<int> rowid,
    });
typedef $$VaultsTableTableUpdateCompanionBuilder =
    VaultsTableCompanion Function({
      Value<String> name,
      Value<int?> autoLock,
      Value<int?> useBin,
      Value<String?> lockType,
      Value<int> rowid,
    });

class $$VaultsTableTableFilterComposer
    extends Composer<_$AppDatabase, $VaultsTableTable> {
  $$VaultsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get autoLock => $composableBuilder(
    column: $table.autoLock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useBin => $composableBuilder(
    column: $table.useBin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockType => $composableBuilder(
    column: $table.lockType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VaultsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $VaultsTableTable> {
  $$VaultsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get autoLock => $composableBuilder(
    column: $table.autoLock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useBin => $composableBuilder(
    column: $table.useBin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockType => $composableBuilder(
    column: $table.lockType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VaultsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $VaultsTableTable> {
  $$VaultsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get autoLock =>
      $composableBuilder(column: $table.autoLock, builder: (column) => column);

  GeneratedColumn<int> get useBin =>
      $composableBuilder(column: $table.useBin, builder: (column) => column);

  GeneratedColumn<String> get lockType =>
      $composableBuilder(column: $table.lockType, builder: (column) => column);
}

class $$VaultsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VaultsTableTable,
          VaultsTableData,
          $$VaultsTableTableFilterComposer,
          $$VaultsTableTableOrderingComposer,
          $$VaultsTableTableAnnotationComposer,
          $$VaultsTableTableCreateCompanionBuilder,
          $$VaultsTableTableUpdateCompanionBuilder,
          (
            VaultsTableData,
            BaseReferences<_$AppDatabase, $VaultsTableTable, VaultsTableData>,
          ),
          VaultsTableData,
          PrefetchHooks Function()
        > {
  $$VaultsTableTableTableManager(_$AppDatabase db, $VaultsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<int?> autoLock = const Value.absent(),
                Value<int?> useBin = const Value.absent(),
                Value<String?> lockType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VaultsTableCompanion(
                name: name,
                autoLock: autoLock,
                useBin: useBin,
                lockType: lockType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                Value<int?> autoLock = const Value.absent(),
                Value<int?> useBin = const Value.absent(),
                Value<String?> lockType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VaultsTableCompanion.insert(
                name: name,
                autoLock: autoLock,
                useBin: useBin,
                lockType: lockType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VaultsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VaultsTableTable,
      VaultsTableData,
      $$VaultsTableTableFilterComposer,
      $$VaultsTableTableOrderingComposer,
      $$VaultsTableTableAnnotationComposer,
      $$VaultsTableTableCreateCompanionBuilder,
      $$VaultsTableTableUpdateCompanionBuilder,
      (
        VaultsTableData,
        BaseReferences<_$AppDatabase, $VaultsTableTable, VaultsTableData>,
      ),
      VaultsTableData,
      PrefetchHooks Function()
    >;
typedef $$TrashTableTableCreateCompanionBuilder =
    TrashTableCompanion Function({
      Value<int> id,
      Value<String?> path,
      Value<int?> dateMillis,
    });
typedef $$TrashTableTableUpdateCompanionBuilder =
    TrashTableCompanion Function({
      Value<int> id,
      Value<String?> path,
      Value<int?> dateMillis,
    });

class $$TrashTableTableFilterComposer
    extends Composer<_$AppDatabase, $TrashTableTable> {
  $$TrashTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrashTableTableOrderingComposer
    extends Composer<_$AppDatabase, $TrashTableTable> {
  $$TrashTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrashTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrashTableTable> {
  $$TrashTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get dateMillis => $composableBuilder(
    column: $table.dateMillis,
    builder: (column) => column,
  );
}

class $$TrashTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrashTableTable,
          TrashTableData,
          $$TrashTableTableFilterComposer,
          $$TrashTableTableOrderingComposer,
          $$TrashTableTableAnnotationComposer,
          $$TrashTableTableCreateCompanionBuilder,
          $$TrashTableTableUpdateCompanionBuilder,
          (
            TrashTableData,
            BaseReferences<_$AppDatabase, $TrashTableTable, TrashTableData>,
          ),
          TrashTableData,
          PrefetchHooks Function()
        > {
  $$TrashTableTableTableManager(_$AppDatabase db, $TrashTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrashTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrashTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrashTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
              }) => TrashTableCompanion(
                id: id,
                path: path,
                dateMillis: dateMillis,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<int?> dateMillis = const Value.absent(),
              }) => TrashTableCompanion.insert(
                id: id,
                path: path,
                dateMillis: dateMillis,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrashTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrashTableTable,
      TrashTableData,
      $$TrashTableTableFilterComposer,
      $$TrashTableTableOrderingComposer,
      $$TrashTableTableAnnotationComposer,
      $$TrashTableTableCreateCompanionBuilder,
      $$TrashTableTableUpdateCompanionBuilder,
      (
        TrashTableData,
        BaseReferences<_$AppDatabase, $TrashTableTable, TrashTableData>,
      ),
      TrashTableData,
      PrefetchHooks Function()
    >;
typedef $$VideoPlaybackTableTableCreateCompanionBuilder =
    VideoPlaybackTableCompanion Function({
      Value<int> id,
      Value<int?> resumeTimeMillis,
    });
typedef $$VideoPlaybackTableTableUpdateCompanionBuilder =
    VideoPlaybackTableCompanion Function({
      Value<int> id,
      Value<int?> resumeTimeMillis,
    });

class $$VideoPlaybackTableTableFilterComposer
    extends Composer<_$AppDatabase, $VideoPlaybackTableTable> {
  $$VideoPlaybackTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resumeTimeMillis => $composableBuilder(
    column: $table.resumeTimeMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VideoPlaybackTableTableOrderingComposer
    extends Composer<_$AppDatabase, $VideoPlaybackTableTable> {
  $$VideoPlaybackTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resumeTimeMillis => $composableBuilder(
    column: $table.resumeTimeMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VideoPlaybackTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $VideoPlaybackTableTable> {
  $$VideoPlaybackTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get resumeTimeMillis => $composableBuilder(
    column: $table.resumeTimeMillis,
    builder: (column) => column,
  );
}

class $$VideoPlaybackTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VideoPlaybackTableTable,
          VideoPlaybackTableData,
          $$VideoPlaybackTableTableFilterComposer,
          $$VideoPlaybackTableTableOrderingComposer,
          $$VideoPlaybackTableTableAnnotationComposer,
          $$VideoPlaybackTableTableCreateCompanionBuilder,
          $$VideoPlaybackTableTableUpdateCompanionBuilder,
          (
            VideoPlaybackTableData,
            BaseReferences<
              _$AppDatabase,
              $VideoPlaybackTableTable,
              VideoPlaybackTableData
            >,
          ),
          VideoPlaybackTableData,
          PrefetchHooks Function()
        > {
  $$VideoPlaybackTableTableTableManager(
    _$AppDatabase db,
    $VideoPlaybackTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VideoPlaybackTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VideoPlaybackTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VideoPlaybackTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> resumeTimeMillis = const Value.absent(),
              }) => VideoPlaybackTableCompanion(
                id: id,
                resumeTimeMillis: resumeTimeMillis,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> resumeTimeMillis = const Value.absent(),
              }) => VideoPlaybackTableCompanion.insert(
                id: id,
                resumeTimeMillis: resumeTimeMillis,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VideoPlaybackTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VideoPlaybackTableTable,
      VideoPlaybackTableData,
      $$VideoPlaybackTableTableFilterComposer,
      $$VideoPlaybackTableTableOrderingComposer,
      $$VideoPlaybackTableTableAnnotationComposer,
      $$VideoPlaybackTableTableCreateCompanionBuilder,
      $$VideoPlaybackTableTableUpdateCompanionBuilder,
      (
        VideoPlaybackTableData,
        BaseReferences<
          _$AppDatabase,
          $VideoPlaybackTableTable,
          VideoPlaybackTableData
        >,
      ),
      VideoPlaybackTableData,
      PrefetchHooks Function()
    >;
typedef $$DebugTableTableCreateCompanionBuilder =
    DebugTableCompanion Function({Value<int> id, Value<String?> message});
typedef $$DebugTableTableUpdateCompanionBuilder =
    DebugTableCompanion Function({Value<int> id, Value<String?> message});

class $$DebugTableTableFilterComposer
    extends Composer<_$AppDatabase, $DebugTableTable> {
  $$DebugTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DebugTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DebugTableTable> {
  $$DebugTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DebugTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DebugTableTable> {
  $$DebugTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);
}

class $$DebugTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DebugTableTable,
          DebugTableData,
          $$DebugTableTableFilterComposer,
          $$DebugTableTableOrderingComposer,
          $$DebugTableTableAnnotationComposer,
          $$DebugTableTableCreateCompanionBuilder,
          $$DebugTableTableUpdateCompanionBuilder,
          (
            DebugTableData,
            BaseReferences<_$AppDatabase, $DebugTableTable, DebugTableData>,
          ),
          DebugTableData,
          PrefetchHooks Function()
        > {
  $$DebugTableTableTableManager(_$AppDatabase db, $DebugTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DebugTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DebugTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DebugTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> message = const Value.absent(),
              }) => DebugTableCompanion(id: id, message: message),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> message = const Value.absent(),
              }) => DebugTableCompanion.insert(id: id, message: message),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DebugTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DebugTableTable,
      DebugTableData,
      $$DebugTableTableFilterComposer,
      $$DebugTableTableOrderingComposer,
      $$DebugTableTableAnnotationComposer,
      $$DebugTableTableCreateCompanionBuilder,
      $$DebugTableTableUpdateCompanionBuilder,
      (
        DebugTableData,
        BaseReferences<_$AppDatabase, $DebugTableTable, DebugTableData>,
      ),
      DebugTableData,
      PrefetchHooks Function()
    >;
typedef $$AppMetaTableTableCreateCompanionBuilder =
    AppMetaTableCompanion Function({
      required String key,
      Value<String?> value,
      Value<int> rowid,
    });
typedef $$AppMetaTableTableUpdateCompanionBuilder =
    AppMetaTableCompanion Function({
      Value<String> key,
      Value<String?> value,
      Value<int> rowid,
    });

class $$AppMetaTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppMetaTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppMetaTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppMetaTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppMetaTableTable,
          AppMetaTableData,
          $$AppMetaTableTableFilterComposer,
          $$AppMetaTableTableOrderingComposer,
          $$AppMetaTableTableAnnotationComposer,
          $$AppMetaTableTableCreateCompanionBuilder,
          $$AppMetaTableTableUpdateCompanionBuilder,
          (
            AppMetaTableData,
            BaseReferences<_$AppDatabase, $AppMetaTableTable, AppMetaTableData>,
          ),
          AppMetaTableData,
          PrefetchHooks Function()
        > {
  $$AppMetaTableTableTableManager(_$AppDatabase db, $AppMetaTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppMetaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppMetaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppMetaTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppMetaTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppMetaTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppMetaTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppMetaTableTable,
      AppMetaTableData,
      $$AppMetaTableTableFilterComposer,
      $$AppMetaTableTableOrderingComposer,
      $$AppMetaTableTableAnnotationComposer,
      $$AppMetaTableTableCreateCompanionBuilder,
      $$AppMetaTableTableUpdateCompanionBuilder,
      (
        AppMetaTableData,
        BaseReferences<_$AppDatabase, $AppMetaTableTable, AppMetaTableData>,
      ),
      AppMetaTableData,
      PrefetchHooks Function()
    >;
typedef $$SettingsValuesTableTableCreateCompanionBuilder =
    SettingsValuesTableCompanion Function({
      required String key,
      required String type,
      required String value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsValuesTableTableUpdateCompanionBuilder =
    SettingsValuesTableCompanion Function({
      Value<String> key,
      Value<String> type,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SettingsValuesTableTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsValuesTableTable> {
  $$SettingsValuesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsValuesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsValuesTableTable> {
  $$SettingsValuesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsValuesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsValuesTableTable> {
  $$SettingsValuesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsValuesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsValuesTableTable,
          SettingsValuesTableData,
          $$SettingsValuesTableTableFilterComposer,
          $$SettingsValuesTableTableOrderingComposer,
          $$SettingsValuesTableTableAnnotationComposer,
          $$SettingsValuesTableTableCreateCompanionBuilder,
          $$SettingsValuesTableTableUpdateCompanionBuilder,
          (
            SettingsValuesTableData,
            BaseReferences<
              _$AppDatabase,
              $SettingsValuesTableTable,
              SettingsValuesTableData
            >,
          ),
          SettingsValuesTableData,
          PrefetchHooks Function()
        > {
  $$SettingsValuesTableTableTableManager(
    _$AppDatabase db,
    $SettingsValuesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsValuesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsValuesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SettingsValuesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsValuesTableCompanion(
                key: key,
                type: type,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String type,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsValuesTableCompanion.insert(
                key: key,
                type: type,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsValuesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsValuesTableTable,
      SettingsValuesTableData,
      $$SettingsValuesTableTableFilterComposer,
      $$SettingsValuesTableTableOrderingComposer,
      $$SettingsValuesTableTableAnnotationComposer,
      $$SettingsValuesTableTableCreateCompanionBuilder,
      $$SettingsValuesTableTableUpdateCompanionBuilder,
      (
        SettingsValuesTableData,
        BaseReferences<
          _$AppDatabase,
          $SettingsValuesTableTable,
          SettingsValuesTableData
        >,
      ),
      SettingsValuesTableData,
      PrefetchHooks Function()
    >;
typedef $$VisibleRangePresetRowsTableCreateCompanionBuilder =
    VisibleRangePresetRowsCompanion Function({
      required String id,
      required String name,
      Value<String> description,
      Value<String> filters,
      Value<bool> builtin,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$VisibleRangePresetRowsTableUpdateCompanionBuilder =
    VisibleRangePresetRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> description,
      Value<String> filters,
      Value<bool> builtin,
      Value<int> position,
      Value<int> rowid,
    });

class $$VisibleRangePresetRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VisibleRangePresetRowsTable> {
  $$VisibleRangePresetRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get builtin => $composableBuilder(
    column: $table.builtin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisibleRangePresetRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisibleRangePresetRowsTable> {
  $$VisibleRangePresetRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get builtin => $composableBuilder(
    column: $table.builtin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisibleRangePresetRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisibleRangePresetRowsTable> {
  $$VisibleRangePresetRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filters =>
      $composableBuilder(column: $table.filters, builder: (column) => column);

  GeneratedColumn<bool> get builtin =>
      $composableBuilder(column: $table.builtin, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$VisibleRangePresetRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisibleRangePresetRowsTable,
          VisibleRangePresetRow,
          $$VisibleRangePresetRowsTableFilterComposer,
          $$VisibleRangePresetRowsTableOrderingComposer,
          $$VisibleRangePresetRowsTableAnnotationComposer,
          $$VisibleRangePresetRowsTableCreateCompanionBuilder,
          $$VisibleRangePresetRowsTableUpdateCompanionBuilder,
          (
            VisibleRangePresetRow,
            BaseReferences<
              _$AppDatabase,
              $VisibleRangePresetRowsTable,
              VisibleRangePresetRow
            >,
          ),
          VisibleRangePresetRow,
          PrefetchHooks Function()
        > {
  $$VisibleRangePresetRowsTableTableManager(
    _$AppDatabase db,
    $VisibleRangePresetRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisibleRangePresetRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VisibleRangePresetRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VisibleRangePresetRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<bool> builtin = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangePresetRowsCompanion(
                id: id,
                name: name,
                description: description,
                filters: filters,
                builtin: builtin,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> description = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<bool> builtin = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangePresetRowsCompanion.insert(
                id: id,
                name: name,
                description: description,
                filters: filters,
                builtin: builtin,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisibleRangePresetRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisibleRangePresetRowsTable,
      VisibleRangePresetRow,
      $$VisibleRangePresetRowsTableFilterComposer,
      $$VisibleRangePresetRowsTableOrderingComposer,
      $$VisibleRangePresetRowsTableAnnotationComposer,
      $$VisibleRangePresetRowsTableCreateCompanionBuilder,
      $$VisibleRangePresetRowsTableUpdateCompanionBuilder,
      (
        VisibleRangePresetRow,
        BaseReferences<
          _$AppDatabase,
          $VisibleRangePresetRowsTable,
          VisibleRangePresetRow
        >,
      ),
      VisibleRangePresetRow,
      PrefetchHooks Function()
    >;
typedef $$VisibleRangeRowsTableCreateCompanionBuilder =
    VisibleRangeRowsCompanion Function({
      required String id,
      required String scope,
      required String ownerId,
      Value<String> baseName,
      Value<String> basePresetId,
      Value<String> baseFilters,
      Value<String> orderMode,
      Value<bool> locked,
      Value<String?> permissions,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$VisibleRangeRowsTableUpdateCompanionBuilder =
    VisibleRangeRowsCompanion Function({
      Value<String> id,
      Value<String> scope,
      Value<String> ownerId,
      Value<String> baseName,
      Value<String> basePresetId,
      Value<String> baseFilters,
      Value<String> orderMode,
      Value<bool> locked,
      Value<String?> permissions,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$VisibleRangeRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VisibleRangeRowsTable> {
  $$VisibleRangeRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseName => $composableBuilder(
    column: $table.baseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get basePresetId => $composableBuilder(
    column: $table.basePresetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseFilters => $composableBuilder(
    column: $table.baseFilters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderMode => $composableBuilder(
    column: $table.orderMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get locked => $composableBuilder(
    column: $table.locked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisibleRangeRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisibleRangeRowsTable> {
  $$VisibleRangeRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseName => $composableBuilder(
    column: $table.baseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get basePresetId => $composableBuilder(
    column: $table.basePresetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseFilters => $composableBuilder(
    column: $table.baseFilters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderMode => $composableBuilder(
    column: $table.orderMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get locked => $composableBuilder(
    column: $table.locked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisibleRangeRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisibleRangeRowsTable> {
  $$VisibleRangeRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get baseName =>
      $composableBuilder(column: $table.baseName, builder: (column) => column);

  GeneratedColumn<String> get basePresetId => $composableBuilder(
    column: $table.basePresetId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseFilters => $composableBuilder(
    column: $table.baseFilters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderMode =>
      $composableBuilder(column: $table.orderMode, builder: (column) => column);

  GeneratedColumn<bool> get locked =>
      $composableBuilder(column: $table.locked, builder: (column) => column);

  GeneratedColumn<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VisibleRangeRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisibleRangeRowsTable,
          VisibleRangeRow,
          $$VisibleRangeRowsTableFilterComposer,
          $$VisibleRangeRowsTableOrderingComposer,
          $$VisibleRangeRowsTableAnnotationComposer,
          $$VisibleRangeRowsTableCreateCompanionBuilder,
          $$VisibleRangeRowsTableUpdateCompanionBuilder,
          (
            VisibleRangeRow,
            BaseReferences<
              _$AppDatabase,
              $VisibleRangeRowsTable,
              VisibleRangeRow
            >,
          ),
          VisibleRangeRow,
          PrefetchHooks Function()
        > {
  $$VisibleRangeRowsTableTableManager(
    _$AppDatabase db,
    $VisibleRangeRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisibleRangeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisibleRangeRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisibleRangeRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> baseName = const Value.absent(),
                Value<String> basePresetId = const Value.absent(),
                Value<String> baseFilters = const Value.absent(),
                Value<String> orderMode = const Value.absent(),
                Value<bool> locked = const Value.absent(),
                Value<String?> permissions = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeRowsCompanion(
                id: id,
                scope: scope,
                ownerId: ownerId,
                baseName: baseName,
                basePresetId: basePresetId,
                baseFilters: baseFilters,
                orderMode: orderMode,
                locked: locked,
                permissions: permissions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String scope,
                required String ownerId,
                Value<String> baseName = const Value.absent(),
                Value<String> basePresetId = const Value.absent(),
                Value<String> baseFilters = const Value.absent(),
                Value<String> orderMode = const Value.absent(),
                Value<bool> locked = const Value.absent(),
                Value<String?> permissions = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeRowsCompanion.insert(
                id: id,
                scope: scope,
                ownerId: ownerId,
                baseName: baseName,
                basePresetId: basePresetId,
                baseFilters: baseFilters,
                orderMode: orderMode,
                locked: locked,
                permissions: permissions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisibleRangeRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisibleRangeRowsTable,
      VisibleRangeRow,
      $$VisibleRangeRowsTableFilterComposer,
      $$VisibleRangeRowsTableOrderingComposer,
      $$VisibleRangeRowsTableAnnotationComposer,
      $$VisibleRangeRowsTableCreateCompanionBuilder,
      $$VisibleRangeRowsTableUpdateCompanionBuilder,
      (
        VisibleRangeRow,
        BaseReferences<_$AppDatabase, $VisibleRangeRowsTable, VisibleRangeRow>,
      ),
      VisibleRangeRow,
      PrefetchHooks Function()
    >;
typedef $$VisibleRangeRuleRowsTableCreateCompanionBuilder =
    VisibleRangeRuleRowsCompanion Function({
      required String id,
      required String rangeId,
      required String kind,
      Value<int> position,
      Value<String> label,
      Value<String> description,
      Value<String> filters,
      Value<bool> active,
      Value<int> rowid,
    });
typedef $$VisibleRangeRuleRowsTableUpdateCompanionBuilder =
    VisibleRangeRuleRowsCompanion Function({
      Value<String> id,
      Value<String> rangeId,
      Value<String> kind,
      Value<int> position,
      Value<String> label,
      Value<String> description,
      Value<String> filters,
      Value<bool> active,
      Value<int> rowid,
    });

class $$VisibleRangeRuleRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VisibleRangeRuleRowsTable> {
  $$VisibleRangeRuleRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rangeId => $composableBuilder(
    column: $table.rangeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisibleRangeRuleRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisibleRangeRuleRowsTable> {
  $$VisibleRangeRuleRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rangeId => $composableBuilder(
    column: $table.rangeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filters => $composableBuilder(
    column: $table.filters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisibleRangeRuleRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisibleRangeRuleRowsTable> {
  $$VisibleRangeRuleRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rangeId =>
      $composableBuilder(column: $table.rangeId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filters =>
      $composableBuilder(column: $table.filters, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$VisibleRangeRuleRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisibleRangeRuleRowsTable,
          VisibleRangeRuleRow,
          $$VisibleRangeRuleRowsTableFilterComposer,
          $$VisibleRangeRuleRowsTableOrderingComposer,
          $$VisibleRangeRuleRowsTableAnnotationComposer,
          $$VisibleRangeRuleRowsTableCreateCompanionBuilder,
          $$VisibleRangeRuleRowsTableUpdateCompanionBuilder,
          (
            VisibleRangeRuleRow,
            BaseReferences<
              _$AppDatabase,
              $VisibleRangeRuleRowsTable,
              VisibleRangeRuleRow
            >,
          ),
          VisibleRangeRuleRow,
          PrefetchHooks Function()
        > {
  $$VisibleRangeRuleRowsTableTableManager(
    _$AppDatabase db,
    $VisibleRangeRuleRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisibleRangeRuleRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisibleRangeRuleRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VisibleRangeRuleRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> rangeId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeRuleRowsCompanion(
                id: id,
                rangeId: rangeId,
                kind: kind,
                position: position,
                label: label,
                description: description,
                filters: filters,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String rangeId,
                required String kind,
                Value<int> position = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> filters = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeRuleRowsCompanion.insert(
                id: id,
                rangeId: rangeId,
                kind: kind,
                position: position,
                label: label,
                description: description,
                filters: filters,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisibleRangeRuleRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisibleRangeRuleRowsTable,
      VisibleRangeRuleRow,
      $$VisibleRangeRuleRowsTableFilterComposer,
      $$VisibleRangeRuleRowsTableOrderingComposer,
      $$VisibleRangeRuleRowsTableAnnotationComposer,
      $$VisibleRangeRuleRowsTableCreateCompanionBuilder,
      $$VisibleRangeRuleRowsTableUpdateCompanionBuilder,
      (
        VisibleRangeRuleRow,
        BaseReferences<
          _$AppDatabase,
          $VisibleRangeRuleRowsTable,
          VisibleRangeRuleRow
        >,
      ),
      VisibleRangeRuleRow,
      PrefetchHooks Function()
    >;
typedef $$VisibleRangeSessionRowsTableCreateCompanionBuilder =
    VisibleRangeSessionRowsCompanion Function({
      required String id,
      required String rangeId,
      required String ruleId,
      required String kind,
      required String mode,
      Value<String> initialFilters,
      Value<String> finalFilters,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$VisibleRangeSessionRowsTableUpdateCompanionBuilder =
    VisibleRangeSessionRowsCompanion Function({
      Value<String> id,
      Value<String> rangeId,
      Value<String> ruleId,
      Value<String> kind,
      Value<String> mode,
      Value<String> initialFilters,
      Value<String> finalFilters,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$VisibleRangeSessionRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VisibleRangeSessionRowsTable> {
  $$VisibleRangeSessionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rangeId => $composableBuilder(
    column: $table.rangeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get initialFilters => $composableBuilder(
    column: $table.initialFilters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalFilters => $composableBuilder(
    column: $table.finalFilters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisibleRangeSessionRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisibleRangeSessionRowsTable> {
  $$VisibleRangeSessionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rangeId => $composableBuilder(
    column: $table.rangeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initialFilters => $composableBuilder(
    column: $table.initialFilters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalFilters => $composableBuilder(
    column: $table.finalFilters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisibleRangeSessionRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisibleRangeSessionRowsTable> {
  $$VisibleRangeSessionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rangeId =>
      $composableBuilder(column: $table.rangeId, builder: (column) => column);

  GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get initialFilters => $composableBuilder(
    column: $table.initialFilters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finalFilters => $composableBuilder(
    column: $table.finalFilters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$VisibleRangeSessionRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisibleRangeSessionRowsTable,
          VisibleRangeSessionRow,
          $$VisibleRangeSessionRowsTableFilterComposer,
          $$VisibleRangeSessionRowsTableOrderingComposer,
          $$VisibleRangeSessionRowsTableAnnotationComposer,
          $$VisibleRangeSessionRowsTableCreateCompanionBuilder,
          $$VisibleRangeSessionRowsTableUpdateCompanionBuilder,
          (
            VisibleRangeSessionRow,
            BaseReferences<
              _$AppDatabase,
              $VisibleRangeSessionRowsTable,
              VisibleRangeSessionRow
            >,
          ),
          VisibleRangeSessionRow,
          PrefetchHooks Function()
        > {
  $$VisibleRangeSessionRowsTableTableManager(
    _$AppDatabase db,
    $VisibleRangeSessionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisibleRangeSessionRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VisibleRangeSessionRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VisibleRangeSessionRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> rangeId = const Value.absent(),
                Value<String> ruleId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> initialFilters = const Value.absent(),
                Value<String> finalFilters = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeSessionRowsCompanion(
                id: id,
                rangeId: rangeId,
                ruleId: ruleId,
                kind: kind,
                mode: mode,
                initialFilters: initialFilters,
                finalFilters: finalFilters,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String rangeId,
                required String ruleId,
                required String kind,
                required String mode,
                Value<String> initialFilters = const Value.absent(),
                Value<String> finalFilters = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeSessionRowsCompanion.insert(
                id: id,
                rangeId: rangeId,
                ruleId: ruleId,
                kind: kind,
                mode: mode,
                initialFilters: initialFilters,
                finalFilters: finalFilters,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisibleRangeSessionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisibleRangeSessionRowsTable,
      VisibleRangeSessionRow,
      $$VisibleRangeSessionRowsTableFilterComposer,
      $$VisibleRangeSessionRowsTableOrderingComposer,
      $$VisibleRangeSessionRowsTableAnnotationComposer,
      $$VisibleRangeSessionRowsTableCreateCompanionBuilder,
      $$VisibleRangeSessionRowsTableUpdateCompanionBuilder,
      (
        VisibleRangeSessionRow,
        BaseReferences<
          _$AppDatabase,
          $VisibleRangeSessionRowsTable,
          VisibleRangeSessionRow
        >,
      ),
      VisibleRangeSessionRow,
      PrefetchHooks Function()
    >;
typedef $$VisibleRangeKeyValuesTableCreateCompanionBuilder =
    VisibleRangeKeyValuesCompanion Function({
      required String key,
      Value<String?> value,
      Value<int> rowid,
    });
typedef $$VisibleRangeKeyValuesTableUpdateCompanionBuilder =
    VisibleRangeKeyValuesCompanion Function({
      Value<String> key,
      Value<String?> value,
      Value<int> rowid,
    });

class $$VisibleRangeKeyValuesTableFilterComposer
    extends Composer<_$AppDatabase, $VisibleRangeKeyValuesTable> {
  $$VisibleRangeKeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisibleRangeKeyValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $VisibleRangeKeyValuesTable> {
  $$VisibleRangeKeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisibleRangeKeyValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisibleRangeKeyValuesTable> {
  $$VisibleRangeKeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$VisibleRangeKeyValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisibleRangeKeyValuesTable,
          VisibleRangeKeyValue,
          $$VisibleRangeKeyValuesTableFilterComposer,
          $$VisibleRangeKeyValuesTableOrderingComposer,
          $$VisibleRangeKeyValuesTableAnnotationComposer,
          $$VisibleRangeKeyValuesTableCreateCompanionBuilder,
          $$VisibleRangeKeyValuesTableUpdateCompanionBuilder,
          (
            VisibleRangeKeyValue,
            BaseReferences<
              _$AppDatabase,
              $VisibleRangeKeyValuesTable,
              VisibleRangeKeyValue
            >,
          ),
          VisibleRangeKeyValue,
          PrefetchHooks Function()
        > {
  $$VisibleRangeKeyValuesTableTableManager(
    _$AppDatabase db,
    $VisibleRangeKeyValuesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisibleRangeKeyValuesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VisibleRangeKeyValuesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VisibleRangeKeyValuesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeKeyValuesCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisibleRangeKeyValuesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisibleRangeKeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisibleRangeKeyValuesTable,
      VisibleRangeKeyValue,
      $$VisibleRangeKeyValuesTableFilterComposer,
      $$VisibleRangeKeyValuesTableOrderingComposer,
      $$VisibleRangeKeyValuesTableAnnotationComposer,
      $$VisibleRangeKeyValuesTableCreateCompanionBuilder,
      $$VisibleRangeKeyValuesTableUpdateCompanionBuilder,
      (
        VisibleRangeKeyValue,
        BaseReferences<
          _$AppDatabase,
          $VisibleRangeKeyValuesTable,
          VisibleRangeKeyValue
        >,
      ),
      VisibleRangeKeyValue,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EntriesTableTableTableManager get entriesTable =>
      $$EntriesTableTableTableManager(_db, _db.entriesTable);
  $$DateTakenTableTableTableManager get dateTakenTable =>
      $$DateTakenTableTableTableManager(_db, _db.dateTakenTable);
  $$MetadataTableTableTableManager get metadataTable =>
      $$MetadataTableTableTableManager(_db, _db.metadataTable);
  $$AddressesTableTableTableManager get addressesTable =>
      $$AddressesTableTableTableManager(_db, _db.addressesTable);
  $$FavouritesTableTableTableManager get favouritesTable =>
      $$FavouritesTableTableTableManager(_db, _db.favouritesTable);
  $$CoversTableTableTableManager get coversTable =>
      $$CoversTableTableTableManager(_db, _db.coversTable);
  $$DynamicAlbumsTableTableTableManager get dynamicAlbumsTable =>
      $$DynamicAlbumsTableTableTableManager(_db, _db.dynamicAlbumsTable);
  $$VaultsTableTableTableManager get vaultsTable =>
      $$VaultsTableTableTableManager(_db, _db.vaultsTable);
  $$TrashTableTableTableManager get trashTable =>
      $$TrashTableTableTableManager(_db, _db.trashTable);
  $$VideoPlaybackTableTableTableManager get videoPlaybackTable =>
      $$VideoPlaybackTableTableTableManager(_db, _db.videoPlaybackTable);
  $$DebugTableTableTableManager get debugTable =>
      $$DebugTableTableTableManager(_db, _db.debugTable);
  $$AppMetaTableTableTableManager get appMetaTable =>
      $$AppMetaTableTableTableManager(_db, _db.appMetaTable);
  $$SettingsValuesTableTableTableManager get settingsValuesTable =>
      $$SettingsValuesTableTableTableManager(_db, _db.settingsValuesTable);
  $$VisibleRangePresetRowsTableTableManager get visibleRangePresetRows =>
      $$VisibleRangePresetRowsTableTableManager(
        _db,
        _db.visibleRangePresetRows,
      );
  $$VisibleRangeRowsTableTableManager get visibleRangeRows =>
      $$VisibleRangeRowsTableTableManager(_db, _db.visibleRangeRows);
  $$VisibleRangeRuleRowsTableTableManager get visibleRangeRuleRows =>
      $$VisibleRangeRuleRowsTableTableManager(_db, _db.visibleRangeRuleRows);
  $$VisibleRangeSessionRowsTableTableManager get visibleRangeSessionRows =>
      $$VisibleRangeSessionRowsTableTableManager(
        _db,
        _db.visibleRangeSessionRows,
      );
  $$VisibleRangeKeyValuesTableTableManager get visibleRangeKeyValues =>
      $$VisibleRangeKeyValuesTableTableManager(_db, _db.visibleRangeKeyValues);
}
