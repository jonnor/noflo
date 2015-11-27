#     NoFlo - Flow-Based Programming for JavaScript
#     (c) 2013-2014 TheGrid (Rituwall Inc.)
#     (c) 2013 Henri Bergius, Nemein
#     NoFlo may be freely distributed under the MIT license
#
# This is the Node.js version of the ComponentLoader.

reader = require 'read-installed'
path = require 'path'
fs = require 'fs'
loader = require '../ComponentLoader'
internalSocket = require '../InternalSocket'
utils = require '../Utils'
nofloGraph = require '../Graph'

# We allow components to be un-compiled CoffeeScript
CoffeeScript = require 'coffee-script'
if typeof CoffeeScript.register != 'undefined'
  CoffeeScript.register()
babel = require 'babel-core'

# Disable NPM logging in normal NoFlo operation
log = require 'npmlog'
log.pause()

# underscore.js style
after = (times, func) ->
  return () ->
    if --times < 1
      return func.apply this, arguments

class ComponentLoader extends loader.ComponentLoader
  getModuleComponents: (moduleDef, callback) ->
    components = {}
    @checked.push moduleDef.name

    depCount = Object.keys(moduleDef.dependencies).length
    done = after depCount + 1, =>
      callback components

    # Handle sub-modules
    moduleDef.dependencies.forEach (def) =>
      return done() unless def.name?
      return done() unless @checked.indexOf(def.name) is -1
      @getModuleComponents def, (depComponents) ->
        return done() if depComponents? or depComponents.length == 0
        components[name] = cPath for name, cPath of depComponents
        done()

    # No need for further processing for non-NoFlo projects
    return done() unless moduleDef.noflo

    checkOwn = (def) =>
      # Handle own components
      prefix = @getModulePrefix def.name

      # See if the library has a default icon
      if def.noflo.icon
        @libraryIcons[prefix] = def.noflo.icon

      if def.noflo.components
        for name, cPath of def.noflo.components
          @registerComponent prefix, name, path.resolve def.realPath, cPath
      if moduleDef.noflo.graphs
        for name, gPath of def.noflo.graphs
          @registerGraph prefix, name, path.resolve def.realPath, gPath
      if def.noflo.loader
        # Run a custom component loader
        loaderPath = path.resolve def.realPath, def.noflo.loader
        @componentLoaders = [] unless @componentLoaders
        @componentLoaders.push loaderPath
        loader = require loaderPath
        @registerLoader loader, done
      else
        done()

    # Normally we can rely on the module data we get from read-installed, but in
    # case cache has been cleared, we must re-read the file
    unless @revalidate
      return checkOwn moduleDef
    @readPackageFile "#{moduleDef.realPath}/package.json", (err, data) ->
      return done() if err
      checkOwn data

  getCoreComponents: (callback) ->
    # Read core components
    # TODO: These components should eventually be migrated to modules too
    corePath = path.resolve __dirname, '../../src/components'
    if path.extname(__filename) is '.coffee'
      # Handle the non-compiled version of ComponentLoader for unit tests
      corePath = path.resolve __dirname, '../../components'

    fs.readdir corePath, (err, components) =>
      coreComponents = {}
      return callback coreComponents if err
      for component in components
        continue if component.substr(0, 1) is '.'
        [componentName, componentExtension] = component.split '.'
        continue unless componentExtension is 'coffee'
        coreComponents[componentName] = "#{corePath}/#{component}"
      callback coreComponents

  cachePath: ->
    path.resolve @baseDir, './.noflo.json'

  writeCache: ->
    cacheData =
      components: {}
      loaders: @componentLoaders or []

    for name, cPath of @components
      continue unless typeof cPath is 'string'
      cacheData.components[name] = cPath

    filePath = @cachePath()
    fs.writeFile filePath, JSON.stringify(cacheData, null, 2),
      encoding: 'utf-8'
    , ->

  readCache: (callback) ->
    filePath = @cachePath()
    fs.readFile filePath,
      encoding: 'utf-8'
    , (err, cached) =>
      return callback err if err
      return callback new Error 'No cached components found' unless cached
      try
        cacheData = JSON.parse cached
      catch e
        callback e
      return callback new Error 'No components in cache' unless cacheData.components
      @components = cacheData.components
      unless cacheData.loaders?.length
        callback null
        return
      done = after cacheData.loaders.length, ->
        callback null
      cacheData.loaders.forEach (loaderPath) =>
        loader = require loaderPath
        @registerLoader loader, done

  listComponents: (callback) ->
    if @processing
      @once 'ready', =>
        callback @components
      return
    return callback @components if @components

    @ready = false
    @processing = true

    if @options.cache and not @failedCache
      @readCache (err) =>
        if err
          @failedCache = true
          @processing = false
          @listComponents callback
          return
        @ready = true
        @processing = false
        @emit 'ready', true
        callback @components if callback
      return

    @components = {}

    done = after 2, =>
      @ready = true
      @processing = false
      @emit 'ready', true
      callback @components if callback
      @writeCache() if @options.cache

    @getCoreComponents (coreComponents) =>
      @components[name] = cPath for name, cPath of coreComponents
      done()

    reader @baseDir, (err, data) =>
      return done() if err
      @getModuleComponents data, (components) =>
        @components[name] = cPath for name, cPath of components
        done()

  getPackagePath: (packageId, callback) ->
    found = null
    seen = []
    find = (packageData) ->
      return if seen.indexOf(packageData.name) isnt -1
      seen.push packageData.name
      if packageData.name is packageId
        found = path.resolve packageData.realPath, './package.json'
        return
      packageData.dependencies.forEach find
    reader @baseDir, (err, data) ->
      return callback err if err
      find data
      return callback null, found

  setSource: (packageId, name, source, language, callback) ->
    unless @ready
      @listComponents =>
        @setSource packageId, name, source, language, callback
      return

    Module = require 'module'
    if language is 'coffeescript'
      try
        source = CoffeeScript.compile source,
          bare: true
      catch e
        return callback e
    else if language in ['es6', 'es2015']
      try
        source = babel.transform(source).code
      catch e
        return callback e

    try
      # Use the Node.js module API to evaluate in the correct directory context
      modulePath = path.resolve @baseDir, "./components/#{name}.js"
      moduleImpl = new Module modulePath, module
      moduleImpl.paths = Module._nodeModulePaths path.dirname modulePath
      moduleImpl.filename = modulePath
      moduleImpl._compile source, modulePath
      implementation = moduleImpl.exports
    catch e
      return callback e
    unless implementation or implementation.getComponent
      return callback new Error 'Provided source failed to create a runnable component'
    @registerComponent packageId, name, implementation, ->
      callback null

  getSource: (name, callback) ->
    unless @ready
      @listComponents =>
        @getSource name, callback
      return

    component = @components[name]
    unless component
      # Try an alias
      for componentName of @components
        if componentName.split('/')[1] is name
          component = @components[componentName]
          name = componentName
          break
      unless component
        return callback new Error "Component #{name} not installed"

    if typeof component isnt 'string'
      return callback new Error "Can't provide source for #{name}. Not a file"

    nameParts = name.split '/'
    if nameParts.length is 1
      nameParts[1] = nameParts[0]
      nameParts[0] = ''

    if @isGraph component
      nofloGraph.loadFile component, (graph) ->
        return callback new Error 'Unable to load graph' unless graph
        callback null,
          name: nameParts[1]
          library: nameParts[0]
          code: JSON.stringify graph.toJSON()
          language: 'json'
      return

    fs.readFile component, 'utf-8', (err, code) ->
      return callback err if err
      callback null,
        name: nameParts[1]
        library: nameParts[0]
        language: utils.guessLanguageFromFilename component
        code: code

  readPackage: (packageId, callback) ->
    @getPackagePath packageId, (err, packageFile) =>
      return callback err if err
      return callback new Error 'no package found' unless packageFile
      @readPackageFile packageFile, callback

  readPackageFile: (packageFile, callback) ->
    fs.readFile packageFile, 'utf-8', (err, packageData) ->
      return callback err if err
      data = JSON.parse packageData
      data.realPath = path.dirname packageFile
      callback null, data

  writePackage: (packageId, data, callback) ->
    @getPackagePath packageId, (err, packageFile) ->
      return callback err if err
      return callback new Error 'no package found' unless packageFile
      delete data.realPath if data.realPath
      packageData = JSON.stringify data, null, 2
      fs.writeFile packageFile, packageData, callback

  registerComponentToDisk: (packageId, name, cPath, callback = ->) ->
    @readPackage packageId, (err, packageData) =>
      return callback err if err
      packageData.noflo = {} unless packageData.noflo
      packageData.noflo.components = {} unless packageData.noflo.components
      packageData.noflo.components[name] = cPath
      @clear()
      @writePackage packageId, packageData, callback

  registerGraphToDisk: (packageId, name, cPath, callback = ->) ->
    @readPackage packageId, (err, packageData) =>
      return callback err if err
      packageData.noflo = {} unless packageData.noflo
      packageData.noflo.graphs = {} unless packageData.noflo.graphs
      packageData.noflo.graphs[name] = cPath
      @clear()
      @writePackage packageId, packageData, callback

exports.ComponentLoader = ComponentLoader
