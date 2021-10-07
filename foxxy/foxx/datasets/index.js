'use strict';

const db = require('@arangodb').db;
const joi = require('joi');
const _ = require('lodash');
const createAuth = require('@arangodb/foxx/auth');
const auth = createAuth();
const createRouter = require('@arangodb/foxx/router');
const sessionsMiddleware = require('@arangodb/foxx/sessions');
const jwtStorage = require('@arangodb/foxx/sessions/storages/jwt');
const request = require('@arangodb/request');
require('@arangodb/aql/cache').properties({ mode: 'on' });

const router = createRouter();
const _settings = db.settings.firstExample();

const sessions = sessionsMiddleware({
  storage: jwtStorage({ secret: _settings.jwt_secret, ttl: 60 * 60 * 24 * 365 }),
  ttl: 60 * 60 * 24 * 365, // one year in seconds
  transport: 'header'
});

module.context.use(sessions);
module.context.use(router);

var save_activity = function(object_id, action, user_key) {
  db.activities.save({
    date: +new Date(),
    object_id,
    action,
    user_key
  })
}

var typeCast = function (type, value) {
  var value = unescape(value)
  if (type == "integer") value = parseInt(value)
  if (type == "float") value = parseFloat(value)
  if (type == "html") value = JSON.parse(value)
  if (type == "datetime") value = value + ":00.000"

  return value
}

var models = function () {
  return db._query(`
    LET ds = (FOR doc IN datatypes SORT doc.name RETURN ZIP([doc.slug], [doc]))
    RETURN MERGE(ds)
  `).toArray()[0]
}

var list = function (aql, locale) {
  let bindvars = {}
  if (aql.indexOf('@lang') > 0) { bindvars.lang = locale; }

  return db._query(aql, bindvars).toArray()
}

var save_revision = function (uid, object, data, max) {
  db.revisions.save({
    data: data, object_id: object._id, c_at: (+new Date()), user_key: uid
  })
  db._query(`
  LET rev_ids = (
    FOR doc IN revisions FILTER doc.object_id == @id
    SORT doc.c_at LIMIT @max, 100 RETURN doc._key
  )
  FOR id IN rev_ids
  REMOVE { _key: id } IN revisions
  `, { id: object._id, max: max })
}

var build_search = function(object, data, lang) {
  var search_arr = []
  _.each(object.search, function(s) {
    if (_.isString(s)) {
      if (_.isPlainObject(data[s])) {
        search_arr.push(data[s][lang])
      } else {
        search_arr.push(data[s])
      }
    }

    if (_.isPlainObject(s)) {
      var bindVars = { id: doc._id }
      if (s.aql.indexOf("@lang")) bindVars.lang = lang
      var search_item = db._query(s.aql, bindVars).toArray()[0]
      search_arr.push(search_item)
    }
  })

  return search_arr.join(" ").toLowerCase()
}

var build_slug = function(key, object, data, lang) {
  var slug = _.map(object.slug, function(field_name) {
    var value = ""
    if (_.isPlainObject(data[field_name])) {
      value = data[field_name][lang]
    } else {
      value = data[field_name]
    }
    return field_name == '_key' ? key : value
  })

  return _.kebabCase(slug)
}

var fieldsToData = function(fields, body, headers) {
  var data = {}
  _.each(fields, function(f) {
    if (f.tr != true) {
      if (_.isArray(body[f.n])) {
        data[f.n] = _.map(body[f.n], function(v) { return typeCast(f.t,v) })
      } else {
        if (body[f.n] === undefined) {
          if (f.t == "boolean") data[f.n] = false
          else data[f.n] = null
        } else {
          if (f.t == "boolean") data[f.n] = true
          else data[f.n] = typeCast(f.t, body[f.n])
          if(f.t == "password" || f.t == "password_confirmation") {
            if(body[f.n] != "") {
              data.authData = auth.create(body[f.n])
            }
            delete data[f.n]
          }
        }
      }
    } else {
      data[f.n] = {}
      if (_.isArray(body[f.n])) {
        data[f.n][headers['foxx-locale']] = _.map(
          body[f.n], function(v) { return typeCast(f.t,v) }
        )
      } else {
        data[f.n][headers['foxx-locale']] = typeCast(f.t, body[f.n])
      }
    }
  })
  return data
}

