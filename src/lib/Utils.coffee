#     NoFlo - Flow-Based Programming for JavaScript
#     (c) 2014 TheGrid (Rituwall Inc.)
#     NoFlo may be freely distributed under the MIT license
#
# Generic object clone. From CS cookbook
clone = (obj) ->
  if not obj? or typeof obj isnt 'object'
    return obj

  if obj instanceof Date
    return new Date(obj.getTime())

  if obj instanceof RegExp
    flags = ''
    flags += 'g' if obj.global?
    flags += 'i' if obj.ignoreCase?
    flags += 'm' if obj.multiline?
    flags += 'y' if obj.sticky?
    return new RegExp(obj.source, flags)

  newInstance = new obj.constructor()

  for key of obj
    newInstance[key] = clone obj[key]

  return newInstance

# Guess language from filename
guessLanguageFromFilename = (filename) ->
  return 'coffeescript' if /.*\.coffee$/.test filename
  return 'javascript'

exports.clone = clone
exports.guessLanguageFromFilename = guessLanguageFromFilename


# Ported to CoffeeScript from http://underscorejs.org/docs/underscore.html
# Underscore.js 1.8.3 http://underscorejs.org
# (c) 2009-2015 Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors
# Underscore may be freely distributed under the MIT license.
exports.debounce = (func, wait, immediate) ->
  timeout = null
  args = null
  context = null
  timestamp = null
  result = null

  later = () ->
    now = new Date().getTime()
    last = now - timestamp

    if last < wait and last >= 0
      timeout = setTimeout later, (wait - last)
    else
      timeout = null
      if not immediate
        result = func.apply context, args
        if not timeout
          context = args = null

  return () ->
    context = this
    args = arguments
    timestamp = new Date().getTime()
    callNow = immediate and !timeout
    if not timeout
      timeout = setTimeout later, wait
    if callNow
      result = func.apply context, args
      context = args = null

    return result
