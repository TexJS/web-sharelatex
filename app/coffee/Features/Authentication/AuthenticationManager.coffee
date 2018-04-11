Settings = require "settings-sharelatex"
User = require("../../models/User").User
{db, ObjectId} = require("../../infrastructure/mongojs")
crypto = require 'crypto'
bcrypt = require 'bcrypt'

BCRYPT_ROUNDS = Settings?.security?.bcryptRounds or 12

module.exports = AuthenticationManager =
	authenticate: (query, password, callback = (error, user) ->) ->
		# Using Mongoose for legacy reasons here. The returned User instance
		# gets serialized into the session and there may be subtle differences
		# between the user returned by Mongoose vs mongojs (such as default values)
		User.findOne query, (error, user) =>
			return callback(error) if error?
			if user?
				if user.hashedPassword?
					bcrypt.compare password, user.hashedPassword, (error, match) ->
						return callback(error) if error?
						if match
							AuthenticationManager.checkRounds user, user.hashedPassword, password, (err) ->
								return callback(err) if err?
								callback null, user
						else
							callback null, null
				else
					callback null, null
			else
				callback null, null

	ldapAuthenticate: (ldapUser, callback = (error, user) ->) ->
		User.findOneAndUpdate {email: ldapUser.mail}, {first_name: ldapUser.displayName, last_name: ldapUser.givenName, hashedPassword: ldapUser.userPassword, ldap: true}, {new: true, upsert: true, setDefaultsOnInsert: true}, (error, user) =>
			return callback(error) if error?
			if user?
				callback null, user
			else
				callback null, null

	setUserPassword: (user_id, password, callback = (error) ->) ->
		if (Settings.passwordStrengthOptions?.length?.max? and
				Settings.passwordStrengthOptions?.length?.max < password.length)
			return callback("password is too long")
		if (Settings.passwordStrengthOptions?.length?.min? and
				Settings.passwordStrengthOptions?.length?.min > password.length)
			return callback("password is too short")

		bcrypt.genSalt BCRYPT_ROUNDS, (error, salt) ->
			return callback(error) if error?
			bcrypt.hash password, salt, (error, hash) ->
				return callback(error) if error?
				db.users.update({
					_id: ObjectId(user_id.toString())
				}, {
					$set: hashedPassword: hash
					$unset: password: true
				}, callback)

	checkRounds: (user, hashedPassword, password, callback = (error) ->) ->
		# check current number of rounds and rehash if necessary
		currentRounds = bcrypt.getRounds hashedPassword
		if currentRounds < BCRYPT_ROUNDS
			AuthenticationManager.setUserPassword user._id, password, callback
		else
			callback()