// Comment this block if you want to avoid authorization
module.context.use(function (req, res, next) {
  if (!req.session.uid) res.throw('unauthorized')
  res.setHeader("Access-Control-Expose-Headers", "X-Session-Id")
  next();
});

// -----------------------------------------------------------------------------
router.put('/:service/:id/change_folder', function (req, res) {
  const collection = db._collection(req.pathParams.service)
  var document = collection.document(req.pathParams.id)
  collection.update(document, { folder_key: req.body.folder_key })
})
  .header('foxx-locale')
  .header('X-Session-Id')
  .body(joi.object({
    folder_key: joi.string().required()
  }).required())
  .description('Update folder');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/datatypes
router.get('/datatypes', function (req, res) {
  res.send(db._query(`
    FOR doc IN datatypes
    FILTER doc.is_system != true
    SORT doc.name
    RETURN { name: doc.name, slug: doc.slug }
  `))
})
.header('X-Session-Id')
.description('Returns all datatypes');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/page/:page/:perpage
router.get('/:service/page/:page/:perpage', function (req, res) {
  let model = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = model.collection || 'datasets'
  if (!db._collection(collection_name)) { db._createDocumentCollection(collection_name); }

  const locale = req.headers['foxx-locale']
  let order = model.sort || 'SORT doc._key DESC'
  if (model.sortable) order = 'SORT doc.order ASC'

  let includes = ''
  let include_merge = ''
  if (model.includes) {
    includes = model.includes.conditions
    include_merge = model.includes.merges
  }

  let folder = ''
  let folder_params = {}
  if (req.queryParams.folder && req.queryParams.is_root != 'true') {
    folder = 'FILTER doc.folder_key == @folder'
    folder_params = { folder: req.queryParams.folder }
  }

  if (req.queryParams.is_root == 'true') {
    folder = 'FILTER !HAS(doc, "folder_key") || doc.folder_key == @folder'
    folder_params = { folder: req.queryParams.folder }
  }

  var fields = ["_id", "_key"]
  fields.push(_.map(model.columns, function(d) { return d.name }))
  var bindVars = _.merge({
    "datatype": req.pathParams.service,
    "offset": (req.pathParams.page - 1) * parseInt(req.pathParams.perpage),
    "perpage": parseInt(req.pathParams.perpage),
    "fields": _.flatten(fields),
    "@collection": model.collection || 'datasets'
  }, folder_params)

  var aql = `
  LET count = LENGTH((FOR doc IN @@collection FILTER doc.is_system != true AND doc.type == @datatype ${folder} RETURN 1))
  LET data = (
    FOR doc IN @@collection
      FILTER doc.is_system != true AND doc.type == @datatype
      LET image = (FOR u IN uploads FILTER u.object_id == doc._id SORT u.pos LIMIT 1 RETURN u)[0]
      ${folder} ${order} ${includes}
      LIMIT @offset, @perpage

      RETURN MERGE(KEEP(doc, @fields), { image: image ${include_merge} })
  )
  RETURN { count: count, data: data }
  `

  if (aql.indexOf('@lang') > 0) { Object.assign(bindVars, { lang: locale }); }

  var langs = _.map(db.settings.firstExample().langs.split(","), function(l) { return _.trim(l) })

  res.send({
    model: model,
    data: db._query(aql, bindVars).toArray(),
    aql, bindVars, langs
  });
})
.header('X-Session-Id')
.description('Returns all objects');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/:service_key/:sub/page/:page/:perpage
router.get('/:service/:service_key/:sub/page/:page/:perpage', function (req, res) {
  let model = JSON.parse(
    models()[req.pathParams.service].javascript
  ).sub_models[req.pathParams.sub]
  const locale = req.headers['foxx-locale']
  let order = model.sort || 'SORT doc._key DESC'
  if (model.sortable) order = 'SORT doc.order ASC'

  let includes = ''
  let include_merge = ''
  if (model.includes) {
    includes = model.includes.conditions
    include_merge = model.includes.merges
  }

  var bindVars = {
    "datatype": req.pathParams.sub,
    "parent": req.pathParams.service_key,
    "offset": (req.pathParams.page - 1) * parseInt(req.pathParams.perpage),
    "perpage": parseInt(req.pathParams.perpage),
    "@collection": model.collection || 'datasets'
  }

  var aql = `
  LET count = LENGTH((FOR doc IN @@collection FILTER doc.type == @datatype RETURN 1))
  LET data = (
    FOR doc IN @@collection
      FILTER doc.parent_id == @parent
      FILTER doc.type == @datatype
      LET image = (FOR u IN uploads FILTER u.object_id == doc._id SORT u.pos LIMIT 1 RETURN u)[0]
      ${order} ${includes}
      LIMIT @offset, @perpage
      RETURN MERGE(doc, { image: image ${include_merge} })
  )
  RETURN { count: count, data: data }
  `
  if (aql.indexOf('@lang') > 0) { Object.assign(bindVars, { lang: locale }); }

  res.send({ model: model, data: db._query(aql, bindVars).toArray() });
})
.header('X-Session-Id')
.description('Returns all objects');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/search/:term
router.get('/:service/search/:term', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  var locale = req.headers['foxx-locale']
  if (locale.match(/[a-z]+/) == null) locale = 'en'
  let order = object.sort || 'SORT doc._key DESC'
  if (object.sortable) order = 'SORT doc.order ASC'

  let includes = ''
  let include_merge = ''
  if (object.includes) {
    includes = object.includes.conditions
    include_merge = object.includes.merges
  }

  if (locale.match(/[a-z]+/) == null) locale = 'en'

  var bindVars = {
    "type": req.pathParams.service,
    "term": req.pathParams.term,
    "@collection": object.view_collection || 'viewDatasets'
  }

  var aql = `
  FOR doc IN @@collection
  SEARCH PHRASE(doc['search'][@lang], @term, CONCAT("text_", @lang))
  FILTER doc.type == @type
  LET image = (FOR u IN uploads FILTER u.object_id == doc._id SORT u.pos LIMIT 1 RETURN u)[0]
  ${order} ${includes}
  LIMIT 100
  RETURN MERGE(doc, { image: image ${include_merge} })
  `

  if (aql.indexOf('@lang') > 0) { Object.assign(bindVars, { lang: locale }) }

  res.send({ data: db._query(aql, bindVars).toArray() })
})
.header('foxx-locale')
.header('X-Session-Id')
.description('Returns First 100 found objects');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/:id
router.get('/:service/:id', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  var folders = db._query(`
    LET r = (FOR f IN folders FILTER f.object_type == @type AND f.is_root == true RETURN { _key: f._key, _id: f._id, name: f.name })[0]
    FOR f IN folders FILTER f.is_root != true SORT f.name
        LET path = (
            FOR v IN ANY SHORTEST_PATH r._id TO f._id GRAPH "folderGraph"
            RETURN { _key: v._key, name: v.name }
        )
        FILTER LENGTH(path) > 0
        RETURN { folder: f, path, root: r }
  `, { type: req.pathParams.service }).toArray()

  const collection = db._collection(object.collection || 'datasets')
  let fields = object.model
  _.each(fields, function (field, i) { if (field.d && !_.isArray(field.d)) { fields[i].d = list(field.d, req.headers['foxx-locale']) } })

  let model = JSON.parse(models()[req.pathParams.service].javascript)
  let sub_models = model.sub_models
  _.each(sub_models, function (_sub_model, sub_mobel_key) {
    _.each(sub_models[sub_mobel_key].fields, function (field, i) {
      if (field.d && !_.isArray(field.d)) {
        model.sub_models[sub_mobel_key].fields[i].d = list(field.d, req.headers['foxx-locale'])
      }
    })
  })

  res.send({
    fields: fields, folders, model, data: collection.document(req.pathParams.id)
  });
})
.header('X-Session-Id')
.header('foxx-locale')
.description('Returns object within ID');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/sub/:sub_service/:id
router.get('/:service/sub/:sub_service/:id', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  let sub_object = object.sub_models[req.pathParams.sub_service]
  const collection = db._collection(sub_object.collection || 'datasets')
  _.each(sub_object.fields, function (field, i) { if (field.d && !_.isArray(field.d)) { sub_object.fields[i].d = list(field.d, req.headers['foxx-locale']) } })
  res.send({
    fields: sub_object.fields,
    model: JSON.parse(models()[req.pathParams.service].javascript),
    data: collection.document(req.pathParams.id)
  });
})
.header('X-Session-Id')
.description('Returns sub object within ID');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/fields
router.get('/:service/fields', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  let fields = object.model
  _.each(fields, function (field, i) {
    if (field.d && !_.isArray(field.d)) { fields[i].d = list(field.d, req.headers['foxx-locale']) }
  })
  res.send({ fields: fields, object });
})
.header('X-Session-Id')
.header('foxx-locale')
.description('Get all fields to build form');

