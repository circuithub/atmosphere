nconf          = require "nconf"
elma           = require("elma")(nconf)
adt =
  typecheck:    require "adt-typecheck.js"

# This is a modification of adt-typecheck-signature.js which is in the public
# domain under the CC0 public domain dedication:
# The function is modified to return an array of CircuitHub errors rather than a
# single error as is normal node convention.

exports.cfn = (schemaF, f) =>
  @_typecheck schemaF, f, true

exports.fn = (schemaF, f) =>
  @_typecheck schemaF, f, false

exports._typecheck = (schemaF, f, chained) ->
  if typeof schemaF != 'function'
    throw "No type signature supplied to `types.cfn`."
  if typeof f != 'function'
    throw "No node function supplied to `types.cfn`."
  expectedNumArgs = 0
  check = adt.typecheck ->
    s = schemaF.call @
    if s.length < 1
      throw "Too few arguments in chain function, a callback function is required."
    # Note: in order to avoid adt.js as a dependency, check whether the last
    #       object in the signature is a function signature manually
    #       (depends on the _tag property added by adt.js)
    #if not isFunctionADT s[s.length - 1]
    if chained
      if s[s.length - 1]?._tag? and s[s.length - 1]?._tag != 'Function'
        throw "The last argument in the chain function signature should be a Function."
    expectedNumArgs = s.length
    return this.Arguments s
  return ->
    errors = check arguments
    # It is not possible to pass along errors if no callback function is supplied
    if errors.length > 0
      if arguments.length != expectedNumArgs
        elma.error "typeError", "Expected #{expectedNumArgs} arguments, but received #{arguments.length}.\n#{adt.typecheck.show errors}", arguments
      if typeof arguments[arguments.length - 1] != 'function'
        elma.error "typeError", adt.typecheck.show errors, arguments
    callback = arguments[arguments.length - 1]
    if errors.length > 0
      # Generate CircuitHub errors instead of one long typecheck message
      callback elma.errors "typeError", (adt.typecheck.show e for e in errors), arguments
    else
      f arguments..., callback


classToType = {}
for name in "Boolean Number String Function Array Date RegExp".split(" ")
  classToType["[object " + name + "]"] = name.toLowerCase()

exports.type = (obj) ->
  if obj == undefined or obj == null
    return String obj
  myClass = Object.prototype.toString.call obj
  if myClass of classToType
    return classToType[myClass]
  return "object"