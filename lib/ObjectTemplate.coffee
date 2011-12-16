
sysmo = require 'sysmo'
TemplateConfig = require './TemplateConfig'

class ObjectTemplate
  constructor: (config, parent) ->
    @config = new TemplateConfig config
    @parent = parent
  
  transform: (data) =>
    node = @nodeToProcess data
    
    return null if !node?
    
    # process properties
    switch sysmo.type node
      when 'Array'  then @processArray node
      when 'Object' then @processMap node
      else null #node
  
  # assume each array element is a map
  processArray: (node) =>
    # convert array to hash if config.arrayToMap is true
    context = if @config.arrayToMap then {} else []
    
    for element, index in node when @config.processable node, element, index
      # convert the index to a key if converting array to map 
      # @updateContext handles the context type automatically
      index = @chooseKey(element) if @config.arrayToMap
      value = @chooseValue(element, {})
      @updateContext context, element, value, index
    context
  
  processMap: (node) =>
    
    context = {}
    
    return @chooseValue(node, context) if !@config.nestTemplate
    
    # loop through properties to pick up any key/values that should be nested
    for key, value of node when @config.processable node, value, key
      # call @getNode() to register the use of the property on that node
      value = @chooseValue @getNode(node, key), {}
      @updateContext context, element, value, key
    context
    
  processTemplate: (node, context, template = {}) =>
    
    # loop through properties in template
    for key, value of template
      # process mapping instructions
      switch sysmo.type value
        # string should be the path to a property on the current node
        when 'String'   then  filter = (node, path)   => result = @getNode(node, path) or null
        # array gets multiple property values
        when 'Array'    then  filter = (node, paths)  => @getNode(node, path) for path in paths
        # function is a custom filter for the node
        when 'Function' then  filter = (node, value)  => value.call(@, node, key)
        when 'Object'   then  filter = (node, config) => new @constructor(config, @).transform node
        else                  filter = (node, value)  -> value
      
      value = filter(node, value)
      @updateContext context, node, value, key
      @processRemaining context, node
      
    context
  
  processRemaining: (context, node) =>
    #return context if @config.nestTemplate
    
    # loop through properties to pick up any key/values that should be chosen
    # skip if node property already used, the property was specified by the template, or it should not be choose
    for key, value of node when !@pathAccessed(node, key) and key not in context and @config.processable node, value, key
      @updateContext context, node, value, key
    context
    
  updateContext: (context, node, value, key) =>
    # format key and value
    formatted = @config.applyFormatting node, value, key
    @aggregateValue(context, formatted.key, formatted.value)
      
  aggregateValue: (context, key, value) =>
    return context if !value?
    
    # if context is an array, just add the value
    if sysmo.isArray(context)
      context.push(formatted.value)
      return context
    
    existing = context[key]
    
    return context if @config.aggregate context, key, value, existing
    
    if !existing?
      context[key] = value
    else if !sysmo.isArray(existing)
      context[key] = [existing, value]
    else
      context[key].push value
      
    context
  
  chooseKey: (node) =>
    result = @config.getKey node
    switch result.name
      when 'value'    then result.value
      when 'path'     then @getNode node, result.value
      else null
    
  chooseValue: (node, context) =>
    result = @config.getValue node
    switch result.name
      when 'value'    then result.value
      when 'path'     then @getNode node, result.value
      when 'template' then @processTemplate node, context, result.value
      else null
  
  nodeToProcess: (node) =>
    @getNode node, @config.getPath()
  
  getNode: (node, path) =>
    return node if path is '.'
    @paths node, path
    sysmo.getDeepValue node, path, true
    
  pathAccessed: (node, path) =>
    key = path.split('.')[0]
    @paths(node).indexOf(key) isnt -1
    
  # track the first property in a path for each node through object tree
  paths: (node, path) =>
    path = path.split('.')[0] if path
    
    @pathNodes or= @parent and @parent.pathNodes or []
    @pathCache or= @parent and @parent.pathCache or []
    
    index = @pathNodes.indexOf node
    
    if !path
      return if index isnt -1 then @pathCache[index] else []
    
    if index is -1
      paths = []
      @pathNodes.push node
      @pathCache.push paths
    else
      paths = @pathCache[index]
    
    paths.push(path) if path and paths.indexOf(path) == -1
    paths
  
  templates: (name, config) =>
    if !@templateCache
      @templateCache = if @parent then @parent.templateCache else {}
    if name and !config
      @templateCache[name] or null
    else if name and config
      @templateCache[name] = @processConfig config
      @templateCache
    else
      @templateCache

# register module
module.exports = ObjectTemplate