# Bundles allow macros and blocks to be bundled and initialized together. This
# makes it easy to create and distribute functionality, as well as configure 
# automatic bundle loading within your own environment.
#
# The bundle [**must**] include the static method `new_instance(TMD::Processor proc, Hash opts = nil)`
#
# If the class has `BUNDLE_ID` defined, the bundle will be registered with that
# id, otherwise, it will use its class name.
module TMD::Bundles

	# Helper module that automatically registers the bundle class extending it.
	module Bundle
		def self.included(clazz)
			id = nil
			if defined?(clazz::BUNDLE_ID)
				id = clazz::BUNDLE_ID
			else
				id = clazz.to_s.gsub('::', '_').downcase
			end
			Registry.register_bundle(clazz, id)
		end
	end

	# Maintains central registry of bundles.
	class Registry
		@@reg = {}

		def self.register_bundle(bundle, id)
			if !bundle.respond_to?(:new_instance)
				$stderr.write "registering bundle failed: #{bundle} does not have 'new_instance' method\n"
				return
			end

			if !@@reg[id]
				@@reg[id] = bundle
				$stderr.write "registering bundle #{id} => #{bundle}\n"
			else
				$stderr.write "registering bundle failed: #{id} already registered\n"
			end
		end

		def self.get_bundle(id)
			return @@reg[id]
		end

		def self.attach_bundle(id, proc)
			bundle = @@reg[id]
			if bundle
				bundle.new_instance(proc)
			end
		end

		def self.unregister_bundle(id)
			bundle = @@reg.delete(id)
			$stderr.write "unregistered bundle #{id} => #{bundle}\n"
		end
	end
end

require_relative './bundles/basics.rb'