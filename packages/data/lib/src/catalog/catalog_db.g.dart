// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_db.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
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
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    kind,
    id,
    name,
    parentId,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
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
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, kind, id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String panelId;

  /// live | movie | series
  final String kind;
  final String id;
  final String name;
  final String? parentId;

  /// Panel order.
  final int sort;
  const CategoryRow({
    required this.panelId,
    required this.kind,
    required this.id,
    required this.name,
    this.parentId,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['kind'] = Variable<String>(kind);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['sort'] = Variable<int>(sort);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      panelId: Value(panelId),
      kind: Value(kind),
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      sort: Value(sort),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'sort': serializer.toJson<int>(sort),
    };
  }

  CategoryRow copyWith({
    String? panelId,
    String? kind,
    String? id,
    String? name,
    Value<String?> parentId = const Value.absent(),
    int? sort,
  }) => CategoryRow(
    panelId: panelId ?? this.panelId,
    kind: kind ?? this.kind,
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId.present ? parentId.value : this.parentId,
    sort: sort ?? this.sort,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('panelId: $panelId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(panelId, kind, id, name, parentId, sort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.panelId == this.panelId &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.sort == this.sort);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> panelId;
  final Value<String> kind;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<int> sort;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.panelId = const Value.absent(),
    this.kind = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String panelId,
    required String kind,
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    required int sort,
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       kind = Value(kind),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<CategoryRow> custom({
    Expression<String>? panelId,
    Expression<String>? kind,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? panelId,
    Value<String>? kind,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? parentId,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      panelId: panelId ?? this.panelId,
      kind: kind ?? this.kind,
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('panelId: $panelId, ')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels
    with TableInfo<$ChannelsTable, ChannelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logoUrlMeta = const VerificationMeta(
    'logoUrl',
  );
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
    'logo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _epgIdMeta = const VerificationMeta('epgId');
  @override
  late final GeneratedColumn<String> epgId = GeneratedColumn<String>(
    'epg_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _catchupDaysMeta = const VerificationMeta(
    'catchupDays',
  );
  @override
  late final GeneratedColumn<int> catchupDays = GeneratedColumn<int>(
    'catchup_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedSecMeta = const VerificationMeta(
    'addedSec',
  );
  @override
  late final GeneratedColumn<int> addedSec = GeneratedColumn<int>(
    'added_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    id,
    name,
    number,
    logoUrl,
    categoryId,
    epgId,
    catchupDays,
    addedSec,
    command,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChannelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
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
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    }
    if (data.containsKey('logo_url')) {
      context.handle(
        _logoUrlMeta,
        logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('epg_id')) {
      context.handle(
        _epgIdMeta,
        epgId.isAcceptableOrUnknown(data['epg_id']!, _epgIdMeta),
      );
    }
    if (data.containsKey('catchup_days')) {
      context.handle(
        _catchupDaysMeta,
        catchupDays.isAcceptableOrUnknown(
          data['catchup_days']!,
          _catchupDaysMeta,
        ),
      );
    }
    if (data.containsKey('added_sec')) {
      context.handle(
        _addedSecMeta,
        addedSec.isAcceptableOrUnknown(data['added_sec']!, _addedSecMeta),
      );
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, id};
  @override
  ChannelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      ),
      logoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_url'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      epgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epg_id'],
      ),
      catchupDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}catchup_days'],
      )!,
      addedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_sec'],
      ),
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      ),
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class ChannelRow extends DataClass implements Insertable<ChannelRow> {
  final String panelId;
  final String id;
  final String name;
  final int? number;
  final String? logoUrl;
  final String? categoryId;
  final String? epgId;
  final int catchupDays;
  final int? addedSec;
  final String? command;

  /// Order inside its category as the panel sent it.
  final int sort;
  const ChannelRow({
    required this.panelId,
    required this.id,
    required this.name,
    this.number,
    this.logoUrl,
    this.categoryId,
    this.epgId,
    required this.catchupDays,
    this.addedSec,
    this.command,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || number != null) {
      map['number'] = Variable<int>(number);
    }
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || epgId != null) {
      map['epg_id'] = Variable<String>(epgId);
    }
    map['catchup_days'] = Variable<int>(catchupDays);
    if (!nullToAbsent || addedSec != null) {
      map['added_sec'] = Variable<int>(addedSec);
    }
    if (!nullToAbsent || command != null) {
      map['command'] = Variable<String>(command);
    }
    map['sort'] = Variable<int>(sort);
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      panelId: Value(panelId),
      id: Value(id),
      name: Value(name),
      number: number == null && nullToAbsent
          ? const Value.absent()
          : Value(number),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      epgId: epgId == null && nullToAbsent
          ? const Value.absent()
          : Value(epgId),
      catchupDays: Value(catchupDays),
      addedSec: addedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(addedSec),
      command: command == null && nullToAbsent
          ? const Value.absent()
          : Value(command),
      sort: Value(sort),
    );
  }

  factory ChannelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      number: serializer.fromJson<int?>(json['number']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      epgId: serializer.fromJson<String?>(json['epgId']),
      catchupDays: serializer.fromJson<int>(json['catchupDays']),
      addedSec: serializer.fromJson<int?>(json['addedSec']),
      command: serializer.fromJson<String?>(json['command']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'number': serializer.toJson<int?>(number),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'categoryId': serializer.toJson<String?>(categoryId),
      'epgId': serializer.toJson<String?>(epgId),
      'catchupDays': serializer.toJson<int>(catchupDays),
      'addedSec': serializer.toJson<int?>(addedSec),
      'command': serializer.toJson<String?>(command),
      'sort': serializer.toJson<int>(sort),
    };
  }

  ChannelRow copyWith({
    String? panelId,
    String? id,
    String? name,
    Value<int?> number = const Value.absent(),
    Value<String?> logoUrl = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<String?> epgId = const Value.absent(),
    int? catchupDays,
    Value<int?> addedSec = const Value.absent(),
    Value<String?> command = const Value.absent(),
    int? sort,
  }) => ChannelRow(
    panelId: panelId ?? this.panelId,
    id: id ?? this.id,
    name: name ?? this.name,
    number: number.present ? number.value : this.number,
    logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    epgId: epgId.present ? epgId.value : this.epgId,
    catchupDays: catchupDays ?? this.catchupDays,
    addedSec: addedSec.present ? addedSec.value : this.addedSec,
    command: command.present ? command.value : this.command,
    sort: sort ?? this.sort,
  );
  ChannelRow copyWithCompanion(ChannelsCompanion data) {
    return ChannelRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      number: data.number.present ? data.number.value : this.number,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      epgId: data.epgId.present ? data.epgId.value : this.epgId,
      catchupDays: data.catchupDays.present
          ? data.catchupDays.value
          : this.catchupDays,
      addedSec: data.addedSec.present ? data.addedSec.value : this.addedSec,
      command: data.command.present ? data.command.value : this.command,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelRow(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('categoryId: $categoryId, ')
          ..write('epgId: $epgId, ')
          ..write('catchupDays: $catchupDays, ')
          ..write('addedSec: $addedSec, ')
          ..write('command: $command, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    panelId,
    id,
    name,
    number,
    logoUrl,
    categoryId,
    epgId,
    catchupDays,
    addedSec,
    command,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelRow &&
          other.panelId == this.panelId &&
          other.id == this.id &&
          other.name == this.name &&
          other.number == this.number &&
          other.logoUrl == this.logoUrl &&
          other.categoryId == this.categoryId &&
          other.epgId == this.epgId &&
          other.catchupDays == this.catchupDays &&
          other.addedSec == this.addedSec &&
          other.command == this.command &&
          other.sort == this.sort);
}

class ChannelsCompanion extends UpdateCompanion<ChannelRow> {
  final Value<String> panelId;
  final Value<String> id;
  final Value<String> name;
  final Value<int?> number;
  final Value<String?> logoUrl;
  final Value<String?> categoryId;
  final Value<String?> epgId;
  final Value<int> catchupDays;
  final Value<int?> addedSec;
  final Value<String?> command;
  final Value<int> sort;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.panelId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.number = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.epgId = const Value.absent(),
    this.catchupDays = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.command = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String panelId,
    required String id,
    required String name,
    this.number = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.epgId = const Value.absent(),
    this.catchupDays = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.command = const Value.absent(),
    required int sort,
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<ChannelRow> custom({
    Expression<String>? panelId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? number,
    Expression<String>? logoUrl,
    Expression<String>? categoryId,
    Expression<String>? epgId,
    Expression<int>? catchupDays,
    Expression<int>? addedSec,
    Expression<String>? command,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (number != null) 'number': number,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (categoryId != null) 'category_id': categoryId,
      if (epgId != null) 'epg_id': epgId,
      if (catchupDays != null) 'catchup_days': catchupDays,
      if (addedSec != null) 'added_sec': addedSec,
      if (command != null) 'command': command,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<String>? panelId,
    Value<String>? id,
    Value<String>? name,
    Value<int?>? number,
    Value<String?>? logoUrl,
    Value<String?>? categoryId,
    Value<String?>? epgId,
    Value<int>? catchupDays,
    Value<int?>? addedSec,
    Value<String?>? command,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      panelId: panelId ?? this.panelId,
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      logoUrl: logoUrl ?? this.logoUrl,
      categoryId: categoryId ?? this.categoryId,
      epgId: epgId ?? this.epgId,
      catchupDays: catchupDays ?? this.catchupDays,
      addedSec: addedSec ?? this.addedSec,
      command: command ?? this.command,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (epgId.present) {
      map['epg_id'] = Variable<String>(epgId.value);
    }
    if (catchupDays.present) {
      map['catchup_days'] = Variable<int>(catchupDays.value);
    }
    if (addedSec.present) {
      map['added_sec'] = Variable<int>(addedSec.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('categoryId: $categoryId, ')
          ..write('epgId: $epgId, ')
          ..write('catchupDays: $catchupDays, ')
          ..write('addedSec: $addedSec, ')
          ..write('command: $command, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MoviesTable extends Movies with TableInfo<$MoviesTable, MovieRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoviesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedSecMeta = const VerificationMeta(
    'addedSec',
  );
  @override
  late final GeneratedColumn<int> addedSec = GeneratedColumn<int>(
    'added_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
    'tmdb_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extensionMeta = const VerificationMeta(
    'extension',
  );
  @override
  late final GeneratedColumn<String> extension = GeneratedColumn<String>(
    'extension',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    id,
    name,
    posterUrl,
    rating,
    year,
    categoryId,
    addedSec,
    tmdbId,
    extension,
    command,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movies';
  @override
  VerificationContext validateIntegrity(
    Insertable<MovieRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
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
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('added_sec')) {
      context.handle(
        _addedSecMeta,
        addedSec.isAcceptableOrUnknown(data['added_sec']!, _addedSecMeta),
      );
    }
    if (data.containsKey('tmdb_id')) {
      context.handle(
        _tmdbIdMeta,
        tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta),
      );
    }
    if (data.containsKey('extension')) {
      context.handle(
        _extensionMeta,
        extension.isAcceptableOrUnknown(data['extension']!, _extensionMeta),
      );
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, id};
  @override
  MovieRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MovieRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      addedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_sec'],
      ),
      tmdbId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tmdb_id'],
      ),
      extension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension'],
      ),
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      ),
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $MoviesTable createAlias(String alias) {
    return $MoviesTable(attachedDatabase, alias);
  }
}

class MovieRow extends DataClass implements Insertable<MovieRow> {
  final String panelId;
  final String id;
  final String name;
  final String? posterUrl;
  final double? rating;
  final int? year;
  final String? categoryId;
  final int? addedSec;
  final int? tmdbId;
  final String? extension;
  final String? command;
  final int sort;
  const MovieRow({
    required this.panelId,
    required this.id,
    required this.name,
    this.posterUrl,
    this.rating,
    this.year,
    this.categoryId,
    this.addedSec,
    this.tmdbId,
    this.extension,
    this.command,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || addedSec != null) {
      map['added_sec'] = Variable<int>(addedSec);
    }
    if (!nullToAbsent || tmdbId != null) {
      map['tmdb_id'] = Variable<int>(tmdbId);
    }
    if (!nullToAbsent || extension != null) {
      map['extension'] = Variable<String>(extension);
    }
    if (!nullToAbsent || command != null) {
      map['command'] = Variable<String>(command);
    }
    map['sort'] = Variable<int>(sort);
    return map;
  }

  MoviesCompanion toCompanion(bool nullToAbsent) {
    return MoviesCompanion(
      panelId: Value(panelId),
      id: Value(id),
      name: Value(name),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      addedSec: addedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(addedSec),
      tmdbId: tmdbId == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbId),
      extension: extension == null && nullToAbsent
          ? const Value.absent()
          : Value(extension),
      command: command == null && nullToAbsent
          ? const Value.absent()
          : Value(command),
      sort: Value(sort),
    );
  }

  factory MovieRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MovieRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      rating: serializer.fromJson<double?>(json['rating']),
      year: serializer.fromJson<int?>(json['year']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      addedSec: serializer.fromJson<int?>(json['addedSec']),
      tmdbId: serializer.fromJson<int?>(json['tmdbId']),
      extension: serializer.fromJson<String?>(json['extension']),
      command: serializer.fromJson<String?>(json['command']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'rating': serializer.toJson<double?>(rating),
      'year': serializer.toJson<int?>(year),
      'categoryId': serializer.toJson<String?>(categoryId),
      'addedSec': serializer.toJson<int?>(addedSec),
      'tmdbId': serializer.toJson<int?>(tmdbId),
      'extension': serializer.toJson<String?>(extension),
      'command': serializer.toJson<String?>(command),
      'sort': serializer.toJson<int>(sort),
    };
  }

  MovieRow copyWith({
    String? panelId,
    String? id,
    String? name,
    Value<String?> posterUrl = const Value.absent(),
    Value<double?> rating = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<int?> addedSec = const Value.absent(),
    Value<int?> tmdbId = const Value.absent(),
    Value<String?> extension = const Value.absent(),
    Value<String?> command = const Value.absent(),
    int? sort,
  }) => MovieRow(
    panelId: panelId ?? this.panelId,
    id: id ?? this.id,
    name: name ?? this.name,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    rating: rating.present ? rating.value : this.rating,
    year: year.present ? year.value : this.year,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    addedSec: addedSec.present ? addedSec.value : this.addedSec,
    tmdbId: tmdbId.present ? tmdbId.value : this.tmdbId,
    extension: extension.present ? extension.value : this.extension,
    command: command.present ? command.value : this.command,
    sort: sort ?? this.sort,
  );
  MovieRow copyWithCompanion(MoviesCompanion data) {
    return MovieRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      rating: data.rating.present ? data.rating.value : this.rating,
      year: data.year.present ? data.year.value : this.year,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      addedSec: data.addedSec.present ? data.addedSec.value : this.addedSec,
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      extension: data.extension.present ? data.extension.value : this.extension,
      command: data.command.present ? data.command.value : this.command,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MovieRow(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedSec: $addedSec, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('extension: $extension, ')
          ..write('command: $command, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    panelId,
    id,
    name,
    posterUrl,
    rating,
    year,
    categoryId,
    addedSec,
    tmdbId,
    extension,
    command,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MovieRow &&
          other.panelId == this.panelId &&
          other.id == this.id &&
          other.name == this.name &&
          other.posterUrl == this.posterUrl &&
          other.rating == this.rating &&
          other.year == this.year &&
          other.categoryId == this.categoryId &&
          other.addedSec == this.addedSec &&
          other.tmdbId == this.tmdbId &&
          other.extension == this.extension &&
          other.command == this.command &&
          other.sort == this.sort);
}

class MoviesCompanion extends UpdateCompanion<MovieRow> {
  final Value<String> panelId;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> posterUrl;
  final Value<double?> rating;
  final Value<int?> year;
  final Value<String?> categoryId;
  final Value<int?> addedSec;
  final Value<int?> tmdbId;
  final Value<String?> extension;
  final Value<String?> command;
  final Value<int> sort;
  final Value<int> rowid;
  const MoviesCompanion({
    this.panelId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.extension = const Value.absent(),
    this.command = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MoviesCompanion.insert({
    required String panelId,
    required String id,
    required String name,
    this.posterUrl = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.extension = const Value.absent(),
    this.command = const Value.absent(),
    required int sort,
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<MovieRow> custom({
    Expression<String>? panelId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? posterUrl,
    Expression<double>? rating,
    Expression<int>? year,
    Expression<String>? categoryId,
    Expression<int>? addedSec,
    Expression<int>? tmdbId,
    Expression<String>? extension,
    Expression<String>? command,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (rating != null) 'rating': rating,
      if (year != null) 'year': year,
      if (categoryId != null) 'category_id': categoryId,
      if (addedSec != null) 'added_sec': addedSec,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (extension != null) 'extension': extension,
      if (command != null) 'command': command,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MoviesCompanion copyWith({
    Value<String>? panelId,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? posterUrl,
    Value<double?>? rating,
    Value<int?>? year,
    Value<String?>? categoryId,
    Value<int?>? addedSec,
    Value<int?>? tmdbId,
    Value<String?>? extension,
    Value<String?>? command,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return MoviesCompanion(
      panelId: panelId ?? this.panelId,
      id: id ?? this.id,
      name: name ?? this.name,
      posterUrl: posterUrl ?? this.posterUrl,
      rating: rating ?? this.rating,
      year: year ?? this.year,
      categoryId: categoryId ?? this.categoryId,
      addedSec: addedSec ?? this.addedSec,
      tmdbId: tmdbId ?? this.tmdbId,
      extension: extension ?? this.extension,
      command: command ?? this.command,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (addedSec.present) {
      map['added_sec'] = Variable<int>(addedSec.value);
    }
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (extension.present) {
      map['extension'] = Variable<String>(extension.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoviesCompanion(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedSec: $addedSec, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('extension: $extension, ')
          ..write('command: $command, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesItemsTable extends SeriesItems
    with TableInfo<$SeriesItemsTable, SeriesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropUrlMeta = const VerificationMeta(
    'backdropUrl',
  );
  @override
  late final GeneratedColumn<String> backdropUrl = GeneratedColumn<String>(
    'backdrop_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genresMeta = const VerificationMeta('genres');
  @override
  late final GeneratedColumn<String> genres = GeneratedColumn<String>(
    'genres',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedSecMeta = const VerificationMeta(
    'addedSec',
  );
  @override
  late final GeneratedColumn<int> addedSec = GeneratedColumn<int>(
    'added_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tmdbIdMeta = const VerificationMeta('tmdbId');
  @override
  late final GeneratedColumn<int> tmdbId = GeneratedColumn<int>(
    'tmdb_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    id,
    name,
    posterUrl,
    backdropUrl,
    plot,
    genres,
    rating,
    year,
    categoryId,
    addedSec,
    tmdbId,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
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
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('backdrop_url')) {
      context.handle(
        _backdropUrlMeta,
        backdropUrl.isAcceptableOrUnknown(
          data['backdrop_url']!,
          _backdropUrlMeta,
        ),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('genres')) {
      context.handle(
        _genresMeta,
        genres.isAcceptableOrUnknown(data['genres']!, _genresMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('added_sec')) {
      context.handle(
        _addedSecMeta,
        addedSec.isAcceptableOrUnknown(data['added_sec']!, _addedSecMeta),
      );
    }
    if (data.containsKey('tmdb_id')) {
      context.handle(
        _tmdbIdMeta,
        tmdbId.isAcceptableOrUnknown(data['tmdb_id']!, _tmdbIdMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, id};
  @override
  SeriesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      backdropUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_url'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      genres: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genres'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      addedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_sec'],
      ),
      tmdbId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tmdb_id'],
      ),
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $SeriesItemsTable createAlias(String alias) {
    return $SeriesItemsTable(attachedDatabase, alias);
  }
}

class SeriesRow extends DataClass implements Insertable<SeriesRow> {
  final String panelId;
  final String id;
  final String name;
  final String? posterUrl;
  final String? backdropUrl;
  final String? plot;

  /// Comma-separated.
  final String genres;
  final double? rating;
  final int? year;
  final String? categoryId;
  final int? addedSec;
  final int? tmdbId;
  final int sort;
  const SeriesRow({
    required this.panelId,
    required this.id,
    required this.name,
    this.posterUrl,
    this.backdropUrl,
    this.plot,
    required this.genres,
    this.rating,
    this.year,
    this.categoryId,
    this.addedSec,
    this.tmdbId,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || backdropUrl != null) {
      map['backdrop_url'] = Variable<String>(backdropUrl);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    map['genres'] = Variable<String>(genres);
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<double>(rating);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || addedSec != null) {
      map['added_sec'] = Variable<int>(addedSec);
    }
    if (!nullToAbsent || tmdbId != null) {
      map['tmdb_id'] = Variable<int>(tmdbId);
    }
    map['sort'] = Variable<int>(sort);
    return map;
  }

  SeriesItemsCompanion toCompanion(bool nullToAbsent) {
    return SeriesItemsCompanion(
      panelId: Value(panelId),
      id: Value(id),
      name: Value(name),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      backdropUrl: backdropUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropUrl),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      genres: Value(genres),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      addedSec: addedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(addedSec),
      tmdbId: tmdbId == null && nullToAbsent
          ? const Value.absent()
          : Value(tmdbId),
      sort: Value(sort),
    );
  }

  factory SeriesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      backdropUrl: serializer.fromJson<String?>(json['backdropUrl']),
      plot: serializer.fromJson<String?>(json['plot']),
      genres: serializer.fromJson<String>(json['genres']),
      rating: serializer.fromJson<double?>(json['rating']),
      year: serializer.fromJson<int?>(json['year']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      addedSec: serializer.fromJson<int?>(json['addedSec']),
      tmdbId: serializer.fromJson<int?>(json['tmdbId']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'backdropUrl': serializer.toJson<String?>(backdropUrl),
      'plot': serializer.toJson<String?>(plot),
      'genres': serializer.toJson<String>(genres),
      'rating': serializer.toJson<double?>(rating),
      'year': serializer.toJson<int?>(year),
      'categoryId': serializer.toJson<String?>(categoryId),
      'addedSec': serializer.toJson<int?>(addedSec),
      'tmdbId': serializer.toJson<int?>(tmdbId),
      'sort': serializer.toJson<int>(sort),
    };
  }

  SeriesRow copyWith({
    String? panelId,
    String? id,
    String? name,
    Value<String?> posterUrl = const Value.absent(),
    Value<String?> backdropUrl = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    String? genres,
    Value<double?> rating = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<int?> addedSec = const Value.absent(),
    Value<int?> tmdbId = const Value.absent(),
    int? sort,
  }) => SeriesRow(
    panelId: panelId ?? this.panelId,
    id: id ?? this.id,
    name: name ?? this.name,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    backdropUrl: backdropUrl.present ? backdropUrl.value : this.backdropUrl,
    plot: plot.present ? plot.value : this.plot,
    genres: genres ?? this.genres,
    rating: rating.present ? rating.value : this.rating,
    year: year.present ? year.value : this.year,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    addedSec: addedSec.present ? addedSec.value : this.addedSec,
    tmdbId: tmdbId.present ? tmdbId.value : this.tmdbId,
    sort: sort ?? this.sort,
  );
  SeriesRow copyWithCompanion(SeriesItemsCompanion data) {
    return SeriesRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      backdropUrl: data.backdropUrl.present
          ? data.backdropUrl.value
          : this.backdropUrl,
      plot: data.plot.present ? data.plot.value : this.plot,
      genres: data.genres.present ? data.genres.value : this.genres,
      rating: data.rating.present ? data.rating.value : this.rating,
      year: data.year.present ? data.year.value : this.year,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      addedSec: data.addedSec.present ? data.addedSec.value : this.addedSec,
      tmdbId: data.tmdbId.present ? data.tmdbId.value : this.tmdbId,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesRow(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('backdropUrl: $backdropUrl, ')
          ..write('plot: $plot, ')
          ..write('genres: $genres, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedSec: $addedSec, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    panelId,
    id,
    name,
    posterUrl,
    backdropUrl,
    plot,
    genres,
    rating,
    year,
    categoryId,
    addedSec,
    tmdbId,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesRow &&
          other.panelId == this.panelId &&
          other.id == this.id &&
          other.name == this.name &&
          other.posterUrl == this.posterUrl &&
          other.backdropUrl == this.backdropUrl &&
          other.plot == this.plot &&
          other.genres == this.genres &&
          other.rating == this.rating &&
          other.year == this.year &&
          other.categoryId == this.categoryId &&
          other.addedSec == this.addedSec &&
          other.tmdbId == this.tmdbId &&
          other.sort == this.sort);
}

class SeriesItemsCompanion extends UpdateCompanion<SeriesRow> {
  final Value<String> panelId;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> posterUrl;
  final Value<String?> backdropUrl;
  final Value<String?> plot;
  final Value<String> genres;
  final Value<double?> rating;
  final Value<int?> year;
  final Value<String?> categoryId;
  final Value<int?> addedSec;
  final Value<int?> tmdbId;
  final Value<int> sort;
  final Value<int> rowid;
  const SeriesItemsCompanion({
    this.panelId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.backdropUrl = const Value.absent(),
    this.plot = const Value.absent(),
    this.genres = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.tmdbId = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesItemsCompanion.insert({
    required String panelId,
    required String id,
    required String name,
    this.posterUrl = const Value.absent(),
    this.backdropUrl = const Value.absent(),
    this.plot = const Value.absent(),
    this.genres = const Value.absent(),
    this.rating = const Value.absent(),
    this.year = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.addedSec = const Value.absent(),
    this.tmdbId = const Value.absent(),
    required int sort,
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       id = Value(id),
       name = Value(name),
       sort = Value(sort);
  static Insertable<SeriesRow> custom({
    Expression<String>? panelId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? posterUrl,
    Expression<String>? backdropUrl,
    Expression<String>? plot,
    Expression<String>? genres,
    Expression<double>? rating,
    Expression<int>? year,
    Expression<String>? categoryId,
    Expression<int>? addedSec,
    Expression<int>? tmdbId,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (backdropUrl != null) 'backdrop_url': backdropUrl,
      if (plot != null) 'plot': plot,
      if (genres != null) 'genres': genres,
      if (rating != null) 'rating': rating,
      if (year != null) 'year': year,
      if (categoryId != null) 'category_id': categoryId,
      if (addedSec != null) 'added_sec': addedSec,
      if (tmdbId != null) 'tmdb_id': tmdbId,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesItemsCompanion copyWith({
    Value<String>? panelId,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? posterUrl,
    Value<String?>? backdropUrl,
    Value<String?>? plot,
    Value<String>? genres,
    Value<double?>? rating,
    Value<int?>? year,
    Value<String?>? categoryId,
    Value<int?>? addedSec,
    Value<int?>? tmdbId,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return SeriesItemsCompanion(
      panelId: panelId ?? this.panelId,
      id: id ?? this.id,
      name: name ?? this.name,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      plot: plot ?? this.plot,
      genres: genres ?? this.genres,
      rating: rating ?? this.rating,
      year: year ?? this.year,
      categoryId: categoryId ?? this.categoryId,
      addedSec: addedSec ?? this.addedSec,
      tmdbId: tmdbId ?? this.tmdbId,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (backdropUrl.present) {
      map['backdrop_url'] = Variable<String>(backdropUrl.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (genres.present) {
      map['genres'] = Variable<String>(genres.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (addedSec.present) {
      map['added_sec'] = Variable<int>(addedSec.value);
    }
    if (tmdbId.present) {
      map['tmdb_id'] = Variable<int>(tmdbId.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesItemsCompanion(')
          ..write('panelId: $panelId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('backdropUrl: $backdropUrl, ')
          ..write('plot: $plot, ')
          ..write('genres: $genres, ')
          ..write('rating: $rating, ')
          ..write('year: $year, ')
          ..write('categoryId: $categoryId, ')
          ..write('addedSec: $addedSec, ')
          ..write('tmdbId: $tmdbId, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodesTable extends Episodes
    with TableInfo<$EpisodesTable, EpisodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stillUrlMeta = const VerificationMeta(
    'stillUrl',
  );
  @override
  late final GeneratedColumn<String> stillUrl = GeneratedColumn<String>(
    'still_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extensionMeta = const VerificationMeta(
    'extension',
  );
  @override
  late final GeneratedColumn<String> extension = GeneratedColumn<String>(
    'extension',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    seriesId,
    id,
    season,
    number,
    title,
    durationSec,
    plot,
    stillUrl,
    extension,
    command,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpisodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('still_url')) {
      context.handle(
        _stillUrlMeta,
        stillUrl.isAcceptableOrUnknown(data['still_url']!, _stillUrlMeta),
      );
    }
    if (data.containsKey('extension')) {
      context.handle(
        _extensionMeta,
        extension.isAcceptableOrUnknown(data['extension']!, _extensionMeta),
      );
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, id};
  @override
  EpisodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      stillUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}still_url'],
      ),
      extension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension'],
      ),
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      ),
    );
  }

  @override
  $EpisodesTable createAlias(String alias) {
    return $EpisodesTable(attachedDatabase, alias);
  }
}

class EpisodeRow extends DataClass implements Insertable<EpisodeRow> {
  final String panelId;
  final String seriesId;
  final String id;
  final int season;
  final int number;
  final String title;
  final int? durationSec;
  final String? plot;
  final String? stillUrl;
  final String? extension;
  final String? command;
  const EpisodeRow({
    required this.panelId,
    required this.seriesId,
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.durationSec,
    this.plot,
    this.stillUrl,
    this.extension,
    this.command,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['series_id'] = Variable<String>(seriesId);
    map['id'] = Variable<String>(id);
    map['season'] = Variable<int>(season);
    map['number'] = Variable<int>(number);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || durationSec != null) {
      map['duration_sec'] = Variable<int>(durationSec);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || stillUrl != null) {
      map['still_url'] = Variable<String>(stillUrl);
    }
    if (!nullToAbsent || extension != null) {
      map['extension'] = Variable<String>(extension);
    }
    if (!nullToAbsent || command != null) {
      map['command'] = Variable<String>(command);
    }
    return map;
  }

  EpisodesCompanion toCompanion(bool nullToAbsent) {
    return EpisodesCompanion(
      panelId: Value(panelId),
      seriesId: Value(seriesId),
      id: Value(id),
      season: Value(season),
      number: Value(number),
      title: Value(title),
      durationSec: durationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSec),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      stillUrl: stillUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(stillUrl),
      extension: extension == null && nullToAbsent
          ? const Value.absent()
          : Value(extension),
      command: command == null && nullToAbsent
          ? const Value.absent()
          : Value(command),
    );
  }

  factory EpisodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      id: serializer.fromJson<String>(json['id']),
      season: serializer.fromJson<int>(json['season']),
      number: serializer.fromJson<int>(json['number']),
      title: serializer.fromJson<String>(json['title']),
      durationSec: serializer.fromJson<int?>(json['durationSec']),
      plot: serializer.fromJson<String?>(json['plot']),
      stillUrl: serializer.fromJson<String?>(json['stillUrl']),
      extension: serializer.fromJson<String?>(json['extension']),
      command: serializer.fromJson<String?>(json['command']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'seriesId': serializer.toJson<String>(seriesId),
      'id': serializer.toJson<String>(id),
      'season': serializer.toJson<int>(season),
      'number': serializer.toJson<int>(number),
      'title': serializer.toJson<String>(title),
      'durationSec': serializer.toJson<int?>(durationSec),
      'plot': serializer.toJson<String?>(plot),
      'stillUrl': serializer.toJson<String?>(stillUrl),
      'extension': serializer.toJson<String?>(extension),
      'command': serializer.toJson<String?>(command),
    };
  }

  EpisodeRow copyWith({
    String? panelId,
    String? seriesId,
    String? id,
    int? season,
    int? number,
    String? title,
    Value<int?> durationSec = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<String?> stillUrl = const Value.absent(),
    Value<String?> extension = const Value.absent(),
    Value<String?> command = const Value.absent(),
  }) => EpisodeRow(
    panelId: panelId ?? this.panelId,
    seriesId: seriesId ?? this.seriesId,
    id: id ?? this.id,
    season: season ?? this.season,
    number: number ?? this.number,
    title: title ?? this.title,
    durationSec: durationSec.present ? durationSec.value : this.durationSec,
    plot: plot.present ? plot.value : this.plot,
    stillUrl: stillUrl.present ? stillUrl.value : this.stillUrl,
    extension: extension.present ? extension.value : this.extension,
    command: command.present ? command.value : this.command,
  );
  EpisodeRow copyWithCompanion(EpisodesCompanion data) {
    return EpisodeRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      id: data.id.present ? data.id.value : this.id,
      season: data.season.present ? data.season.value : this.season,
      number: data.number.present ? data.number.value : this.number,
      title: data.title.present ? data.title.value : this.title,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      plot: data.plot.present ? data.plot.value : this.plot,
      stillUrl: data.stillUrl.present ? data.stillUrl.value : this.stillUrl,
      extension: data.extension.present ? data.extension.value : this.extension,
      command: data.command.present ? data.command.value : this.command,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeRow(')
          ..write('panelId: $panelId, ')
          ..write('seriesId: $seriesId, ')
          ..write('id: $id, ')
          ..write('season: $season, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('durationSec: $durationSec, ')
          ..write('plot: $plot, ')
          ..write('stillUrl: $stillUrl, ')
          ..write('extension: $extension, ')
          ..write('command: $command')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    panelId,
    seriesId,
    id,
    season,
    number,
    title,
    durationSec,
    plot,
    stillUrl,
    extension,
    command,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeRow &&
          other.panelId == this.panelId &&
          other.seriesId == this.seriesId &&
          other.id == this.id &&
          other.season == this.season &&
          other.number == this.number &&
          other.title == this.title &&
          other.durationSec == this.durationSec &&
          other.plot == this.plot &&
          other.stillUrl == this.stillUrl &&
          other.extension == this.extension &&
          other.command == this.command);
}

class EpisodesCompanion extends UpdateCompanion<EpisodeRow> {
  final Value<String> panelId;
  final Value<String> seriesId;
  final Value<String> id;
  final Value<int> season;
  final Value<int> number;
  final Value<String> title;
  final Value<int?> durationSec;
  final Value<String?> plot;
  final Value<String?> stillUrl;
  final Value<String?> extension;
  final Value<String?> command;
  final Value<int> rowid;
  const EpisodesCompanion({
    this.panelId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.id = const Value.absent(),
    this.season = const Value.absent(),
    this.number = const Value.absent(),
    this.title = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.plot = const Value.absent(),
    this.stillUrl = const Value.absent(),
    this.extension = const Value.absent(),
    this.command = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodesCompanion.insert({
    required String panelId,
    required String seriesId,
    required String id,
    required int season,
    required int number,
    required String title,
    this.durationSec = const Value.absent(),
    this.plot = const Value.absent(),
    this.stillUrl = const Value.absent(),
    this.extension = const Value.absent(),
    this.command = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       seriesId = Value(seriesId),
       id = Value(id),
       season = Value(season),
       number = Value(number),
       title = Value(title);
  static Insertable<EpisodeRow> custom({
    Expression<String>? panelId,
    Expression<String>? seriesId,
    Expression<String>? id,
    Expression<int>? season,
    Expression<int>? number,
    Expression<String>? title,
    Expression<int>? durationSec,
    Expression<String>? plot,
    Expression<String>? stillUrl,
    Expression<String>? extension,
    Expression<String>? command,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (seriesId != null) 'series_id': seriesId,
      if (id != null) 'id': id,
      if (season != null) 'season': season,
      if (number != null) 'number': number,
      if (title != null) 'title': title,
      if (durationSec != null) 'duration_sec': durationSec,
      if (plot != null) 'plot': plot,
      if (stillUrl != null) 'still_url': stillUrl,
      if (extension != null) 'extension': extension,
      if (command != null) 'command': command,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodesCompanion copyWith({
    Value<String>? panelId,
    Value<String>? seriesId,
    Value<String>? id,
    Value<int>? season,
    Value<int>? number,
    Value<String>? title,
    Value<int?>? durationSec,
    Value<String?>? plot,
    Value<String?>? stillUrl,
    Value<String?>? extension,
    Value<String?>? command,
    Value<int>? rowid,
  }) {
    return EpisodesCompanion(
      panelId: panelId ?? this.panelId,
      seriesId: seriesId ?? this.seriesId,
      id: id ?? this.id,
      season: season ?? this.season,
      number: number ?? this.number,
      title: title ?? this.title,
      durationSec: durationSec ?? this.durationSec,
      plot: plot ?? this.plot,
      stillUrl: stillUrl ?? this.stillUrl,
      extension: extension ?? this.extension,
      command: command ?? this.command,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (stillUrl.present) {
      map['still_url'] = Variable<String>(stillUrl.value);
    }
    if (extension.present) {
      map['extension'] = Variable<String>(extension.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesCompanion(')
          ..write('panelId: $panelId, ')
          ..write('seriesId: $seriesId, ')
          ..write('id: $id, ')
          ..write('season: $season, ')
          ..write('number: $number, ')
          ..write('title: $title, ')
          ..write('durationSec: $durationSec, ')
          ..write('plot: $plot, ')
          ..write('stillUrl: $stillUrl, ')
          ..write('extension: $extension, ')
          ..write('command: $command, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpgTable extends Epg with TableInfo<$EpgTable, EpgRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpgTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startSecMeta = const VerificationMeta(
    'startSec',
  );
  @override
  late final GeneratedColumn<int> startSec = GeneratedColumn<int>(
    'start_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endSecMeta = const VerificationMeta('endSec');
  @override
  late final GeneratedColumn<int> endSec = GeneratedColumn<int>(
    'end_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    channelId,
    startSec,
    endSec,
    title,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'epg';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpgRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('start_sec')) {
      context.handle(
        _startSecMeta,
        startSec.isAcceptableOrUnknown(data['start_sec']!, _startSecMeta),
      );
    } else if (isInserting) {
      context.missing(_startSecMeta);
    }
    if (data.containsKey('end_sec')) {
      context.handle(
        _endSecMeta,
        endSec.isAcceptableOrUnknown(data['end_sec']!, _endSecMeta),
      );
    } else if (isInserting) {
      context.missing(_endSecMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, channelId, startSec};
  @override
  EpgRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpgRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      )!,
      startSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_sec'],
      )!,
      endSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_sec'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
    );
  }

  @override
  $EpgTable createAlias(String alias) {
    return $EpgTable(attachedDatabase, alias);
  }
}

class EpgRow extends DataClass implements Insertable<EpgRow> {
  final String panelId;
  final String channelId;
  final int startSec;
  final int endSec;
  final String title;
  final String? description;
  const EpgRow({
    required this.panelId,
    required this.channelId,
    required this.startSec,
    required this.endSec,
    required this.title,
    this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['channel_id'] = Variable<String>(channelId);
    map['start_sec'] = Variable<int>(startSec);
    map['end_sec'] = Variable<int>(endSec);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    return map;
  }

  EpgCompanion toCompanion(bool nullToAbsent) {
    return EpgCompanion(
      panelId: Value(panelId),
      channelId: Value(channelId),
      startSec: Value(startSec),
      endSec: Value(endSec),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
    );
  }

  factory EpgRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpgRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      channelId: serializer.fromJson<String>(json['channelId']),
      startSec: serializer.fromJson<int>(json['startSec']),
      endSec: serializer.fromJson<int>(json['endSec']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'channelId': serializer.toJson<String>(channelId),
      'startSec': serializer.toJson<int>(startSec),
      'endSec': serializer.toJson<int>(endSec),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
    };
  }

  EpgRow copyWith({
    String? panelId,
    String? channelId,
    int? startSec,
    int? endSec,
    String? title,
    Value<String?> description = const Value.absent(),
  }) => EpgRow(
    panelId: panelId ?? this.panelId,
    channelId: channelId ?? this.channelId,
    startSec: startSec ?? this.startSec,
    endSec: endSec ?? this.endSec,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
  );
  EpgRow copyWithCompanion(EpgCompanion data) {
    return EpgRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      startSec: data.startSec.present ? data.startSec.value : this.startSec,
      endSec: data.endSec.present ? data.endSec.value : this.endSec,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpgRow(')
          ..write('panelId: $panelId, ')
          ..write('channelId: $channelId, ')
          ..write('startSec: $startSec, ')
          ..write('endSec: $endSec, ')
          ..write('title: $title, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(panelId, channelId, startSec, endSec, title, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpgRow &&
          other.panelId == this.panelId &&
          other.channelId == this.channelId &&
          other.startSec == this.startSec &&
          other.endSec == this.endSec &&
          other.title == this.title &&
          other.description == this.description);
}

class EpgCompanion extends UpdateCompanion<EpgRow> {
  final Value<String> panelId;
  final Value<String> channelId;
  final Value<int> startSec;
  final Value<int> endSec;
  final Value<String> title;
  final Value<String?> description;
  final Value<int> rowid;
  const EpgCompanion({
    this.panelId = const Value.absent(),
    this.channelId = const Value.absent(),
    this.startSec = const Value.absent(),
    this.endSec = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpgCompanion.insert({
    required String panelId,
    required String channelId,
    required int startSec,
    required int endSec,
    required String title,
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       channelId = Value(channelId),
       startSec = Value(startSec),
       endSec = Value(endSec),
       title = Value(title);
  static Insertable<EpgRow> custom({
    Expression<String>? panelId,
    Expression<String>? channelId,
    Expression<int>? startSec,
    Expression<int>? endSec,
    Expression<String>? title,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (channelId != null) 'channel_id': channelId,
      if (startSec != null) 'start_sec': startSec,
      if (endSec != null) 'end_sec': endSec,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpgCompanion copyWith({
    Value<String>? panelId,
    Value<String>? channelId,
    Value<int>? startSec,
    Value<int>? endSec,
    Value<String>? title,
    Value<String?>? description,
    Value<int>? rowid,
  }) {
    return EpgCompanion(
      panelId: panelId ?? this.panelId,
      channelId: channelId ?? this.channelId,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      title: title ?? this.title,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (startSec.present) {
      map['start_sec'] = Variable<int>(startSec.value);
    }
    if (endSec.present) {
      map['end_sec'] = Variable<int>(endSec.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpgCompanion(')
          ..write('panelId: $panelId, ')
          ..write('channelId: $channelId, ')
          ..write('startSec: $startSec, ')
          ..write('endSec: $endSec, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _panelIdMeta = const VerificationMeta(
    'panelId',
  );
  @override
  late final GeneratedColumn<String> panelId = GeneratedColumn<String>(
    'panel_id',
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
  static const VerificationMeta _syncedAtSecMeta = const VerificationMeta(
    'syncedAtSec',
  );
  @override
  late final GeneratedColumn<int> syncedAtSec = GeneratedColumn<int>(
    'synced_at_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemCountMeta = const VerificationMeta(
    'itemCount',
  );
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
    'item_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxAddedSecMeta = const VerificationMeta(
    'maxAddedSec',
  );
  @override
  late final GeneratedColumn<int> maxAddedSec = GeneratedColumn<int>(
    'max_added_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    panelId,
    scope,
    syncedAtSec,
    itemCount,
    maxAddedSec,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('panel_id')) {
      context.handle(
        _panelIdMeta,
        panelId.isAcceptableOrUnknown(data['panel_id']!, _panelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_panelIdMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('synced_at_sec')) {
      context.handle(
        _syncedAtSecMeta,
        syncedAtSec.isAcceptableOrUnknown(
          data['synced_at_sec']!,
          _syncedAtSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_syncedAtSecMeta);
    }
    if (data.containsKey('item_count')) {
      context.handle(
        _itemCountMeta,
        itemCount.isAcceptableOrUnknown(data['item_count']!, _itemCountMeta),
      );
    }
    if (data.containsKey('max_added_sec')) {
      context.handle(
        _maxAddedSecMeta,
        maxAddedSec.isAcceptableOrUnknown(
          data['max_added_sec']!,
          _maxAddedSecMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {panelId, scope};
  @override
  SyncRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncRow(
      panelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}panel_id'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      syncedAtSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_sec'],
      )!,
      itemCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_count'],
      )!,
      maxAddedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_added_sec'],
      ),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncRow extends DataClass implements Insertable<SyncRow> {
  final String panelId;
  final String scope;
  final int syncedAtSec;
  final int itemCount;

  /// Newest `added` seen (cheap "what's new" check next time).
  final int? maxAddedSec;
  const SyncRow({
    required this.panelId,
    required this.scope,
    required this.syncedAtSec,
    required this.itemCount,
    this.maxAddedSec,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['panel_id'] = Variable<String>(panelId);
    map['scope'] = Variable<String>(scope);
    map['synced_at_sec'] = Variable<int>(syncedAtSec);
    map['item_count'] = Variable<int>(itemCount);
    if (!nullToAbsent || maxAddedSec != null) {
      map['max_added_sec'] = Variable<int>(maxAddedSec);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      panelId: Value(panelId),
      scope: Value(scope),
      syncedAtSec: Value(syncedAtSec),
      itemCount: Value(itemCount),
      maxAddedSec: maxAddedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(maxAddedSec),
    );
  }

  factory SyncRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncRow(
      panelId: serializer.fromJson<String>(json['panelId']),
      scope: serializer.fromJson<String>(json['scope']),
      syncedAtSec: serializer.fromJson<int>(json['syncedAtSec']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
      maxAddedSec: serializer.fromJson<int?>(json['maxAddedSec']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'panelId': serializer.toJson<String>(panelId),
      'scope': serializer.toJson<String>(scope),
      'syncedAtSec': serializer.toJson<int>(syncedAtSec),
      'itemCount': serializer.toJson<int>(itemCount),
      'maxAddedSec': serializer.toJson<int?>(maxAddedSec),
    };
  }

  SyncRow copyWith({
    String? panelId,
    String? scope,
    int? syncedAtSec,
    int? itemCount,
    Value<int?> maxAddedSec = const Value.absent(),
  }) => SyncRow(
    panelId: panelId ?? this.panelId,
    scope: scope ?? this.scope,
    syncedAtSec: syncedAtSec ?? this.syncedAtSec,
    itemCount: itemCount ?? this.itemCount,
    maxAddedSec: maxAddedSec.present ? maxAddedSec.value : this.maxAddedSec,
  );
  SyncRow copyWithCompanion(SyncStateCompanion data) {
    return SyncRow(
      panelId: data.panelId.present ? data.panelId.value : this.panelId,
      scope: data.scope.present ? data.scope.value : this.scope,
      syncedAtSec: data.syncedAtSec.present
          ? data.syncedAtSec.value
          : this.syncedAtSec,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
      maxAddedSec: data.maxAddedSec.present
          ? data.maxAddedSec.value
          : this.maxAddedSec,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncRow(')
          ..write('panelId: $panelId, ')
          ..write('scope: $scope, ')
          ..write('syncedAtSec: $syncedAtSec, ')
          ..write('itemCount: $itemCount, ')
          ..write('maxAddedSec: $maxAddedSec')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(panelId, scope, syncedAtSec, itemCount, maxAddedSec);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncRow &&
          other.panelId == this.panelId &&
          other.scope == this.scope &&
          other.syncedAtSec == this.syncedAtSec &&
          other.itemCount == this.itemCount &&
          other.maxAddedSec == this.maxAddedSec);
}

class SyncStateCompanion extends UpdateCompanion<SyncRow> {
  final Value<String> panelId;
  final Value<String> scope;
  final Value<int> syncedAtSec;
  final Value<int> itemCount;
  final Value<int?> maxAddedSec;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.panelId = const Value.absent(),
    this.scope = const Value.absent(),
    this.syncedAtSec = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.maxAddedSec = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String panelId,
    required String scope,
    required int syncedAtSec,
    this.itemCount = const Value.absent(),
    this.maxAddedSec = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : panelId = Value(panelId),
       scope = Value(scope),
       syncedAtSec = Value(syncedAtSec);
  static Insertable<SyncRow> custom({
    Expression<String>? panelId,
    Expression<String>? scope,
    Expression<int>? syncedAtSec,
    Expression<int>? itemCount,
    Expression<int>? maxAddedSec,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (panelId != null) 'panel_id': panelId,
      if (scope != null) 'scope': scope,
      if (syncedAtSec != null) 'synced_at_sec': syncedAtSec,
      if (itemCount != null) 'item_count': itemCount,
      if (maxAddedSec != null) 'max_added_sec': maxAddedSec,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? panelId,
    Value<String>? scope,
    Value<int>? syncedAtSec,
    Value<int>? itemCount,
    Value<int?>? maxAddedSec,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      panelId: panelId ?? this.panelId,
      scope: scope ?? this.scope,
      syncedAtSec: syncedAtSec ?? this.syncedAtSec,
      itemCount: itemCount ?? this.itemCount,
      maxAddedSec: maxAddedSec ?? this.maxAddedSec,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (panelId.present) {
      map['panel_id'] = Variable<String>(panelId.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (syncedAtSec.present) {
      map['synced_at_sec'] = Variable<int>(syncedAtSec.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    if (maxAddedSec.present) {
      map['max_added_sec'] = Variable<int>(maxAddedSec.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('panelId: $panelId, ')
          ..write('scope: $scope, ')
          ..write('syncedAtSec: $syncedAtSec, ')
          ..write('itemCount: $itemCount, ')
          ..write('maxAddedSec: $maxAddedSec, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CatalogDb extends GeneratedDatabase {
  _$CatalogDb(QueryExecutor e) : super(e);
  $CatalogDbManager get managers => $CatalogDbManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MoviesTable movies = $MoviesTable(this);
  late final $SeriesItemsTable seriesItems = $SeriesItemsTable(this);
  late final $EpisodesTable episodes = $EpisodesTable(this);
  late final $EpgTable epg = $EpgTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final Index categoriesByKind = Index(
    'categories_by_kind',
    'CREATE INDEX categories_by_kind ON categories (panel_id, kind, sort)',
  );
  late final Index channelsByCategory = Index(
    'channels_by_category',
    'CREATE INDEX channels_by_category ON channels (panel_id, category_id, sort)',
  );
  late final Index moviesByCategory = Index(
    'movies_by_category',
    'CREATE INDEX movies_by_category ON movies (panel_id, category_id, sort)',
  );
  late final Index moviesByAdded = Index(
    'movies_by_added',
    'CREATE INDEX movies_by_added ON movies (panel_id, added_sec)',
  );
  late final Index moviesByTmdb = Index(
    'movies_by_tmdb',
    'CREATE INDEX movies_by_tmdb ON movies (tmdb_id)',
  );
  late final Index seriesByCategory = Index(
    'series_by_category',
    'CREATE INDEX series_by_category ON series (panel_id, category_id, sort)',
  );
  late final Index seriesByAdded = Index(
    'series_by_added',
    'CREATE INDEX series_by_added ON series (panel_id, added_sec)',
  );
  late final Index seriesByTmdb = Index(
    'series_by_tmdb',
    'CREATE INDEX series_by_tmdb ON series (tmdb_id)',
  );
  late final Index episodesBySeries = Index(
    'episodes_by_series',
    'CREATE INDEX episodes_by_series ON episodes (panel_id, series_id, season, number)',
  );
  late final Index epgByEnd = Index(
    'epg_by_end',
    'CREATE INDEX epg_by_end ON epg (panel_id, end_sec)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    channels,
    movies,
    seriesItems,
    episodes,
    epg,
    syncState,
    categoriesByKind,
    channelsByCategory,
    moviesByCategory,
    moviesByAdded,
    moviesByTmdb,
    seriesByCategory,
    seriesByAdded,
    seriesByTmdb,
    episodesBySeries,
    epgByEnd,
  ];
}

typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String panelId,
  required String kind,
  required String id,
  required String name,
  Value<String?> parentId,
  required int sort,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> panelId,
  Value<String> kind,
  Value<String> id,
  Value<String> name,
  Value<String?> parentId,
  Value<int> sort,
  Value<int> rowid,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$CatalogDb, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$CatalogDb, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$CatalogDb, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            CategoryRow,
            BaseReferences<_$CatalogDb, $CategoriesTable, CategoryRow>,
          ),
          CategoryRow,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$CatalogDb db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                panelId: panelId,
                kind: kind,
                id: id,
                name: name,
                parentId: parentId,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String kind,
                required String id,
                required String name,
                Value<String?> parentId = const Value.absent(),
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                panelId: panelId,
                kind: kind,
                id: id,
                name: name,
                parentId: parentId,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, CategoryRow>(table),
                  BaseReferences<_$CatalogDb, $CategoriesTable, CategoryRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, BaseReferences<_$CatalogDb, $CategoriesTable, CategoryRow>),
      CategoryRow,
      PrefetchHooks Function()
    >;
typedef $$ChannelsTableCreateCompanionBuilder = ChannelsCompanion Function({
  required String panelId,
  required String id,
  required String name,
  Value<int?> number,
  Value<String?> logoUrl,
  Value<String?> categoryId,
  Value<String?> epgId,
  Value<int> catchupDays,
  Value<int?> addedSec,
  Value<String?> command,
  required int sort,
  Value<int> rowid,
});
typedef $$ChannelsTableUpdateCompanionBuilder = ChannelsCompanion Function({
  Value<String> panelId,
  Value<String> id,
  Value<String> name,
  Value<int?> number,
  Value<String?> logoUrl,
  Value<String?> categoryId,
  Value<String?> epgId,
  Value<int> catchupDays,
  Value<int?> addedSec,
  Value<String?> command,
  Value<int> sort,
  Value<int> rowid,
});

class $$ChannelsTableFilterComposer
    extends Composer<_$CatalogDb, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epgId => $composableBuilder(
    column: $table.epgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get catchupDays => $composableBuilder(
    column: $table.catchupDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$CatalogDb, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epgId => $composableBuilder(
    column: $table.epgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get catchupDays => $composableBuilder(
    column: $table.catchupDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$CatalogDb, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get epgId =>
      $composableBuilder(column: $table.epgId, builder: (column) => column);

  GeneratedColumn<int> get catchupDays => $composableBuilder(
    column: $table.catchupDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedSec =>
      $composableBuilder(column: $table.addedSec, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $ChannelsTable,
          ChannelRow,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (ChannelRow, BaseReferences<_$CatalogDb, $ChannelsTable, ChannelRow>),
          ChannelRow,
          PrefetchHooks Function()
        > {
  $$ChannelsTableTableManager(_$CatalogDb db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> number = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> epgId = const Value.absent(),
                Value<int> catchupDays = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<String?> command = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                panelId: panelId,
                id: id,
                name: name,
                number: number,
                logoUrl: logoUrl,
                categoryId: categoryId,
                epgId: epgId,
                catchupDays: catchupDays,
                addedSec: addedSec,
                command: command,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String id,
                required String name,
                Value<int?> number = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> epgId = const Value.absent(),
                Value<int> catchupDays = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<String?> command = const Value.absent(),
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                panelId: panelId,
                id: id,
                name: name,
                number: number,
                logoUrl: logoUrl,
                categoryId: categoryId,
                epgId: epgId,
                catchupDays: catchupDays,
                addedSec: addedSec,
                command: command,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChannelsTable, ChannelRow>(table),
                  BaseReferences<_$CatalogDb, $ChannelsTable, ChannelRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $ChannelsTable,
      ChannelRow,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (ChannelRow, BaseReferences<_$CatalogDb, $ChannelsTable, ChannelRow>),
      ChannelRow,
      PrefetchHooks Function()
    >;
typedef $$MoviesTableCreateCompanionBuilder = MoviesCompanion Function({
  required String panelId,
  required String id,
  required String name,
  Value<String?> posterUrl,
  Value<double?> rating,
  Value<int?> year,
  Value<String?> categoryId,
  Value<int?> addedSec,
  Value<int?> tmdbId,
  Value<String?> extension,
  Value<String?> command,
  required int sort,
  Value<int> rowid,
});
typedef $$MoviesTableUpdateCompanionBuilder = MoviesCompanion Function({
  Value<String> panelId,
  Value<String> id,
  Value<String> name,
  Value<String?> posterUrl,
  Value<double?> rating,
  Value<int?> year,
  Value<String?> categoryId,
  Value<int?> addedSec,
  Value<int?> tmdbId,
  Value<String?> extension,
  Value<String?> command,
  Value<int> sort,
  Value<int> rowid,
});

class $$MoviesTableFilterComposer extends Composer<_$CatalogDb, $MoviesTable> {
  $$MoviesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MoviesTableOrderingComposer
    extends Composer<_$CatalogDb, $MoviesTable> {
  $$MoviesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MoviesTableAnnotationComposer
    extends Composer<_$CatalogDb, $MoviesTable> {
  $$MoviesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedSec =>
      $composableBuilder(column: $table.addedSec, builder: (column) => column);

  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<String> get extension =>
      $composableBuilder(column: $table.extension, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$MoviesTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $MoviesTable,
          MovieRow,
          $$MoviesTableFilterComposer,
          $$MoviesTableOrderingComposer,
          $$MoviesTableAnnotationComposer,
          $$MoviesTableCreateCompanionBuilder,
          $$MoviesTableUpdateCompanionBuilder,
          (MovieRow, BaseReferences<_$CatalogDb, $MoviesTable, MovieRow>),
          MovieRow,
          PrefetchHooks Function()
        > {
  $$MoviesTableTableManager(_$CatalogDb db, $MoviesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MoviesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MoviesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MoviesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<int?> tmdbId = const Value.absent(),
                Value<String?> extension = const Value.absent(),
                Value<String?> command = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MoviesCompanion(
                panelId: panelId,
                id: id,
                name: name,
                posterUrl: posterUrl,
                rating: rating,
                year: year,
                categoryId: categoryId,
                addedSec: addedSec,
                tmdbId: tmdbId,
                extension: extension,
                command: command,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String id,
                required String name,
                Value<String?> posterUrl = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<int?> tmdbId = const Value.absent(),
                Value<String?> extension = const Value.absent(),
                Value<String?> command = const Value.absent(),
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => MoviesCompanion.insert(
                panelId: panelId,
                id: id,
                name: name,
                posterUrl: posterUrl,
                rating: rating,
                year: year,
                categoryId: categoryId,
                addedSec: addedSec,
                tmdbId: tmdbId,
                extension: extension,
                command: command,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MoviesTable, MovieRow>(table),
                  BaseReferences<_$CatalogDb, $MoviesTable, MovieRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MoviesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $MoviesTable,
      MovieRow,
      $$MoviesTableFilterComposer,
      $$MoviesTableOrderingComposer,
      $$MoviesTableAnnotationComposer,
      $$MoviesTableCreateCompanionBuilder,
      $$MoviesTableUpdateCompanionBuilder,
      (MovieRow, BaseReferences<_$CatalogDb, $MoviesTable, MovieRow>),
      MovieRow,
      PrefetchHooks Function()
    >;
typedef $$SeriesItemsTableCreateCompanionBuilder =
    SeriesItemsCompanion Function({
      required String panelId,
      required String id,
      required String name,
      Value<String?> posterUrl,
      Value<String?> backdropUrl,
      Value<String?> plot,
      Value<String> genres,
      Value<double?> rating,
      Value<int?> year,
      Value<String?> categoryId,
      Value<int?> addedSec,
      Value<int?> tmdbId,
      required int sort,
      Value<int> rowid,
    });
typedef $$SeriesItemsTableUpdateCompanionBuilder =
    SeriesItemsCompanion Function({
      Value<String> panelId,
      Value<String> id,
      Value<String> name,
      Value<String?> posterUrl,
      Value<String?> backdropUrl,
      Value<String?> plot,
      Value<String> genres,
      Value<double?> rating,
      Value<int?> year,
      Value<String?> categoryId,
      Value<int?> addedSec,
      Value<int?> tmdbId,
      Value<int> sort,
      Value<int> rowid,
    });

class $$SeriesItemsTableFilterComposer
    extends Composer<_$CatalogDb, $SeriesItemsTable> {
  $$SeriesItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropUrl => $composableBuilder(
    column: $table.backdropUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genres => $composableBuilder(
    column: $table.genres,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesItemsTableOrderingComposer
    extends Composer<_$CatalogDb, $SeriesItemsTable> {
  $$SeriesItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropUrl => $composableBuilder(
    column: $table.backdropUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genres => $composableBuilder(
    column: $table.genres,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedSec => $composableBuilder(
    column: $table.addedSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tmdbId => $composableBuilder(
    column: $table.tmdbId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesItemsTableAnnotationComposer
    extends Composer<_$CatalogDb, $SeriesItemsTable> {
  $$SeriesItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<String> get backdropUrl => $composableBuilder(
    column: $table.backdropUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<String> get genres =>
      $composableBuilder(column: $table.genres, builder: (column) => column);

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedSec =>
      $composableBuilder(column: $table.addedSec, builder: (column) => column);

  GeneratedColumn<int> get tmdbId =>
      $composableBuilder(column: $table.tmdbId, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$SeriesItemsTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $SeriesItemsTable,
          SeriesRow,
          $$SeriesItemsTableFilterComposer,
          $$SeriesItemsTableOrderingComposer,
          $$SeriesItemsTableAnnotationComposer,
          $$SeriesItemsTableCreateCompanionBuilder,
          $$SeriesItemsTableUpdateCompanionBuilder,
          (
            SeriesRow,
            BaseReferences<_$CatalogDb, $SeriesItemsTable, SeriesRow>,
          ),
          SeriesRow,
          PrefetchHooks Function()
        > {
  $$SeriesItemsTableTableManager(_$CatalogDb db, $SeriesItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> backdropUrl = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String> genres = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<int?> tmdbId = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesItemsCompanion(
                panelId: panelId,
                id: id,
                name: name,
                posterUrl: posterUrl,
                backdropUrl: backdropUrl,
                plot: plot,
                genres: genres,
                rating: rating,
                year: year,
                categoryId: categoryId,
                addedSec: addedSec,
                tmdbId: tmdbId,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String id,
                required String name,
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> backdropUrl = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String> genres = const Value.absent(),
                Value<double?> rating = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int?> addedSec = const Value.absent(),
                Value<int?> tmdbId = const Value.absent(),
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => SeriesItemsCompanion.insert(
                panelId: panelId,
                id: id,
                name: name,
                posterUrl: posterUrl,
                backdropUrl: backdropUrl,
                plot: plot,
                genres: genres,
                rating: rating,
                year: year,
                categoryId: categoryId,
                addedSec: addedSec,
                tmdbId: tmdbId,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeriesItemsTable, SeriesRow>(table),
                  BaseReferences<_$CatalogDb, $SeriesItemsTable, SeriesRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $SeriesItemsTable,
      SeriesRow,
      $$SeriesItemsTableFilterComposer,
      $$SeriesItemsTableOrderingComposer,
      $$SeriesItemsTableAnnotationComposer,
      $$SeriesItemsTableCreateCompanionBuilder,
      $$SeriesItemsTableUpdateCompanionBuilder,
      (SeriesRow, BaseReferences<_$CatalogDb, $SeriesItemsTable, SeriesRow>),
      SeriesRow,
      PrefetchHooks Function()
    >;
typedef $$EpisodesTableCreateCompanionBuilder = EpisodesCompanion Function({
  required String panelId,
  required String seriesId,
  required String id,
  required int season,
  required int number,
  required String title,
  Value<int?> durationSec,
  Value<String?> plot,
  Value<String?> stillUrl,
  Value<String?> extension,
  Value<String?> command,
  Value<int> rowid,
});
typedef $$EpisodesTableUpdateCompanionBuilder = EpisodesCompanion Function({
  Value<String> panelId,
  Value<String> seriesId,
  Value<String> id,
  Value<int> season,
  Value<int> number,
  Value<String> title,
  Value<int?> durationSec,
  Value<String?> plot,
  Value<String?> stillUrl,
  Value<String?> extension,
  Value<String?> command,
  Value<int> rowid,
});

class $$EpisodesTableFilterComposer
    extends Composer<_$CatalogDb, $EpisodesTable> {
  $$EpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stillUrl => $composableBuilder(
    column: $table.stillUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpisodesTableOrderingComposer
    extends Composer<_$CatalogDb, $EpisodesTable> {
  $$EpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stillUrl => $composableBuilder(
    column: $table.stillUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extension => $composableBuilder(
    column: $table.extension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpisodesTableAnnotationComposer
    extends Composer<_$CatalogDb, $EpisodesTable> {
  $$EpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<String> get stillUrl =>
      $composableBuilder(column: $table.stillUrl, builder: (column) => column);

  GeneratedColumn<String> get extension =>
      $composableBuilder(column: $table.extension, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);
}

class $$EpisodesTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $EpisodesTable,
          EpisodeRow,
          $$EpisodesTableFilterComposer,
          $$EpisodesTableOrderingComposer,
          $$EpisodesTableAnnotationComposer,
          $$EpisodesTableCreateCompanionBuilder,
          $$EpisodesTableUpdateCompanionBuilder,
          (EpisodeRow, BaseReferences<_$CatalogDb, $EpisodesTable, EpisodeRow>),
          EpisodeRow,
          PrefetchHooks Function()
        > {
  $$EpisodesTableTableManager(_$CatalogDb db, $EpisodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> season = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> durationSec = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> stillUrl = const Value.absent(),
                Value<String?> extension = const Value.absent(),
                Value<String?> command = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodesCompanion(
                panelId: panelId,
                seriesId: seriesId,
                id: id,
                season: season,
                number: number,
                title: title,
                durationSec: durationSec,
                plot: plot,
                stillUrl: stillUrl,
                extension: extension,
                command: command,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String seriesId,
                required String id,
                required int season,
                required int number,
                required String title,
                Value<int?> durationSec = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<String?> stillUrl = const Value.absent(),
                Value<String?> extension = const Value.absent(),
                Value<String?> command = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodesCompanion.insert(
                panelId: panelId,
                seriesId: seriesId,
                id: id,
                season: season,
                number: number,
                title: title,
                durationSec: durationSec,
                plot: plot,
                stillUrl: stillUrl,
                extension: extension,
                command: command,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EpisodesTable, EpisodeRow>(table),
                  BaseReferences<_$CatalogDb, $EpisodesTable, EpisodeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $EpisodesTable,
      EpisodeRow,
      $$EpisodesTableFilterComposer,
      $$EpisodesTableOrderingComposer,
      $$EpisodesTableAnnotationComposer,
      $$EpisodesTableCreateCompanionBuilder,
      $$EpisodesTableUpdateCompanionBuilder,
      (EpisodeRow, BaseReferences<_$CatalogDb, $EpisodesTable, EpisodeRow>),
      EpisodeRow,
      PrefetchHooks Function()
    >;
typedef $$EpgTableCreateCompanionBuilder = EpgCompanion Function({
  required String panelId,
  required String channelId,
  required int startSec,
  required int endSec,
  required String title,
  Value<String?> description,
  Value<int> rowid,
});
typedef $$EpgTableUpdateCompanionBuilder = EpgCompanion Function({
  Value<String> panelId,
  Value<String> channelId,
  Value<int> startSec,
  Value<int> endSec,
  Value<String> title,
  Value<String?> description,
  Value<int> rowid,
});

class $$EpgTableFilterComposer extends Composer<_$CatalogDb, $EpgTable> {
  $$EpgTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startSec => $composableBuilder(
    column: $table.startSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endSec => $composableBuilder(
    column: $table.endSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpgTableOrderingComposer extends Composer<_$CatalogDb, $EpgTable> {
  $$EpgTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startSec => $composableBuilder(
    column: $table.startSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endSec => $composableBuilder(
    column: $table.endSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpgTableAnnotationComposer extends Composer<_$CatalogDb, $EpgTable> {
  $$EpgTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<int> get startSec =>
      $composableBuilder(column: $table.startSec, builder: (column) => column);

  GeneratedColumn<int> get endSec =>
      $composableBuilder(column: $table.endSec, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$EpgTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $EpgTable,
          EpgRow,
          $$EpgTableFilterComposer,
          $$EpgTableOrderingComposer,
          $$EpgTableAnnotationComposer,
          $$EpgTableCreateCompanionBuilder,
          $$EpgTableUpdateCompanionBuilder,
          (EpgRow, BaseReferences<_$CatalogDb, $EpgTable, EpgRow>),
          EpgRow,
          PrefetchHooks Function()
        > {
  $$EpgTableTableManager(_$CatalogDb db, $EpgTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpgTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpgTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpgTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> channelId = const Value.absent(),
                Value<int> startSec = const Value.absent(),
                Value<int> endSec = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpgCompanion(
                panelId: panelId,
                channelId: channelId,
                startSec: startSec,
                endSec: endSec,
                title: title,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String channelId,
                required int startSec,
                required int endSec,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpgCompanion.insert(
                panelId: panelId,
                channelId: channelId,
                startSec: startSec,
                endSec: endSec,
                title: title,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EpgTable, EpgRow>(table),
                  BaseReferences<_$CatalogDb, $EpgTable, EpgRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpgTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $EpgTable,
      EpgRow,
      $$EpgTableFilterComposer,
      $$EpgTableOrderingComposer,
      $$EpgTableAnnotationComposer,
      $$EpgTableCreateCompanionBuilder,
      $$EpgTableUpdateCompanionBuilder,
      (EpgRow, BaseReferences<_$CatalogDb, $EpgTable, EpgRow>),
      EpgRow,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String panelId,
  required String scope,
  required int syncedAtSec,
  Value<int> itemCount,
  Value<int?> maxAddedSec,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> panelId,
  Value<String> scope,
  Value<int> syncedAtSec,
  Value<int> itemCount,
  Value<int?> maxAddedSec,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$CatalogDb, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtSec => $composableBuilder(
    column: $table.syncedAtSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxAddedSec => $composableBuilder(
    column: $table.maxAddedSec,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$CatalogDb, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get panelId => $composableBuilder(
    column: $table.panelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtSec => $composableBuilder(
    column: $table.syncedAtSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxAddedSec => $composableBuilder(
    column: $table.maxAddedSec,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$CatalogDb, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get panelId =>
      $composableBuilder(column: $table.panelId, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get syncedAtSec => $composableBuilder(
    column: $table.syncedAtSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get itemCount =>
      $composableBuilder(column: $table.itemCount, builder: (column) => column);

  GeneratedColumn<int> get maxAddedSec => $composableBuilder(
    column: $table.maxAddedSec,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$CatalogDb,
          $SyncStateTable,
          SyncRow,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (SyncRow, BaseReferences<_$CatalogDb, $SyncStateTable, SyncRow>),
          SyncRow,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$CatalogDb db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> panelId = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> syncedAtSec = const Value.absent(),
                Value<int> itemCount = const Value.absent(),
                Value<int?> maxAddedSec = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                panelId: panelId,
                scope: scope,
                syncedAtSec: syncedAtSec,
                itemCount: itemCount,
                maxAddedSec: maxAddedSec,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String panelId,
                required String scope,
                required int syncedAtSec,
                Value<int> itemCount = const Value.absent(),
                Value<int?> maxAddedSec = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                panelId: panelId,
                scope: scope,
                syncedAtSec: syncedAtSec,
                itemCount: itemCount,
                maxAddedSec: maxAddedSec,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncRow>(table),
                  BaseReferences<_$CatalogDb, $SyncStateTable, SyncRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDb,
      $SyncStateTable,
      SyncRow,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (SyncRow, BaseReferences<_$CatalogDb, $SyncStateTable, SyncRow>),
      SyncRow,
      PrefetchHooks Function()
    >;

class $CatalogDbManager {
  final _$CatalogDb _db;
  $CatalogDbManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$MoviesTableTableManager get movies =>
      $$MoviesTableTableManager(_db, _db.movies);
  $$SeriesItemsTableTableManager get seriesItems =>
      $$SeriesItemsTableTableManager(_db, _db.seriesItems);
  $$EpisodesTableTableManager get episodes =>
      $$EpisodesTableTableManager(_db, _db.episodes);
  $$EpgTableTableManager get epg => $$EpgTableTableManager(_db, _db.epg);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
