<datatype_folders>
  <div>
    <ul class="uk-breadcrumb">
      <li each={ f in path }><a href="#datatypes/{f._key}">{ f.name }</a></li>
      <li>
        <a if={ path.length > 1 } onclick={renameFolder}><i class="far fa-edit"></i></a>
        <a onclick={addFolder}><i class="fas fa-plus"></i></a>
        <a if={ path.length > 1 && folders.length == 0 } onclick={deleteFolder}><i class="fas fa-trash"></i></a>
      </li>
    </ul>
    <ul class="uk-list">
      <li each={f in folders}><a href="#datatypes/{f._key}"><i class="far fa-folder" /> {f.name}</a></li>
    </ul>
  </div>
  <script>
    this.folders = []
    this.folder = {}
    this.path = [ this.folder ]
    this.folder_key = this.opts.folder_key || '';
    var self = this

    var loadFolder = function(folder_key) {
      common.get(url + '/cruds/folders/datatypes/' + folder_key, function(d) {
        self.folders = d.folders
        self.path = d.path
        self.folder = _.last(self.path)
        self.parent.setFolder(self.folder)
        self.update()
      })
    }

    addFolder(e) {
      var name = prompt("Folder's name");
      common.post(url + "/cruds/folders/datatypes", JSON.stringify({ name: name, parent_id: self.folder._key }), function(d) {
        loadFolder(self.folder._key)
      })
    }

    renameFolder(e) {
      var name = prompt("Update Folder's name");
      common.patch(url + "/cruds/folders/datatypes", JSON.stringify({ name: name, id: self.folder._key }), function(d) {
        self.path = d.path
        self.update()
      })
    }

    deleteFolder(e) {
      UIkit.modal.confirm('Are you sure? This action will destroy the folder and it\'s content')
        .then(function() {
          var parent = _.last(_.initial(self.path));
          common.delete(url + "/cruds/folders/datatypes/" + self.folder._key, function(d) {
            common.get(url + "/cruds/folders/datatypes/" + parent._key, function(d) {
              self.folders = d.folders
              self.path = d.path
              loadFolder(parent._key)
              self.update()
            })
          })
      }, function () {
        console.log('Rejected.')
      });
    }

    loadFolder(this.folder_key)
  </script>
</datatype_folders>

<datatype_crud_index>
  <a href="#" class="uk-button uk-button-small uk-button-default" onclick={ new_item }>
    <i class="fas fa-plus"></i> New { opts.singular }
  </a>

  <table class="uk-table uk-table-striped" if={data.length > 0}>
    <thead>
      <tr>
        <th each={ col in cols }>
          {col.name == undefined ? col : col.label === undefined ? col.name : col.label}
        </th>
        <th width="70"></th>
      </tr>
    </thead>
    <tbody>
      <tr each={ row in data } >
        <td each={ col in cols } class="{col.class}">
          <virtual if={ col.tr == true }>{_.get(row,col.name)[locale]}</virtual>
          <virtual if={ col.tr != true }>{_.get(row,col.name)}</virtual>
        </td>
        <td class="uk-text-center" width="110">
          <a onclick={edit} class="uk-button uk-button-primary uk-button-small"><i class="fas fa-edit"></i></a>
          <a onclick={ destroy_object } class="uk-button uk-button-danger uk-button-small" ><i class="fas fa-trash-alt"></i></a>
        </td>
      </tr>
    </tbody>

  </table>

  <ul class="uk-pagination">
    <li if={ datatype > 0 } ><a onclick={ previouspage }><span class="uk-margin-small-right" uk-pagination-previous></span> Previous</a></li>
    <li if={ (datatype + 1) * perpage < count} class="uk-margin-auto-left"><a onclick={ nextpage }>Next <span class="uk-margin-small-left" uk-pagination-next></span></a></li>
  </ul>

  <script>
    var self = this
    this.data = []
    new_item(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "datatype_crud_new", opts)
    }

    this.loaddatatype = function(datatypeIndex) {
      common.get(url + "/cruds/sub/"+opts.parent_id+"/"+opts.id+"/"+opts.key+"/datatype/"+datatypeIndex+"/"+per_page, function(d) {
        self.data = d.data[0].data
        self.cols = _.map(common.array_diff(common.keys(self.data[0]), ["_id", "_key", "_rev"]), function(v) { return { name: v }})
        if(opts.columns) self.cols = opts.columns
        self.count = d.data[0].count
        self.update()
      })
    }
    this.loaddatatype(1)

    edit(e) {
      e.preventDefault()
      opts.element_id = e.item.row._key
      riot.mount("#"+opts.id, "datatype_crud_edit", opts)
    }

    nextpage(e) {
      e.preventDefault()
      self.datatype += 1
      self.loaddatatype(self.datatype + 1)
    }

    previouspage(e) {
      e.preventDefault()
      self.datatype -= 1
      self.loaddatatype(self.datatype + 1)
    }

    destroy_object(e) {
      e.preventDefault()
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.delete(url + "/cruds/" + opts.id + "/" + e.item.row._key, function() {
          self.loaddatatype(1)
        })
      }, function() {})
    }
  </script>
