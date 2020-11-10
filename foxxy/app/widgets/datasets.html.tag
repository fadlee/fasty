<dataset_folders>
  <div>
    <ul class="uk-breadcrumb">
      <li each={ f in path }><a href="#datasets/{opts.slug}/{f._key}">{ f.name }</a></li>
      <li>
        <a if={ path.length > 1 } onclick={renameFolder}><i class="far fa-edit"></i></a>
        <a onclick={addFolder}><i class="fas fa-plus"></i></a>
        <a if={ path.length > 1 && folders.length == 0 } onclick={deleteFolder}><i class="fas fa-trash"></i></a>
      </li>
    </ul>
    <ul class="uk-list">
      <li each={f in folders}><a href="#datasets/{opts.slug}/{f._key}"><i class="far fa-folder" /> {f.name}</a></li>
    </ul>
  </div>
  <script>
    this.folders = []
    this.folder = {}
    this.path = [ this.folder ]
    this.folder_key = this.opts.folder_key || ''
    var self = this

    var loadFolder = function(folder_key) {
      common.get(url + "/datasets/folders/" + opts.slug + "/" + folder_key, function(d) {
        self.folders = d.folders
        self.path = d.path
        self.folder = _.last(self.path)
        self.parent.setFolder(self.folder)
        self.update()
      })
    }

    addFolder(e) {
      var name = prompt("Folder's name");
      common.post(url + "/datasets/folders/" + opts.slug, JSON.stringify({ name: name, parent_id: self.folder._key }), function(d) {
        loadFolder(self.folder._key)
      })
    }

    renameFolder(e) {
      var name = prompt("Update Folder's name");
      common.patch(url + "/datasets/folders/" + opts.slug, JSON.stringify({ name: name, id: self.folder._key }), function(d) {
        self.path = d.path
        self.update()
      })
    }

    deleteFolder(e) {
      UIkit.modal.confirm('Are you sure? This action will destroy the folder and it\'s content').then(function() {
        var parent = _.last(_.initial(self.path))
        common.delete(url + "/datasets/folders/" + opts.slug + "/" + self.folder._key, function(d) {
          common.get(url + "/datasets/folders/" + opts.slug + "/" + parent._key, function(d) {
            route("/datasets/" + opts.slug + "/" + parent._key)
          })
        })
      }, function () {
        console.log('Rejected.')
      });
    }

    loadFolder(this.folder_key)
  </script>
</dataset_folders>

<dataset_crud_index>

  <a href="#" class="uk-button uk-button-small uk-button-default" onclick={ new_item }>
    <i class="fas fa-plus"></i> New { opts.singular }
  </a>

  <table class="uk-table uk-table-striped" if={data.length > 0}>
    <thead>
      <tr>
        <th width="20" if={sortable}></th>
        <th each={ col in cols }>
          {col.name == undefined ? col : col.label === undefined ? col.name : col.label}
        </th>
        <th width="70"></th>
      </tr>
    </thead>
    <tbody id="sublist">
      <tr each={ row in data } >
        <td if={sortable}><i class="fas fa-grip-vertical handle"></i></td>
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
    <li if={ page > 0 } ><a onclick={ previousPage }><span class="uk-margin-small-right" uk-pagination-previous></span> Previous</a></li>
    <li if={ (page + 1) * perpage < count} class="uk-margin-auto-left"><a onclick={ nextPage }>Next <span class="uk-margin-small-left" uk-pagination-next></span></a></li>
  </ul>

  <script>
    this.sortable = false
    this.data     = []

    var self = this

    new_item(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "dataset_crud_new", opts)
    }
    ////////////////////////////////////////////////////////////////////////////
    this.loadPage = function(pageIndex) {
      common.get(url + "datasets/"+opts.parent_name+"/"+ opts.parent_id + "/"+opts.model+"/page/"+pageIndex+"/"+per_page, function(d) {
        self.data = d.data[0].data
        var model = d.model
        self.cols = _.map(common.array_diff(common.keys(self.data[0]), ["_id", "_key", "_rev"]), function(v) { return { name: v }})
        if(model.columns) self.cols = model.columns
        self.sortable = !!model.sortable
        self.count = d.data[0].count
        self.update()
      })
    }
    this.loadPage(1)
    ////////////////////////////////////////////////////////////////////////////
    edit(e) {
      e.preventDefault()
      opts.element_id = e.item.row._key
      riot.mount("#"+opts.id, "dataset_crud_edit", opts)
    }
    ////////////////////////////////////////////////////////////////////////////
    nextPage(e) {
      e.preventDefault()
      self.page += 1
      self.loadPage(self.page + 1)
    }
    ////////////////////////////////////////////////////////////////////////////
    previousPage(e) {
      e.preventDefault()
      self.page -= 1
      self.loadPage(self.page + 1)
    }
    ////////////////////////////////////////////////////////////////////////////
    destroy_object(e) {
      e.preventDefault()
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.delete(url + "/datasets/" + opts.parent_name + "/" + opts.model +"/" + e.item.row._key, function() {
          self.loadPage(1)
        })
      }, function() {})
    }
    ////////////////////////////////////////////////////////////////////////////
    this.on('updated', function() {
      if(self.sortable) {
        var el = document.getElementById('sublist');
        if(el)
          var sortable = new Sortable(el, {
            animation: 150,
            ghostClass: 'blue-background-class',
            handle: '.fa-grip-vertical',
            onSort: function (/**Event*/evt) {
              common.put(
                url + 'datasets/'+ opts.id +'/orders/' + evt.oldIndex + "/" + evt.newIndex, {},
                function() {}
              )
            },
          });
      }
    })
  </script>