////////////////////////////////////////////////////////////////////////////////
// POST /datasets/:service
router.post('/:service', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'
  const collection = db._collection(collection_name)

  object.revisions = object.revisions || 10
  let fields = object.model
  const body = JSON.parse(req.body.toString())
  var obj = null
  var errors = []
  if (!_.isArray(fields)) fields = fields.model

  try {
    var schema = {}
    if (object.act_as_tree) schema.folder_key = joi.string().required()
    _.each(fields, function (f) {
      schema[f.n] = _.isString(f.j) ? schema[f.n] = eval(f.j) : schema[f.n] = f.j
    })
    errors = joi.validate(body, schema, { abortEarly: false }).error.details
  }
  catch (e) { }

  if (errors.length == 0) {
    var data = fieldsToData(fields, body, req.headers)
    data.type = req.pathParams.service

    if (data.html && data.html.html) {
      data['html_text'] = data.html.html.replace(/(<([^>]+)>)/gi, "")
    }

    if (object.act_as_tree) data['folder_key'] = body.folder_key

    if (object.search) {
      data.search = {}
      data.search[req.headers['foxx-locale']] = build_search(object, data, req.headers['foxx-locale'])
    }

    if (object.timestamps === true) { data.created_at = +new Date() }

    var filter_by_folder = ''
    var folder_params = {}

    if (object.act_as_tree) {
      filter_by_folder = 'FILTER doc.folder_key == @folder'
      folder_params.folder = body.folder_key
    }

    data.order = db._query(`
      LET docs = (FOR doc IN @@collection FILTER doc.type == @type ${filter_by_folder} RETURN 1)
      RETURN LENGTH(docs)
    `, _.merge({ type: req.pathParams.service, '@collection': collection_name }, folder_params)
    ).toArray()[0]
    obj = collection.save(data, { waitForSync: true })

    let obj_update = {}
    if (object.slug) {
      var slug = build_slug(obj._key, object, data, req.headers['foxx-locale'])

      if(data.slug == '' || data.slug == undefined ) {
        obj_update.slug = slug
      }
    }

    collection.update(obj, obj_update)

    save_revision(req.session.uid, obj, data, object.revisions)
    save_activity(obj._id, 'created', req.session.uid)
  }
  res.send({ success: errors.length == 0, data: obj, errors: errors });
}).header('foxx-locale')
.header('X-Session-Id')
.description('Create a new object.');

