class cola.WidgetDataModel extends cola.AbstractDataModel
	constructor: (model, @widget) ->
		super(model)

	_getRealPath: (dynaPath) ->
		index = dynaPath.indexOf(".")
		if index > 1
			realPath = @_transferDynaProperty(dynaPath.substring(1, index)) + dynaPath.substring(index)
		else
			realPath = @_transferDynaProperty(dynaPath.substring(1))
		return realPath

	get: (path, loadMode, context) ->
		if path.charCodeAt(0) is 64 # `@`
			return @model.parent?.data.get(@_getRealPath(path), loadMode, context)
		else
			return @widget.get(path)

	set: (path, value) ->
		if path.charCodeAt(0) is 64 # `@`
			@model.parent?.data.set(@_getRealPath(path), value)
		else
			@widget.set(path, value)
			@onDataMessage(path.split("."), cola.constants.MESSAGE_PROPERTY_CHANGE, {})
		return

	_bind: (path, processor) ->
		if path[0].charCodeAt(0) is 64 # `@`
			property = path[0].substring(1)
			if not @dynaPropertyMap
				@dynaPropertyMap = {}
				@dynaPropertyPathMap = {}

			if @dynaPropertyMap[property]
				@dynaPropertyMap[property] = @dynaPropertyMap[property] + 1
			else
				@dynaPropertyMap[property] = 1

		return super(path, processor)

	_unbind: (path, processor) ->
		if @dynaPropertyMap and path[0].charCodeAt(0) is 64 # `@`
			property = path[0].substring(1)
			if @dynaPropertyMap[property] > 1
				@dynaPropertyMap[property] = @dynaPropertyMap[property] - 1
			else
				delete @dynaPropertyMap[property]
				delete @dynaPropertyPathMap[property]

		return super(path, processor)

	_transferDynaProperty: (property, force = true) -> # TODO: force待优化
		if not @dynaPropertyPathMap.hasOwnProperty(property) or force
			path = @dynaPropertyPathMap[property]
			if path
				@model.unwatchPath(path)

			path = @widget.get(property)
			@dynaPropertyPathMap[property] = if path then path.split(".") else null

			if path
				@model.watchPath(path)
		else
			path = @dynaPropertyPathMap[property]
		return path

	processMessage: (bindingPath, path, type, arg) ->

		isParentPath = (targetPath, parentPath) ->
			isParent = true
			for part, i in parentPath
				targetPart = targetPath[i]
				if part isnt targetPart
					if targetPart is "**" then continue
					else if targetPart is "*"
						if i is parentPath.length - 1 then continue
					isParent = false
					break
			return isParent

		if @dynaPropertyPathMap
			for property, dynaPath of @dynaPropertyPathMap
				if isParentPath(dynaPath, path)
					if type is cola.constants.MESSAGE_REFRESH or type is cola.constants.MESSAGE_CURRENT_CHANGE or
						type is cola.constants.MESSAGE_PROPERTY_CHANGE or type is cola.constants.MESSAGE_REMOVE
							@_transferDynaProperty(property, true)
							@onDataMessage(["@" + property], cola.constants.MESSAGE_REFRESH, {})
				else if isParentPath(path, dynaPath)
					relativePath = path.slice(dynaPath.length)
					@onDataMessage(["@" + property].concat(relativePath), type, arg)
		return

	getDataType: (path) ->
		if path.charCodeAt(0) is 64 # `@`
			return @model.parent?.data.getDataType(path.substring(1))
		else
			return null

	getProperty: (path) ->
		if path.charCodeAt(0) is 64 # `@`
			return @model.parent?.data.getProperty(path.substring(1))
		else
			return null

	flush: (name, loadMode) ->
		if path.charCodeAt(0) is 64 # `@`
			@model.parent?.data.getDataType(name.substring(1), loadMode)
		return @

class cola.WidgetModel extends cola.SubScope
	repeatNotification: true

	constructor: (@widget, @parent) ->
		widget = @widget
		@data = new cola.WidgetDataModel(@, widget)

		@action = (name) ->
			method = widget[name]
			if method instanceof Function
				return () -> method.apply(widget, arguments)
			return widget._scope.action(name)

	processMessage: (bindingPath, path, type, arg) ->
		if @messageTimestamp >= arg.timestamp then return
		return @data.processMessage(bindingPath, path, type, arg)

class cola.TemplateWidget extends cola.Widget