</dataset_crud_index>

<dataset_crud_edit>
  <a href="#" class="uk-button uk-button-link" onclick={ goback }>Back to { opts.id }</a>
  <form onsubmit="{ save_form }" class="uk-form" id="{opts.id}_crud_{opts.singular}">
  </form>

  <script>
    goback(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "dataset_crud_index", opts)
    }

    save_form(e) {
      e.preventDefault()
      common.saveForm(opts.id+'_crud_'+opts.singular, "datasets/sub/"+opts.parent_name+"/"+ opts.id+"/"+opts.element_id, "")
    }

    var self = this;
    common.get(url + "/datasets/" + opts.parent_name + "/sub/" + opts.id + "/" + opts.element_id, function(d) {
      self.subdata = d.data

      common.buildForm(self.subdata, opts.fields, '#'+opts.id+'_crud_' + opts.singular)
    })
    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
  </script>
</dataset_crud_edit>

<dataset_crud_new>
  <a href="#" class="uk-button uk-button-link" onclick={ goback }>Back to { opts.id }</a>
  <form onsubmit="{ save_form }" class="uk-form" id="{opts.id}_crud_dataset">
  </form>

  <script>
    var self = this
    this.crud = {}
    this.crud[opts.key] = opts.parent_id

    goback(e) {
      e.preventDefault()
      riot.mount("#"+opts.id, "dataset_crud_index", opts)
    }

    this.on('mount', function() {
      common.buildForm(self.crud, opts.fields, '#'+opts.id+'_crud_dataset')
    })

    save_form(e) {
      e.preventDefault()
      common.saveForm(opts.id+'_crud_dataset', "datasets/"+ opts.parent_name +"/" + opts.parent_id + "/"+ opts.id, "", opts)
    }
  </script>
</dataset_crud_new>

<all_datatypes>
  <div class="rightnav uk-card uk-card-default uk-card-body">
    <ul class="uk-nav-default uk-nav-parent-icon" uk-nav>
      <li class="uk-nav-header">Datasets</li>
      <li each={datatypes}><a href="#datasets/{slug}">{name}</a></li>
    </ul>
  </div>
  <script>
    var self = this
    this.datatypes = []
    common.get(url + "/datasets/datatypes", function(data) {
      self.datatypes = data
      self.update()
    })
  </script>
  <style>

  </style>
</all_datatypes>