////////////////////////////////////////////////////////////////////////////////
// POST /datasets/:service/:service_key/:sub
router.post('/:service/:service_key/:sub', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  let sub_object = object.sub_models[req.pathParams.sub]
  const collection = db._collection(sub_object.collection || 'datasets')

  object.revisions = object.revisions || 10
  const body = JSON.parse(req.body.toString())
  var obj = null
  var errors = []
  let fields = sub_object.fields
  try {
    var schema = {}
    _.each(fields, function (f) {
      let validate = f.ju ? f.ju : f.j
      schema[f.n] = _.isString(validate) ? eval(validate) : validate
    })
    errors = joi.validate(body, schema, { abortEarly: false }).error.details
  }
  catch(e) {}
  if (errors.length == 0) {
    var data = fieldsToData(fields, body, req.headers)
    data.type = req.pathParams.sub
    if (object.search) {
      var search_arr = []
      _.each(object.search, function(s) {
        if (_.isPlainObject(data[s])) {
          search_arr.push(data[s][req.headers['foxx-locale']])
        } else {
          search_arr.push(data[s])
        }
      })
      data.search = {}
      data.search[req.headers['foxx-locale']] = search_arr.join(" ").toLowerCase()
    }
    if (object.timestamps === true) { data.created_at = +new Date() }

    data.order = db._query(
      'LET docs = (FOR doc IN @@collection FILTER doc.type == @type RETURN 1) RETURN LENGTH(docs)',
      { type: req.pathParams.sub, "@collection": object.collection || 'datasets' }
    ).toArray()[0]
    data.parent_id = req.pathParams.service_key
    obj = collection.save(data, { waitForSync: true })
    if (object.slug) {
      var slug = build_slug(obj._key, object, data, req.headers['foxx-locale'])

      if(data.slug == '' || data.slug == undefined) {
        collection.update(obj, { slug: slug })
      }
    }
    save_revision(req.session.uid, obj, data, object.revisions)
    save_activity(object._id, 'created', req.session.uid)
  }
  res.send({ success: errors.length == 0, data: obj, errors: errors });
}).header('foxx-locale')
.header('X-Session-Id')
  .description('Create a new object.');