</datatype_crud_index>

<datatype_crud_edit>
  <a href="#" class="uk-button uk-button-link" onclick={ goback }>Back to { opts.id }</a>
  <form onsubmit="{ save_form }" class="uk-form" id="{opts.id}_crud_datatype">
  </form>

  <script>
    goback(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "datatype_crud_index", opts)
    }

    save_form(e) {
      e.preventDefault()
      common.saveForm(opts.id+'_crud_datatype', "cruds/sub/"+opts.parent_name+"/"+ opts.id+"/"+opts.element_id, "", opts)
    }

    var self = this;
    common.get(url + "/cruds/" + opts.id + "/" + opts.element_id, function(d) {
      self.datatype = d.data

      common.buildForm(self.datatype, opts.fields, '#'+opts.id+'_crud_datatype')
    })
    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
  </script>
</datatype_crud_edit>

<datatype_crud_new>
  <a href="#" class="uk-button uk-button-link" onclick={ goback }>Back to { opts.id }</a>
  <form onsubmit="{ save_form }" class="uk-form" id="{opts.id}_crud_datatype">
  </form>

  <script>
    var self = this
    this.crud = {}
    this.crud[opts.key] = opts.parent_id

    goback(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "datatype_crud_index", opts)
    }

    this.on('mount', function() {
      common.buildForm(self.crud, opts.fields, '#'+opts.id+'_crud_datatype')
    })

    save_form(e) {
      e.preventDefault()
      common.saveForm(opts.id+'_crud_datatype', "cruds/sub/datatypes/"+ opts.id, "", opts)
    }


  </script>
</datatype_crud_new>

<datatype_edit>
  <virtual if={can_access}>
    <ul uk-tab>
      <li><a href="#">datatypes</a></li>
      <li each={ i, k in sub_models }><a href="#">{ k }</a></li>
    </ul>

    <ul class="uk-switcher uk-margin">
      <li>
        <h3>Editing datatype</h3>
        <form onsubmit="{ save_form }" class="uk-form" id="form_datatype">
        </form>
        <a class="uk-button uk-button-primary" onclick="{ publish }">Publish</a>
        <a class="uk-button uk-button-secondary" onclick="{ duplicate }">Duplicate</a>
      </li>
      <li each={ i, k in sub_models }>
        <div id={ k } class="crud"></div>
      </li>
    </ul>
  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this datatype...
  </virtual>

  <script>
    var self = this
    self.can_access = false
    self.loaded = false

    save_form(e) {
      e.preventDefault()
      common.saveForm("form_datatype", "cruds/datatypes",opts.datatype_id)
    }

    duplicate(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.get(url + "/cruds/datatypes/" + opts.datatype_id + "/duplicate", function(data) {
          route('/datatypes/' + data._key + '/edit')
          UIkit.notification({
            message : 'Successfully duplicated!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
        })
      }, function() {})
    }

    publish(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.post(url + "/cruds/datatypes/" + opts.datatype_id + "/publish", JSON.stringify({}), function(data) {
          UIkit.notification({
            message : 'Successfully published!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
        })
      })
    }

    common.get(url + "/cruds/datatypes/" + opts.datatype_id, function(d) {
      self.datatype = d.data
      self.fields = d.fields
      self.sub_models = d.fields.sub_models
      var fields = d.fields
      var act_as_tree = d.fields.act_as_tree

      if(!_.isArray(fields)) fields = fields.model
      common.get(url + "/auth/whoami", function(me) {
        self.can_access = d.fields.roles === undefined || _.includes(d.fields.roles.write, me.role)
        self.loaded = true
        self.update()
        var back_url = 'datatypes'
        if(act_as_tree) { back_url = 'datatypes/' + self.datatype.folder_key }
        if(self.can_access)
          common.buildForm(self.datatype, fields, '#form_datatype', back_url, function() {
            $(".crud").each(function(i, c) {
            var id = $(c).attr("id")
            riot.mount("#" + id, "datatype_crud_index", { model: id,
              fields: self.sub_models[id].fields,
              key: self.sub_models[id].key,
              singular: self.sub_models[id].singular,
              columns: self.sub_models[id].columns,
              parent_id: opts.datatype_id,
              parent_name: back_url })
          })
        })
      })
    })

    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
</datatype_edit>

