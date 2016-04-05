library ticket_models;

import 'dart:async';
import 'dart:mirrors';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_pool.dart';
import 'package:tickets/shared/schemas.dart';
import 'package:connection_pool/connection_pool.dart';

class MongoModel {

  MongoDbPool _dbPool;

  MongoModel(String _databaseName, String _databaseUrl, int _databasePoolSize) {
    _dbPool = new MongoDbPool(_databaseUrl + _databaseName, _databasePoolSize);
  }

  // Create
  Future<BaseDTO> createByItem(BaseDTO item) {
    // if item already in the db, force an error
    assert(item.id == null);
    item.id = new ObjectId().toString();
    return _dbPool.getConnection().then((ManagedConnection mc) {
      Db db = mc.conn;
      DbCollection collection = db.collection(item.collection_key);
      Map aMap = dtoToMongoMap(item);
      return collection.insert(aMap).then((status) {
        _dbPool.releaseConnection(mc);
        return (status['ok'] == 1) ? item : null;
      });
    });
  }

  // Delete
  Future<Map> deleteByItem(BaseDTO item) async {
    assert(item.id != null);
    return _dbPool.getConnection().then((ManagedConnection mc) {
      Db database = mc.conn;
      DbCollection collection = database.collection(item.collection_key);
      Map aMap = dtoToMap(item);
      return collection.remove(aMap).then((status) {
        _dbPool.releaseConnection(mc);
        return status;
      });
    });
  }

  // Update
  Future<Map> updateItem(BaseDTO item) async {
    assert(item.id != null);
    return _dbPool.getConnection().then((ManagedConnection mc) async {
      Db database = mc.conn;
      DbCollection collection = new DbCollection(database, item.collection_key);
      Map selector = {'_id': item.id};
      Map newItem = dtoToMongoMap(item);
      return collection.update(selector, newItem).then((status) {
        _dbPool.releaseConnection(mc);
        return status;
      });
    });
  }

  // Read helper
  Future<List> _getCollection(String collectionName, [Map query = null]) {
    return _dbPool.getConnection().then((ManagedConnection mc) async {
      DbCollection collection = new DbCollection(mc.conn, collectionName);
      return collection.find(query).toList().then((List<Map> maps) {
        _dbPool.releaseConnection(mc);
        return maps;
      });
    });
  }

  // Another read helper
  Future<List> _getCollectionWhere(String collectionName, fieldName, values) {
    return _dbPool.getConnection().then((ManagedConnection mc) async {
      Db database = mc.conn;
      DbCollection collection = new DbCollection(database, collectionName);
      SelectorBuilder builder = where.oneFrom(fieldName, values);
      return collection.find(builder).toList().then((map) {
        _dbPool.releaseConnection(mc);
        return map;
      });
    });
  }

  // Refresh an item from the database
  Future<BaseDTO> readItemByItem(BaseDTO matcher) async {
    assert(matcher.id != null);
    Map query = {'_id': matcher.id};
    BaseDTO bDto;
    return _getCollection(matcher.collection_key, query).then((items) {
      bDto = mapToDto(getInstance(matcher.runtimeType), items.first);
      return bDto;
    });
  }

  // acquires a collection of documents based on a type, field values
  Future<List> readCollectionByTypeWhere(t, fieldName, values) async {
    List list = new List();
    BaseDTO freshInstance = getInstance(t);
    return _getCollectionWhere(freshInstance.collection_key, fieldName, values).then((items) {
      items.forEach((item) {
        list.add(mapToDto(getInstance(t), item));
      });
      return list;
    });
  }

  // acquires a collection of documents based on type and optional query
  Future<List> readCollectionByType(t, [Map query = null]) {
    List list = new List();
    BaseDTO freshInstance = getInstance(t);
    return _getCollection(freshInstance.collection_key, query).then((items) {
      items.forEach((item) {
        list.add(mapToDto(getInstance(t), item));
      });
      return list;
    });
  }

  // drop the database
  Future<Map> dropDatabase() async {
    Db database = await _dbPool.openNewConnection();
    Map status = await database.drop();
    return status;
  }

  dynamic mapToDto(cleanObject, Map document) {
    var reflection = reflect(cleanObject);
    document['id'] = document['_id'].toString();
    document.remove('_id');
    document.forEach((k,v) {
      reflection.setField(new Symbol(k), v);
    });
    return cleanObject;
  }

  Map dtoToMap(Object object) {
    var reflection = reflect(object);
    Map target = new Map();
    var type = reflection.type;
    while (type != null) {
      type.declarations.values.forEach((item) {
        if(item is VariableMirror) {
          VariableMirror value = item;
          if(!value.isFinal) {
            target[MirrorSystem.getName(value.simpleName)] =
                reflection.getField(value.simpleName).reflectee;
          }
        }
      });
      type = type.superclass;
    }
    return target;
  }

  Map dtoToMongoMap(object) {
    Map item = dtoToMap(object);
    // convert id to contain underscore for private field in mongo
    item['_id'] = item['id'];
    item.remove('id');
    return item;
  }

  dynamic getInstance(Type t) {
    MirrorSystem mirrors = currentMirrorSystem();
    LibraryMirror lm = mirrors.libraries.values.firstWhere(
        (LibraryMirror lm) => lm.qualifiedName == new Symbol('ticket_schemas')
    );
    ClassMirror cm = lm.declarations[new Symbol(t.toString())];
    InstanceMirror im = cm.newInstance(new Symbol(''), []);
    return im.reflectee;
  }
}