<dataset_edit>
  <virtual if={can_access}>
    <ul uk-tab>
      <li><a href="#">datasets</a></li>
      <li each={ i, k in sub_models }><a href="#">{ k }</a></li>
    </ul>

    <ul class="uk-switcher uk-margin">
      <li>
        <h3>Editing {object.singular}</h3>
        <virtual if={folders.length > 0}>
          <label class="uk-label">Path</label>
          <form onsubmit={changePath}>
            <div class="uk-grid uk-grid-small">
              <div class="uk-width-3-4">
                <select class="uk-select" ref="folder">
                  <option value={folders[0].root._key} selected={folders[0].root._key == dataset.folder_key}>Root</option>
                  <option each={f in folders} value={f.folder._key} selected={f.folder._key == dataset.folder_key}>{ pathName(f.path) }</option>
                </select>
              </div>
              <div class="uk-width-1-4">
                <a onclick={changePath} class="uk-button uk-button-primary">Change</a>
              </div>
            </div>
          </form>
        </virtual>

        <form onsubmit="{ save_form }" class="uk-form" id="form_dataset">
        </form>
        <a if={publishable} class="uk-button uk-button-primary" onclick="{ publish }">Publish</a>
        <a class="uk-button uk-button-secondary" onclick="{ duplicate }">Duplicate</a>
      </li>
      <li each={ i, k in sub_models }>
        <div id={ k } class="crud"></div>
      </li>
    </ul>
  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this page...
  </virtual>

  <script>
    var self = this
    self.can_access = false
    self.loaded = false
    self.sub_models = []
    self.publishable = false
    self.folders = []

    changePath(e) {
      e.preventDefault()
      common.put(url + "/datasets/pages/" + opts.dataset_id + "/change_folder", JSON.stringify({ folder_key: self.refs.folder.value}), function(d) {
        UIkit.notification({
            message : 'Successfully updated!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
      })
    }

    save_form(e) {
      e.preventDefault()
      common.saveForm("form_dataset", "datasets/" + opts.datatype, opts.dataset_id)
    }

    duplicate(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.get(url + "/datasets/"+ opts.datatype +"/" + self.dataset._key + "/duplicate", function(data) {
          route('/datasets/'+ opts.datatype + '/' + data._key + '/edit')
          UIkit.notification({
            message : 'Successfully duplicated!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
        })
      }, function() {})
    }

    pathName(path) {
      return _.map(path, function(p) { return p.name }).join(" > ")
    }

    publish(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.post(url + "/datasets/" + self.dataset._key + "/publish", JSON.stringify({}), function(data) {
          UIkit.notification({
            message : 'Successfully published!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
        })
      })
    }

    common.get(url + "/datasets/" + opts.datatype + "/" + opts.dataset_id, function(d) {
      self.publishable = d.model.publishable
      self.object = d.model
      self.dataset = d.data
      self.folders = d.folders
      self.fields = d.fields
      self.sub_models = d.model.sub_models
      var act_as_tree = d.model.act_as_tree

      if(!_.isArray(self.fields)) fields = fields.model
      common.get(url + "/auth/whoami", function(me) {
        localStorage.setItem('resize_api_key', me.resize_api_key)
        self.can_access = d.fields.roles === undefined || _.includes(d.fields.roles.write, me.role)
        self.loaded = true
        self.update()
        if(self.can_access)
          var back_url = 'datasets/' + opts.datatype
          if(act_as_tree && self.dataset.folder_key) { back_url += '/' + self.dataset.folder_key }
          common.buildForm(self.dataset, self.fields, '#form_dataset', back_url, function() {
            $(".crud").each(function(i, c) {
              var id = $(c).attr("id")
              riot.mount("#" + id, "dataset_crud_index", { model: id,
                fields: self.sub_models[id].fields,
                key: self.sub_models[id].key,
                singular: self.sub_models[id].singular,
                columns: self.sub_models[id].columns,
                parent_id: opts.dataset_id,
                parent_name: opts.datatype })
            })
          })
      })
    })

    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
</dataset_edit>

<dataset_new>
  <virtual if={can_access}>
    <h3>Creating {object.singular}</h3>
    <form onsubmit="{ save_form }" class="uk-form" id="form_new_dataset">
    </form>
  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this page...
  </virtual>
  <script>
    var self = this
    self.can_access = false
    self.loaded = false

    save_form(e) {
      e.preventDefault()
      common.saveForm("form_new_dataset", "datasets/" + opts.datatype)
    }

    common.get(url + "/datasets/"+ opts.datatype + "/fields", function(d) {
      self.object = d.object
      common.get(url + "/auth/whoami", function(me) {
        localStorage.setItem('resize_api_key', me.resize_api_key)
        self.can_access = d.fields.roles === undefined || _.includes(d.fields.roles.write, me.role)
        self.loaded = true
        self.update()
        if(self.can_access) {
          var fields = d.fields
          var obj = {}
          var back_url = 'datasets/' + opts.datatype
          if(self.opts.folder_key) {
            fields.push({ r: true, c: "1-1", n: "folder_key", t: "hidden" })
            obj['folder_key'] = opts.folder_key
            back_url += '/' + opts.folder_key
          }

          common.buildForm(obj, fields, '#form_new_dataset', back_url);
        }
      })
    })

    this.on('updated', function() {
      $(".select_list").select2()
      $(".select_mlist").select2()
      $(".select_tag").select2({ tags: true })
    })
  </script>
</dataset_new>

<dataset_tags>
  <span each={ row in data }>
    { row.tag } <span class="uk-badge uk-margin-right">{ row.size }</span>
  </span>
  <script>
    var self = this
    common.get(url + "/datasets/" + opts.datatype + "/stats/" + this.opts.tag, function(d) {
      self.data = d
      self.update()
    })
  </script>
</dataset_tags>

<datasets>
  <dataset_folders show={loaded} if={act_as_tree} folder_key={folder_key} slug={opts.datatype} />
  <virtual if={can_access}>
    <div class="uk-float-right">
      <a if={act_as_tree} href="#datasets/{opts.datatype}/new/{folder_key}" class="uk-button uk-button-small uk-button-default"><i class="fas fa-plus"></i> New { model.singular }</a>
      <a if={!act_as_tree} href="#datasets/{opts.datatype}/new" class="uk-button uk-button-small uk-button-default"><i class="fas fa-plus"></i> New { model.singular }</a>

      <a if={ export } onclick="{ export_data }" class="uk-button uk-button-small uk-button-primary"><i class="fas fa-file-export"></i> Export CSV</a>
    </div>
    <h3>Listing { opts.datatype }</h3>

    <form onsubmit={filter} class="uk-margin-top">
      <div class="uk-inline uk-width-1-1">
        <span class="uk-form-icon" uk-icon="icon: search"></span>
        <input type="text" ref="term" id="term" class="uk-input" autocomplete="off">
      </div>
    </form>

    <dataset_tags if={ show_stats } datatype={ opts.datatype } tag={ show_stats_tag }></dataset_tags>
    <table class="uk-table uk-table-striped">
      <thead>
        <tr>
          <th if={sortable} width="20"></th>
          <th each={ col in cols } class="{col.class}">{col.name == undefined ? col : col.label === undefined ? col.name : col.label}</th>
          <th width="70"></th>
        </tr>
      </thead>
      <tbody id="list">
        <tr each={ row in data } no-reorder key={row._key}>
          <td if={sortable}><i class="fas fa-grip-vertical handle"></i></td>
          <td each={ col in cols } class="{col.class}">
            <virtual if={col.trads == true}>
              <div each={lang in langs}><a onclick={traduct} data-lang={lang} data-id={row._key} data-value={calc_value(row, col, lang)} class="uk-button uk-button-small">{lang} :</a> <span id="trad_{lang}_{row._key}">{ calc_value(row, col, lang) }</span></div>
            </virtual>

            <virtual if={col.trads != true}>
              <virtual if={ col.toggle == true } >
              <virtual if={ col.tr == true }><a style="color: { col.colors ? col.colors[row[col.name][locale]] : 'white' }" onclick={toggleField} data-key="{row._key}">{col.values ? col.values[row[col.name][locale]] : _.get(row,col.name)[locale]}</a></virtual>
              <virtual if={ col.tr != true }><a style="color: {col.colors ? col.colors[row[col.name]] : 'white' }" onclick={toggleField} data-key="{row._key}">{col.values ? col.values[row[col.name]] : _.get(row,col.name) }</a></virtual>
              </virtual>

              <virtual if={ col.toggle != true } >
                <virtual if={ col.type == "image" }>
                  <img src="{calc_value(row, col, locale)} " style="height:25px">
                </virtual>
                <virtual if={ col.type != "image" }>
                  { calc_value(row, col, locale) }
                </virtual>
              </virtual>
            </virtual>
          </td>
          <td class="uk-text-center" width="160">
            <a onclick={edit} class="uk-button uk-button-primary uk-button-small"><i class="fas fa-edit"></i></a>
            <a if={is_api} onclick={install} class="uk-button uk-button-success uk-button-small"><i class="fas fa-upload"></i></a>
            <a if={is_script} onclick={install_script} class="uk-button uk-button-success uk-button-small"><i class="fas fa-upload"></i></a>
            <a onclick={destroy_object} class="uk-button uk-button-danger uk-button-small" ><i class="fas fa-trash-alt"></i></a>
          </td>
        </tr>
      </tbody>
    </table>
    <div id="moreitems" style="height: 50px;">{loaded ? "" : "Loading ..."}</div>

  </virtual>
  <virtual if={!can_access && loaded}>
    Sorry, you can't access this page...
  </virtual>
  <script>
    var self        = this
    
    this.show_stats = false
    this.page       = 1
    this.perpage    = localStorage.getItem("perpage") || per_page
    this.locale     = window.localStorage.getItem('foxx-locale')
    this.data       = []
    this.export     = false
    this.can_access = false
    this.sortable   = false
    this.loaded     = false
    this.folder_key = this.opts.folder_key || ''
    this.folder     = {}
    this.reach_end  = false
    this.act_as_tree = true

    this.settings   = {}

    common.get(url + "/settings", function(settings) { self.settings = settings.data })

    this.loadPage = function(pageIndex) {
      self.loaded = false
      self.update()
      var querystring = "?folder=" + self.folder._key + "&is_root=" + self.folder.is_root

      common.get(url + "/datasets/" + opts.datatype + "/page/" + pageIndex + "/" + this.perpage + querystring, function(d) {
        self.reach_end = d.data[0].data.length == 0
        _.each(d.data[0].data, function(d) { self.data.push(d) })

        var model = d.model
        self.model = d.model

        self.act_as_tree = model.act_as_tree
        self.is_api = !!model.is_api
        self.is_script = !!model.is_script
        if(model.stats_for_tag) {
          self.show_stats = true
          self.show_stats_tag = model.stats_for_tag
          self.update()
        }
        self.export = !!model.export
        self.cols = _.map(common.array_diff(common.keys(self.data[0]), ["_id", "_key", "_rev"]), function(v) { return { name: v }})
        if(model.columns) self.cols = model.columns
        self.count = d.data[0].count
        self.sortable = !!model.sortable
        self.loaded = true
        self.langs = d.langs
        self.update()

        if(self.can_access == false) {
          common.get(url + "/auth/whoami", function(me) {
            localStorage.setItem('resize_api_key', me.resize_api_key)
            self.can_access = model.roles === undefined || _.includes(model.roles.read, me.role)
            self.update()
          })
        }
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    this.setFolder = function(folder) {
      self.folder = folder || {}
      self.folder_key = self.folder._key
      self.loadPage(1)
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
    traduct(e) {
      e.preventDefault()
      var lang = e.item.lang
      var id = $(e.srcElement).data("id")
      var traduction = prompt(lang, $(e.srcElement).data("value"))
      if(traduction) {
        common.patch(url + "/datasets/" + opts.datatype + "/" + id + "/value/" + lang + "/field", JSON.stringify({ value: traduction }), function(d) {
          $("#trad_" + lang + "_" + id).text(traduction)
          $(e.srcElement).data("value", traduction)
        })
      }
      
      return false
    }


    ////////////////////////////////////////////////////////////////////////////
    filter(e) {
      e.preventDefault();
      if(self.refs.term.value != "") {
        $(".uk-form-icon i").attr("class", "uk-icon-spin uk-icon-spinner")
        common.get(url + "/datasets/"+ opts.datatype +"/search/"+self.refs.term.value, function(d) {
          self.data = d.data
          $(".uk-form-icon i").attr("class", "uk-icon-search")
          self.update()
        })
      }
      else {
        self.loadPage(1)
      }
    }

    ////////////////////////////////////////////////////////////////////////////
    edit(e) {
      route("/datasets/" + this.opts.datatype + "/" + e.item.row._key + "/edit")
    }

    ////////////////////////////////////////////////////////////////////////////
    new_dataset(e) {
      route("/datasets/" + this.opts.datatype + "/new")
    }

    ////////////////////////////////////////////////////////////////////////////
    destroy_object(e) {
      UIkit.modal.confirm("Are you sure?").then(function() {
        common.delete(url + "/datasets/" + opts.datatype + "/" + e.item.row._key, function() {
          self.loadPage(self.page + 1)
        })
      }, function() {})
    }

    ////////////////////////////////////////////////////////////////////////////
    toggleField(e) {
      e.preventDefault()
      common.patch(url + "/datasets/" + opts.datatype + "/" + e.target.dataset.key + "/" + e.item.col.name + "/toggle", "{}", function(data) {
        if(data.success) {
          e.target.innerText = data.data
        }
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    setPerPage(e) {
      e.preventDefault()
      var perpage = parseInt(e.srcElement.innerText)
      if(e.srcElement.innerText == 'ALL') perpage = 1000000000;
      this.perpage = perpage
      localStorage.setItem("perpage", perpage)
      this.loadPage(1)
    }

    ////////////////////////////////////////////////////////////////////////////
    export_data(e) {
      common.get(url + '/datasets/' + opts.datatype + '/export', function(d) {
        var csvContent = d.data
        var encodedUri = encodeURI(csvContent)
        var link = document.createElement("a")
        link.setAttribute("href", encodedUri)
        link.setAttribute("download", "datasets.csv")
        link.innerHTML= "Click Here to download"
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
      })
    }

    ////////////////////////////////////////////////////////////////////////////
    install(e) {
      e.preventDefault()
      var url = "/service/" + e.item.row.name
      $.post(url, { token: self.settings.token }, function(data) {
        if(data == "service installed")
          UIkit.notification({
            message : 'Endpoint Deployed Successfully!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
      })
      return false
    }

    ////////////////////////////////////////////////////////////////////////////
    install_script(e) {
      e.preventDefault()
      var url = "/script/" + e.item.row.name
      
      $.post(url, { token: self.settings.token }, function(data) {
        if(data == "script installed")
          UIkit.notification({
            message : 'Script Launched Successfully!',
            status  : 'success',
            timeout : 1000,
            pos     : 'bottom-right'
          });
      })
      return false
    }

    ////////////////////////////////////////////////////////////////////////////
    this.isElementInViewport = function(el) {
      var rect = el.getBoundingClientRect();

      return rect.bottom > 0 &&
          rect.right > 0 &&
          rect.left < (window.innerWidth || document.documentElement.clientWidth) /* or $(window).width() */ &&
          rect.top < (window.innerHeight || document.documentElement.clientHeight) + 300 /* or $(window).height() */;
    }

    ////////////////////////////////////////////////////////////////////////////
    this.on('mount', function() {
      $(window).on('DOMContentLoaded load resize scroll', function(i) {
        if(!self.reach_end && self.loaded && self.isElementInViewport(document.getElementById("moreitems"))) {
          self.page += 1
          self.loadPage(self.page)
        }
      })
    })

    ////////////////////////////////////////////////////////////////////////////
    this.on('updated', function() {
      if(self.sortable) {
        var el = document.getElementById('list');
        if(el) {
          var sortable = new Sortable(el, {
            animation: 150,
            ghostClass: 'blue-background-class',
            handle: '.fa-grip-vertical',
            onSort: function (/**Event*/evt) {
              var folder_key = "?folder_key=" + self.folder._key
              if(!self.act_as_tree) folder_key = ''
              common.put(
                url + 'datasets/'+ opts.datatype +'/orders/' + evt.oldIndex + "/" + evt.newIndex + folder_key, {},
                function() {}
              )
            },
          });
        }

      }
    })
  </script>
</datasets>