////////////////////////////////////////////////////////////////////////////////
// POST /datasets/:service/:id
router.post('/:service/:id', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection = db._collection(object.collection || 'datasets')

  object.revisions = object.revisions || 10
  let fields = object.model
  const body = JSON.parse(req.body.toString())
  var obj = null
  var errors = []

  if (!_.isArray(fields)) fields = fields.model

  try {
    var schema = {}
    _.each(fields, function (f) {
      let validate = f.ju ? f.ju : f.j
      if(validate)
        schema[f.n] = _.isString(validate) ? eval(validate) : validate
    })
    var validation = joi.validate(body, schema, { abortEarly: false })
    if(validation.error) errors = validation.error.details
  }
  catch(e) { console.log("err", e) }

  if (errors.length == 0) {
    var doc = collection.document(req.pathParams.id)
    var data = fieldsToData(fields, body, req.headers)

    if (object.search) {
      data.search = {}
      data.search[req.headers['foxx-locale']] = data.search[req.headers['foxx-locale']] = build_search(object, data, req.headers['foxx-locale'])
    }

    if (object.timestamps === true) { data.updated_at = +new Date() }

    if (object.slug) {
      var slug = build_slug(doc._key, object, data, req.headers['foxx-locale'])

      if (data.slug == '' || data.slug == undefined) data.slug = slug
    }

    if(req.pathParams.service == "components" && data.kind == "riot4") {
      // Compile widget to javascript using riotjs/cli
      const url = JSON.parse(db.settings.firstExample({}).home).base_url
      var response = request.post(url + "/riotjs", {
        form: { token: _settings.secret, name: data.slug, tag: data.html, id: req.pathParams.id }
      })
      data.javascript = response.body
    }

    if(req.pathParams.service == "layouts") {
      if(doc.scss.indexOf("@tailwind") >= 0) {
        const url = JSON.parse(db.settings.firstExample({}).home).base_url
        var response = request.post(url + "/tailwindcss", {
          form: { token: _settings.secret, id: req.pathParams.id, field: "scss" }
        })
        data.compiled_css = response.body
      }
    }

    if (doc.html && doc.html.html) {
      data['html_text'] = data.html.html.replace(/(<([^>]+)>)/gi, "")
    }

    obj = collection.update(doc, data)
    save_revision(req.session.uid, doc, data, object.revisions)
    save_activity(doc._id, 'updated', req.session.uid)
  }
  res.send({ success: errors.length == 0, data: obj, errors: errors });
})
.header('foxx-locale')
.header('X-Session-Id')
.description('Update an object.');