<datatype_new>
  <virtual if={can_access}>
    <h3>Creating datatype</h3>
    <form onsubmit="{ save_form }" class="uk-form" id="form_new_datatype">
    </form>
  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this datatype...
  </virtual>
  <script>
    var self = this
    self.can_access = false
    self.loaded = false

    save_form(e) {
      e.preventDefault()
      common.saveForm("form_new_datatype", "cruds/datatypes")
    }

    common.get(url + "/cruds/datatypes/fields", function(d) {
      common.get(url + "/auth/whoami", function(me) {
        self.can_access = d.fields.roles === undefined || _.includes(d.fields.roles.write, me.role)
        self.loaded = true
        self.update()
        if(self.can_access) {
          // Ignore sub models if any
          var fields = d.fields
          var obj = {}
          if(!_.isArray(fields)) fields = fields.model
          var back_url = 'datatypes'
          if(self.opts.folder_key) {
            fields.push({ r: true, c: "1-1", n: "folder_key", t: "hidden" })
            obj['folder_key'] = opts.folder_key
            back_url = 'datatypes/' + opts.folder_key
          }
          common.buildForm(obj, fields, '#form_new_datatype', back_url);
        }
      })
    })

    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
  </script>
</datatype_new>

<datatypes>
  <datatype_folders show={loaded} folder_key={folder_key} />
  <virtual if={can_access}>
    <div class="uk-float-right">
      <a if={act_as_tree} href="#datatypes/{folder._key}/new" class="uk-button uk-button-small uk-button-default"><i class="fas fa-plus"></i> New datatype</a>
      <a if={!act_as_tree} href="#datatypes/new" class="uk-button uk-button-small uk-button-default"><i class="fas fa-plus"></i> New datatype</a>
      <a if={ export } onclick="{ export_data }" class="uk-button uk-button-small uk-button-primary"><i class="fas fa-file-export"></i> Export CSV</a>
    </div>

    <h3>Listing datatypes</h3>

    <form onsubmit={filter} class="uk-margin-top">
      <div class="uk-inline uk-width-1-1">
        <span class="uk-form-icon" uk-icon="icon: search"></span>
        <input type="text" ref="term" id="term" class="uk-input" autocomplete="off">
      </div>
    </form>
    <table class="uk-table uk-table-striped">
      <thead>
        <tr>
          <th if={sortable} width="20"></th>
          <th each={ col in cols }>{col.name == undefined ? col : col.label === undefined ? col.name : col.label}</th>
          <th width="70"></th>
        </tr>
      </thead>
      <tbody id="list">
        <tr each={ row in data } >
          <td if={sortable}><i class="fas fa-grip-vertical handle"></i></td>
          <td each={ col in cols } class="{col.class}">
            <virtual if={ col.toggle == true } >
              <virtual if={ col.tr == true }><a onclick={toggleField} data-key="{row._key}">{col.values ? col.values[row[col.name][locale]] : _.get(row,col.name)[locale]}</a></virtual>
              <virtual if={ col.tr != true }><a onclick={toggleField} data-key="{row._key}">{col.values ? col.values[row[col.name]] : _.get(row,col.name) }</a></virtual>
            </virtual>

            <virtual if={ col.toggle != true } >
              <virtual if={ col.type == "image" }>
                <img src="{_.get(row,col.name)[locale]} " style="height:25px">
              </virtual>
              <virtual if={ col.type != "image" }>
                { calc_value(row, col, locale) }
              </virtual>
            </virtual>
          </td>
          <td class="uk-text-center" width="110">
            <a onclick={edit} class="uk-button uk-button-primary uk-button-small"><i class="fas fa-edit"></i></a>
            <a onclick={ destroy_object } class="uk-button uk-button-danger uk-button-small" ><i class="fas fa-trash-alt"></i></a>
          </td>
        </tr>
      </tbody>
    </table>
    <ul class="uk-pagination">
      <li if={ datatype > 0 } ><a onclick={ previouspage }><span class="uk-margin-small-right" uk-pagination-previous></span> Previous</a></li>
      <li if={ (datatype + 1) * perpage < count} class="uk-margin-auto-left"><a onclick={ nextpage }>Next <span class="uk-margin-small-left" uk-pagination-next></span></a></li>
    </ul>
    Per datatype : {perpage > 100000 ? 'ALL' : perpage}
    <a onclick={ setperpage } class="uk-label">25</a>
    <a onclick={ setperpage } class="uk-label">50</a>
    <a onclick={ setperpage } class="uk-label">100</a>
    <a onclick={ setperpage } class="uk-label">500</a>
    <a onclick={ setperpage } class="uk-label">1000</a>
    <a onclick={ setperpage } class="uk-label">ALL</a>
  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this datatype...
  </virtual>
  <style>
    .handle { cursor: move; }
  </style>
  <script>

    var self        = this
    this.datatype    = 0
    this.perpage    = per_page
    this.locale     = window.localStorage.getItem('foxx-locale')
    this.data       = []
    this.export     = false
    this.can_access = false
    this.sortable   = false
    this.loaded     = false
    this.folder     = {}
    this.folder_key = this.opts.folder_key || ''
    this.act_as_tree = true

    this.loaddatatype = function(datatypeIndex) {
      self.loaded = false
      var querystring = "?folder=" + self.folder._key + "&is_root=" + self.folder.is_root
      common.get(url + "/cruds/datatypes/page/"+datatypeIndex+"/"+this.perpage + querystring, function(d) {
        self.data = d.data[0].data
        self.export = !!d.model.export
        self.cols = _.map(common.array_diff(common.keys(self.data[0]), ["_id", "_key", "_rev"]), function(v) { return { name: v }})
        if(d.model.columns) self.cols = d.model.columns
        self.count = d.data[0].count
        self.sortable = !!d.model.sortable
        common.get(url + "/auth/whoami", function(me) {
          self.loaded = true
          self.can_access = d.model.roles === undefined || _.includes(d.model.roles.read, me.role)
          self.update()
        })
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    this.setFolder = function(folder) {
      self.folder = folder
      self.act_as_tree = folder !== ''
      self.loaddatatype(1)
    }

    ////////////////////////////////////////////////////////////////////////////
    calc_value(row, col, locale) {
      value = _.get(row, col.name)
      if(col.tr) { value = value[locale] }
      if(col.truncate) { value = value.substring(0,col.truncate) }
      if(col.capitalize) { value = _.capitalize(value) }
      if(col.uppercase) { value = _.toUpper(value) }
      if(col.downcase) { value = _.toLower(value) }
      return value
    }

    ////////////////////////////////////////////////////////////////////////////
    filter(e) {
      e.preventDefault();
      if(self.refs.term.value != "") {
        $(".uk-form-icon i").attr("class", "uk-icon-spin uk-icon-spinner")
        common.get(url + "/cruds/datatypes/search/"+self.refs.term.value, function(d) {
          self.data = d.data
          $(".uk-form-icon i").attr("class", "uk-icon-search")
          self.update()
        })
      }
      else {
        self.loaddatatype(1)
      }
    }

    ////////////////////////////////////////////////////////////////////////////
    edit(e) {
      route("/datatypes/" + e.item.row._key + "/edit")
    }

    ////////////////////////////////////////////////////////////////////////////
    nextpage(e) {
      self.datatype += 1
      self.loaddatatype(self.datatype + 1)
    }

    ////////////////////////////////////////////////////////////////////////////
    previouspage(e) {
      self.datatype -= 1
      self.loaddatatype(self.datatype + 1)
    }

    ////////////////////////////////////////////////////////////////////////////
    destroy_object(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.delete(url + "/cruds/datatypes/" + e.item.row._key, function() {
          self.loaddatatype(self.datatype + 1)
        })
      }, function() {})
    }

    ////////////////////////////////////////////////////////////////////////////
    toggleField(e) {
      e.preventDefault()
      common.patch(url + "/cruds/datatypes/" + e.target.dataset.key + "/" + e.item.col.name + "/toggle", "{}", function(data) {
        if(data.success) {
          e.target.innerText = data.data
        }
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    setperpage(e) {
      e.preventDefault()
      var perpage = parseInt(e.srcElement.innerText)
      if(e.srcElement.innerText == 'ALL') perpage = 1000000000;
      this.perpage = perpage
      this.loaddatatype(1)
    }

    ////////////////////////////////////////////////////////////////////////////
    export_data(e) {
      common.get(url + '/cruds/datatypes/export', function(d) {
        var csvContent = d.data
        var encodedUri = encodeURI(csvContent)
        var link = document.createElement("a")
        link.setAttribute("href", encodedUri)
        link.setAttribute("download", "datatypes.csv")
        link.innerHTML= "Click Here to download"
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    this.on('updated', function() {
      if(self.sortable) {
        var el = document.getElementById('list');
        var sortable = new Sortable(el, {
          animation: 150,
          ghostClass: 'blue-background-class',
          handle: '.fa-grip-vertical',
          onSort: function (/**Event*/evt) {
            var folder_key = "?folder_key=" + self.folder._key
            if(!self.act_as_tree) folder_key = ''
            common.put(
              url + 'cruds/datatypes/orders/' + evt.oldIndex + "/" + evt.newIndex + folder_key, {},
              function() {}
            )
          },
        });
      }
    })
  </script>
</datatypes>

