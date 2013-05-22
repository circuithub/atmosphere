_ = require "underscore"
should       = require "should"



###############################
## TEST HELPERS

exports.shouldNotHaveErrors = (errors) ->
  if errors?
    errorsString = ""
    if Array.isArray errors
      errorsString = (for e in errors then "#{e?.code}: #{e?.message}").join "\n"      
    else
      if errors.code?
        errorsString = (for k,e of errors then "#{e?.code}: #{e?.message}").join "\n"    
      else
        for k, job of errors 
          errorsString += (for k,e of job then "#{e?.code}: #{e?.message}").join "\n"    
    should.fail errorsString, ""
      
#Allowed Error Formats:
#Array:
#   [ {id, code, message}, undefined, {id, code, message}, ... ]  ---  array of objects, undefined (no errors) allowed
#Object:
#   { 
#       keyName1: [ {id, code, message}, undefined, {id, code, message}, ... ] 
#       keyName2: undefined
#   }
exports.shouldHaveErrors = (errors) ->
  should.exist errors
  if Array.isArray errors    
    errors.should.not.be.empty
    for e in errors
      should.exist e.id
      should.exist e.code
      should.exist e.message
  else
    errors.should.be.an.instanceof Object # (Must be a circuithub error)
    keys = _.keys errors
    for i in [0...keys.length]
      value = errors[keys[i]]
      if value?      
        should.exist value[0].id
        should.exist value[0].code
        should.exist value[0].message

#Determines is a specific error occurred
exports.shouldHaveError = (errors, errorCode) ->  
  shouldHaveErrors errors
  errorCodeExists = false
  return error for error in errors when error.code is errorCode
  errorCodeExists.should.equal true