////////////////////////////////////////////////////////////////////////////////
// POST /datasets/sub/:service/:sub_service/:id
router.post('/sub/:service/:sub_service/:id', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  let sub_object = object.sub_models[req.pathParams.sub_service]
  const collection = db._collection(sub_object.collection || 'datasets')

  object.revisions = object.revisions || 10
  let fields = sub_object.fields
  const body = JSON.parse(req.body.toString())
  var obj = null
  var errors = []
  try {
    var schema = {}
    _.each(fields, function (f) {
      if (f.ju) {
        schema[f.n] = _.isString(f.ju) ? eval(f.ju) : f.ju
      } else {
        schema[f.n] = _.isString(f.j) ? eval(f.j) : f.j
      }
    })
    errors = joi.validate(body, schema, { abortEarly: false }).error.details
  }
  catch(e) {}
  if (errors.length == 0) {
    var doc = collection.document(req.pathParams.id)
    var data = fieldsToData(fields, body, req.headers)
    if (object.search) {
      data.search = {}
      var search_arr = []
      _.each(object.search, function(s) {
        if (_.isPlainObject(data[s])) {
          search_arr.push(data[s][req.headers['foxx-locale']])
        } else {
          search_arr.push(data[s])
        }
      })
      data.search[req.headers['foxx-locale']] = search_arr.join(" ")
    }
    if (object.timestamps === true) { data.updated_at = +new Date() }
    if (object.slug) {
      data['slug'] = build_slug(doc._key, object, data, req.headers['foxx-locale'])
    }
    obj = collection.update(doc, data)
    save_revision(req.session.uid, doc, data, object.revisions)
    save_activity(doc._id, 'updated', req.session.uid)
  }
  res.send({ success: errors.length == 0, data: obj, errors: errors });
})
.header('foxx-locale')
.header('X-Session-Id')
.description('Update an object.');

////////////////////////////////////////////////////////////////////////////////
// PATCH /datasets/:service/:id/:field/field
router.patch('/:service/:id/:field/:lang/field', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection = db._collection(object.collection || 'datasets')

  var item = collection.document(req.pathParams.id)
  let column = _.first(_.filter(object.columns, function(el) { return el.name == req.pathParams.field}))
  if (item) {

    item[req.pathParams.field][req.pathParams.lang] = req.body.value
    collection.update(item, item)

    res.send({ success: true })
  } else {
    res.send({ success: false })
  }
})
.body(joi.object({
  value: joi.any().required()
}))
.header('foxx-locale')
.header('X-Session-Id')
.description('Update a field.');

////////////////////////////////////////////////////////////////////////////////
// PATCH /datasets/:service/:id/:field/toggle
router.patch('/:service/:id/:field/toggle', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection = db._collection(object.collection || 'datasets')

  var item = collection.document(req.pathParams.id)
  let column = _.first(_.filter(object.columns, function(el) { return el.name == req.pathParams.field}))
  if (item) {
    var data = {}
    data[req.pathParams.field] = !item[req.pathParams.field]
    collection.update(item, data)
    var returned_data = !item[req.pathParams.field]
    if (column && column.values) returned_data = column.values[!item[req.pathParams.field]]
    res.send({ success: true, data: returned_data })
  } else {
    res.send({ success: false })
  }
})
.header('foxx-locale')
.header('X-Session-Id')
.description('Toggle boolean field.');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/:id/duplicate
router.get('/:service/:id/duplicate', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'

  var new_obj = db._query(`
    FOR doc IN @@collection
    FILTER doc._key == @key
    INSERT UNSET( doc, "_id", "_key", "_rev" ) IN @@collection RETURN NEW
  `, { key: req.pathParams.id, '@collection': collection_name }).toArray()[0]
  res.send(new_obj);
})
.header('X-Session-Id')
.description('duplicate an object.');

////////////////////////////////////////////////////////////////////////////////
// POST /datasets/:id/publish
router.post('/:id/publish', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'
  const collection = db._collection(collection_name)

  var dataset = collection.document(req.pathParams.id)
  db.publications.save({ _key: collection_name + '_' + dataset._key, data: dataset }, { overwrite: true })
  db._query(`
    FOR dataset IN @@collection FILTER dataset.parent_id == @key
    UPSERT { _id: @id }
      INSERT { data: dataset }
      UPDATE { data: dataset }
    IN publications
    RETURN dataset._key
  `, { key: req.pathParams.id, id: 'publications/' + req.pathParams.id, '@collection': collection_name })
  res.send({ success: true });
})
.header('X-Session-Id')
.description('publish a dataset.');

////////////////////////////////////////////////////////////////////////////////
// DELETE /datasets/:service/:id
router.delete('/:service/:id', function (req, res) {
  console.log("delete")
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'
  const collection = db._collection(collection_name)
  collection.remove(req.pathParams.id)
  db.revisions.removeByExample({ object_id: collection_name + '/' + req.pathParams.id })
  res.send({success: true });
})
.header('X-Session-Id')
.description('delete an object.');

////////////////////////////////////////////////////////////////////////////////
// DELETE /datasets/:service/:id
router.delete('/:service/:sub_service/:id', function (req, res) {
  console.log("delete sub route")
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  let sub_object = object.sub_models[req.pathParams.sub_service]
  const collection = db._collection(sub_object.collection || 'datasets')

  collection.remove(req.pathParams.id)

  db.revisions.removeByExample({ object_id: req.pathParams.sub_service + '/' + req.pathParams.id })
  res.send({success: true });
})
.header('X-Session-Id')
.description('delete a sub object.');


////////////////////////////////////////////////////////////////////////////////
// PUT /datasets/:service/orders/:from/:to
router.put('/:service/orders/:from/:to', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'
  const collection = db._collection(collection_name)
  const from = parseInt(req.pathParams.from)
  const to = parseInt(req.pathParams.to)

  var filter_by_folder = ''
  var folder_params = {}

  if (req.queryParams.folder_key) {
    filter_by_folder = 'FILTER doc.folder_key == @folder'
    folder_params.folder = req.queryParams.folder_key
  }

  var doc = db._query(
    `FOR doc IN @@collection FILTER doc.type == @type ${filter_by_folder} SORT doc.order ASC LIMIT @pos, 1 RETURN doc`,
    _.merge({ "type": req.pathParams.service, pos: parseInt(req.pathParams.from), "@collection": collection_name }, folder_params)
  ).toArray()[0]

  if (from < to) {
    db._query(
      `FOR doc IN @@collection
        ${filter_by_folder}
        FILTER doc.type == @type AND doc.order <= @to AND doc.order >= @from and doc._key != @key
          UPDATE({ _key: doc._key, order: doc.order - 1 }) IN @@collection`,
      _.merge({ "type": req.pathParams.service, from, to, key: doc._key, "@collection": collection_name }, folder_params)
    )
  } else {
    db._query(
      `FOR doc IN @@collection
        ${filter_by_folder}
        FILTER doc.type == @type AND doc.order <= @from and doc.order >= @to and doc._key != @key
        UPDATE({ _key: doc._key, order: doc.order + 1 }) IN @@collection`,
      _.merge({ "type": req.pathParams.service, from, to, key: doc._key, "@collection": collection_name }, folder_params)
    )
  }

  collection.update(doc._key, { order: to })

  let docs = db._query(
    `FOR doc IN @@collection
      ${filter_by_folder}
      FILTER doc.type == @type SORT doc.order RETURN doc`, _.merge({
        type: req.pathParams.service,
        "@collection": collection_name
      }, folder_params)).toArray()

  let i = 0;
  _.each(docs, function(doc) {
    collection.update(doc._key, { order: i });
    i++;
  })

  res.send({ success: true });
})
  .header('foxx-locale')
  .header('X-Session-Id')
  .description('Swap 2 items');

////////////////////////////////////////////////////////////////////////////////
// PUT /datasets/:service/orders/:from/:to
router.put('/:service/:sub_service/orders/:from/:to', function (req, res) {
  const collection_name = 'datasets'
  const collection = db._collection(collection_name)
  const from = parseInt(req.pathParams.from)
  const to = parseInt(req.pathParams.to)
  const folder_params = {}
  var doc = db._query(
    `FOR doc IN @@collection FILTER doc.type == @type SORT doc.order ASC LIMIT @pos, 1 RETURN doc`,
    _.merge({ "type": req.pathParams.sub_service, pos: parseInt(req.pathParams.from), "@collection": collection_name }, folder_params)
  ).toArray()[0]

  if (from < to) {
    db._query(
      `FOR doc IN @@collection
        FILTER doc.type == @type AND doc.order <= @to AND doc.order >= @from and doc._key != @key
          UPDATE({ _key: doc._key, order: doc.order - 1 }) IN @@collection`,
      _.merge({ "type": req.pathParams.sub_service, from, to, key: doc._key, "@collection": collection_name }, folder_params)
    )
  } else {
    db._query(
      `FOR doc IN @@collection
        FILTER doc.type == @type AND doc.order <= @from and doc.order >= @to and doc._key != @key
        UPDATE({ _key: doc._key, order: doc.order + 1 }) IN @@collection`,
      _.merge({ "type": req.pathParams.sub_service, from, to, key: doc._key, "@collection": collection_name }, folder_params)
    )
  }

  collection.update(doc._key, { order: to })

  let docs = db._query(
    `FOR doc IN @@collection
      FILTER doc.type == @type SORT doc.order RETURN doc`, _.merge({
        type: req.pathParams.sub_service,
        "@collection": collection_name
      }, folder_params)).toArray()

  let i = 0;
  _.each(docs, function(doc) {
    collection.update(doc._key, { order: i });
    i++;
  })

  res.send({ success: true });
})
  .header('foxx-locale')
  .header('X-Session-Id')
  .description('Sub Items : Swap 2 items');

////////////////////////////////////////////////////////////////////////////////
// GET /datasets/:service/stats/:tag
router.get('/:service/stats/:tag', function (req, res) {
  let object = JSON.parse(models()[req.pathParams.service].javascript)
  const collection_name = object.collection || 'datasets'

  var results = db._query(`
    FOR d IN @@collection
    FILTER d.type == @service
      FILTER d[@tag] != NULL
      FOR t IN d[@tag]
          COLLECT tag = t WITH COUNT into size
          FILTER tag != NULL
          SORT size DESC
          RETURN { tag, size }
  `, { tag: req.pathParams.tag, service: req.pathParams.service, "@collection": collection_name })

  res.send(results);
})
  .header('foxx-locale')
  .header('X-Session-Id')
  .description('Get tag statistic usages');

  module.context.use('/folders', require('./routes/folders.js'), 'folders');